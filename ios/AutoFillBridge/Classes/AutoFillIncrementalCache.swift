import CryptoKit
import Darwin
import Foundation

enum AutoFillV3Error: Error {
    case recoveryRequired, staleBase, writerInvalidated, invalid
    var code: String {
        switch self {
        case .recoveryRequired: return "AUTOFILL_FULL_RECOVERY_REQUIRED"
        case .staleBase: return "AUTOFILL_STALE_BASE"
        case .writerInvalidated: return "AUTOFILL_WRITER_INVALIDATED"
        case .invalid: return "AUTOFILL_CACHE_ERROR"
        }
    }
}

struct AutoFillV3Base: Equatable {
    let generation: Int
    let revision: Int
    init(generation: Int, revision: Int) { self.generation = generation; self.revision = revision }
    init(_ raw: [String: Any]) throws {
        guard Set(raw.keys) == ["generation", "revision"],
              let generation = AutoFillV3JSON.positive(raw["generation"]),
              let revision = AutoFillV3JSON.positive(raw["revision"]) else { throw AutoFillV3Error.invalid }
        self.init(generation: generation, revision: revision)
    }
    var object: [String: Any] { ["generation": generation, "revision": revision] }
}

// Owned only by the app bridge. Provider reads never receive this capability.
final class AutoFillV3Writer {
    private let lock = NSRecursiveLock()
    private var epoch = 0
    private var generation: Int?
    private var key: Data?
    private var keyID: String?

    func begin(generation: Int) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        guard epoch < Int.max, generation > 0 else { throw AutoFillV3Error.invalid }
        wipe(); epoch += 1; self.generation = generation
        return epoch
    }
    func end(epoch: Int) {
        lock.lock(); defer { lock.unlock() }
        guard self.epoch == epoch else { return }
        wipe(); generation = nil
    }
    func invalidate(generation expectedGeneration: Int? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let expectedGeneration, generation != expectedGeneration { return }
        wipe(); generation = nil
    }
    func withCurrent<T>(epoch: Int, generation: Int, _ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard self.epoch == epoch, self.generation == generation else { throw AutoFillV3Error.writerInvalidated }
        return try operation()
    }
    func openingMaterial(epoch: Int, generation: Int) throws -> (key: Data, keyID: String) {
        try withCurrent(epoch: epoch, generation: generation) {
            guard let key, let keyID else { throw AutoFillV3Error.recoveryRequired }
            return (key, keyID)
        }
    }
    func install(key: Data, keyID: String, epoch: Int, generation: Int) throws {
        try withCurrent(epoch: epoch, generation: generation) { wipe(); self.key = key; self.keyID = keyID }
    }
    private func wipe() { let count = key?.count ?? 0; key?.resetBytes(in: 0..<count); key = nil; keyID = nil }
    deinit { wipe() }
}

enum AutoFillV3JSON {
    static func encode(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AutoFillV3Error.invalid }
        return value
    }
    static func positive(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue > 0, number.doubleValue < Double(Int.max) else { return nil }
        return number.intValue
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func coordinate(_ raw: [String: Any]) throws -> String {
        guard Set(raw.keys) == ["vaultId", "entryId"], let vault = raw["vaultId"] as? String,
              let entry = raw["entryId"] as? String, !vault.isEmpty, !entry.isEmpty,
              !vault.contains(":"), !entry.contains(":") else { throw AutoFillV3Error.invalid }
        return vault + ":" + entry
    }
    static func instant(_ raw: Any?) throws -> Date {
        guard let text = raw as? String else { throw AutoFillV3Error.invalid }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let value = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) else { throw AutoFillV3Error.invalid }
        return value
    }
}

struct AutoFillV3Pointer {
    let base: AutoFillV3Base
    let keyID: String
    let catalogID: String
    let digest: String
    var cacheID: String { "v3~\(base.revision)~\(keyID)~\(catalogID)~\(digest)" }
    init(base: AutoFillV3Base, keyID: String, catalogID: String, digest: String) {
        self.base = base; self.keyID = keyID; self.catalogID = catalogID; self.digest = digest
    }
    init(generation: Int, cacheID: String) throws {
        let parts = cacheID.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5, parts[0] == "v3", let revision = Int(parts[1]), revision > 0,
              String(revision) == parts[1], UUID(uuidString: parts[2]) != nil, UUID(uuidString: parts[3]) != nil,
              parts[4].count == 64, parts[4].allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw AutoFillV3Error.invalid }
        self.init(base: .init(generation: generation, revision: revision), keyID: parts[2], catalogID: parts[3], digest: parts[4])
    }
}

struct AutoFillV3Entry {
    let bodyID: String
    let digest: String
    let originalManifest: [String: Any]
    let identity: [String: Any]
    let notAfter: Date
    var object: [String: Any] {
        ["bodyID": bodyID, "digest": digest, "originalManifest": originalManifest,
         "identity": identity, "notAfter": notAfter.timeIntervalSince1970]
    }
}

struct AutoFillV3Catalog {
    let generation: Int
    let keyID: String
    var manifest: [String: Any]
    var entries: [String: AutoFillV3Entry]
    var denies: [String: [String]]
    var object: [String: Any] {
        ["version": 3, "generation": generation, "keyID": keyID, "manifest": manifest,
         "entries": entries.mapValues(\.object), "denies": denies]
    }
    var identities: [[String: Any]] {
        let denied = Set(denies.values.flatMap { $0 })
        return entries.keys.sorted().filter { !denied.contains($0) }.compactMap { entries[$0]?.identity }
    }
}

// Persistent files contain only authenticated ciphertext. The protected native
// fence selects an immutable catalog by digest; caller owns process-lock/CAS.
final class AutoFillV3Engine {
    static let maximumBytes = 16 * 1024 * 1024
    let directory: URL
    private(set) var recordEncryptions = 0
    private(set) var recordDecryptions = 0
    var fault: ((String) throws -> Void)?
    init(directory: URL) { self.directory = directory }

    func full(payload: [String: Any], generation: Int, keyID: String, key: Data, now: Date) throws -> AutoFillV3Catalog {
        let checked = try AutoFillPayloadValidator.validate(payload, now: now, incremental: true)
        let manifest = checked.canonicalObject["manifest"] as! [String: Any]
        let records = checked.canonicalObject["records"] as! [[String: Any]]
        var entries: [String: AutoFillV3Entry] = [:]
        for record in records {
            let coordinate = try coordinate(record)
            entries[coordinate] = try encrypt(record, manifest: singleManifest(manifest, coordinate: coordinate), generation: generation, keyID: keyID, key: key)
        }
        return AutoFillV3Catalog(generation: generation, keyID: keyID, manifest: manifest, entries: entries, denies: [:])
    }

    func delta(catalog: AutoFillV3Catalog, manifest: [String: Any], upserts: [[String: Any]], removals: [[String: Any]], releasingDenies: [String], key: Data, now: Date) throws -> AutoFillV3Catalog {
        try validate(catalog, now: now)
        let validated = try AutoFillPayloadValidator.validateManifest(manifest, now: now, allowEmpty: true).canonicalObject
        guard try profile(catalog.manifest) == profile(validated) else { throw AutoFillV3Error.recoveryRequired }
        let removed = try Set(removals.map(AutoFillV3JSON.coordinate))
        guard removed.count == removals.count, Set(releasingDenies).count == releasingDenies.count,
              releasingDenies.allSatisfy({ catalog.denies[$0] != nil }) else { throw AutoFillV3Error.invalid }
        var result = catalog; result.manifest = validated
        var changed = Set<String>()
        for record in upserts {
            let coordinate = try coordinate(record)
            guard changed.insert(coordinate).inserted, !removed.contains(coordinate) else { throw AutoFillV3Error.invalid }
            let single = try singleManifest(validated, coordinate: coordinate)
            let checked = try AutoFillPayloadValidator.validate(["version": 3, "manifest": single, "records": [record]], now: now, incremental: true)
            let canonical = (checked.canonicalObject["records"] as! [[String: Any]])[0]
            result.entries[coordinate] = try encrypt(canonical, manifest: single, generation: catalog.generation, keyID: catalog.keyID, key: key)
        }
        for coordinate in removed { result.entries.removeValue(forKey: coordinate) }
        guard Set(result.entries.keys) == coordinates(validated) else { throw AutoFillV3Error.invalid }
        for (coordinate, old) in result.entries where !changed.contains(coordinate) {
            let current = try singleManifest(validated, coordinate: coordinate)
            guard try binding(current) == binding(old.originalManifest) else { throw AutoFillV3Error.recoveryRequired }
            let expiry = min(old.notAfter, try notAfter(current))
            guard expiry > now else { throw AutoFillV3Error.recoveryRequired }
            _ = try load(id: old.bodyID, generation: catalog.generation, digest: old.digest)
            result.entries[coordinate] = AutoFillV3Entry(bodyID: old.bodyID, digest: old.digest, originalManifest: old.originalManifest, identity: old.identity, notAfter: expiry)
        }
        for token in releasingDenies {
            // Retained records have now passed complete current authority,
            // immutable binding, ciphertext integrity and minimum-lease checks.
            guard catalog.denies[token]!.allSatisfy({ removed.contains($0) || result.entries[$0] != nil }) else { throw AutoFillV3Error.invalid }
            result.denies.removeValue(forKey: token)
        }
        return result
    }

    func preparePublication(previous: AutoFillV3Catalog, next: AutoFillV3Catalog,
                            pointer: AutoFillV3Pointer, key: Data, allowUnchanged: Bool,
                            now: Date) throws -> AutoFillV3Publication {
        try validate(previous, now: now)
        try validate(next, now: now)
        if allowUnchanged, try canPreservePublication(previous: previous, next: next, now: now) {
            for entry in previous.entries.values {
                _ = try load(id: entry.bodyID, generation: previous.generation, digest: entry.digest)
            }
            return AutoFillV3Publication(pointer: pointer, identities: previous.identities,
                                        previousIdentities: previous.identities, updatesIdentities: false)
        }
        let nextPointer = try persist(next, revision: pointer.base.revision + 1, key: key)
        return AutoFillV3Publication(pointer: nextPointer, identities: next.identities,
                                    previousIdentities: previous.identities)
    }

    func canPreservePublication(previous: AutoFillV3Catalog, next: AutoFillV3Catalog, now: Date) throws -> Bool {
        try validate(previous, now: now)
        try validate(next, now: now)
        guard previous.denies.isEmpty, next.denies.isEmpty,
              previous.generation == next.generation, previous.keyID == next.keyID,
              try binding(previous.manifest) == binding(next.manifest),
              try AutoFillV3JSON.encode(previous.entries.mapValues(\.object)) == AutoFillV3JSON.encode(next.entries.mapValues(\.object)),
              let oldVaults = previous.manifest["vaults"] as? [[String: Any]],
              let newVaults = next.manifest["vaults"] as? [[String: Any]] else { return false }
        for old in oldVaults {
            guard let current = newVaults.first(where: { $0["vaultId"] as? String == old["vaultId"] as? String }) else { return false }
            let oldStart = try AutoFillV3JSON.instant(old["issuedAt"])
            let oldEnd = try AutoFillV3JSON.instant(old["notAfter"])
            let newStart = try AutoFillV3JSON.instant(current["issuedAt"])
            let newEnd = try AutoFillV3JSON.instant(current["notAfter"])
            guard newEnd >= oldEnd, max(oldStart, newStart) < min(oldEnd, newEnd) else { return false }
        }
        for (coordinate, entry) in previous.entries {
            let current = try singleManifest(next.manifest, coordinate: coordinate)
            let originalVault = (entry.originalManifest["vaults"] as! [[String: Any]])[0]
            let currentVault = (current["vaults"] as! [[String: Any]])[0]
            let originalStart = try AutoFillV3JSON.instant(originalVault["issuedAt"])
            let currentStart = try AutoFillV3JSON.instant(currentVault["issuedAt"])
            guard max(originalStart, currentStart) < min(entry.notAfter, try notAfter(current)) else { return false }
        }
        return true
    }

    func deny(catalog: AutoFillV3Catalog, entries: [[String: Any]], now: Date) throws -> (catalog: AutoFillV3Catalog, token: String) {
        try validate(catalog, now: now)
        let coordinates = try entries.map(AutoFillV3JSON.coordinate)
        guard Set(coordinates).count == coordinates.count else { throw AutoFillV3Error.invalid }
        var updated = catalog
        let token = UUID().uuidString.lowercased()
        updated.denies[token] = coordinates
        return (updated, token)
    }

    func persist(_ catalog: AutoFillV3Catalog, revision: Int, key: Data) throws -> AutoFillV3Pointer {
        let catalogID = UUID().uuidString.lowercased()
        var plaintext = try AutoFillV3JSON.encode(catalog.object)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        var total = plaintext.count
        for entry in catalog.entries.values {
            let value = try load(id: entry.bodyID, generation: catalog.generation, digest: entry.digest)
            total += value.count
            guard total <= Self.maximumBytes else { throw AutoFillV3Error.invalid }
        }
        let sealed = try seal(plaintext, key: key, aad: Data("catalog-v3:\(catalog.generation):\(revision):\(catalog.keyID):\(catalogID)".utf8))
        try write(sealed, id: catalogID, generation: catalog.generation)
        try fault?("catalogDurable")
        return AutoFillV3Pointer(base: .init(generation: catalog.generation, revision: revision), keyID: catalog.keyID, catalogID: catalogID, digest: AutoFillV3JSON.hash(sealed))
    }

    func open(_ pointer: AutoFillV3Pointer, key: Data, now: Date, allowExpired: Bool = false) throws -> AutoFillV3Catalog {
        do {
            let sealed = try load(id: pointer.catalogID, generation: pointer.base.generation, digest: pointer.digest)
            var plaintext = try open(sealed, key: key, aad: Data("catalog-v3:\(pointer.base.generation):\(pointer.base.revision):\(pointer.keyID):\(pointer.catalogID)".utf8))
            defer { plaintext.resetBytes(in: 0..<plaintext.count) }
            let raw = try AutoFillV3JSON.object(plaintext)
            guard Set(raw.keys) == ["version", "generation", "keyID", "manifest", "entries", "denies"],
                  raw["version"] as? Int == 3, raw["generation"] as? Int == pointer.base.generation,
                  raw["keyID"] as? String == pointer.keyID, let manifest = raw["manifest"] as? [String: Any],
                  let values = raw["entries"] as? [String: [String: Any]], let denies = raw["denies"] as? [String: [String]],
                  values.count <= AutoFillPayloadValidator.maximumRecords else { throw AutoFillV3Error.invalid }
            var entries: [String: AutoFillV3Entry] = [:]
            for (coordinate, value) in values {
                guard Set(value.keys) == ["bodyID", "digest", "originalManifest", "identity", "notAfter"],
                      let bodyID = value["bodyID"] as? String, let digest = value["digest"] as? String,
                      let original = value["originalManifest"] as? [String: Any], let identity = value["identity"] as? [String: Any],
                      let expiry = value["notAfter"] as? Double, expiry.isFinite else { throw AutoFillV3Error.invalid }
                entries[coordinate] = .init(bodyID: bodyID, digest: digest, originalManifest: original, identity: identity, notAfter: Date(timeIntervalSince1970: expiry))
            }
            let catalog = AutoFillV3Catalog(generation: pointer.base.generation, keyID: pointer.keyID, manifest: manifest, entries: entries, denies: denies)
            try validate(catalog, now: now, allowExpired: allowExpired)
            return catalog
        } catch { throw AutoFillV3Error.recoveryRequired }
    }

    func records(_ catalog: AutoFillV3Catalog, key: Data, now: Date) throws -> [(AutoFillCredentialRecord, Date)] {
        try validate(catalog, now: now)
        let denied = Set(catalog.denies.values.flatMap { $0 })
        return try catalog.entries.keys.sorted().filter { !denied.contains($0) }.map { coordinate in
            let entry = catalog.entries[coordinate]!
            let ciphertext = try load(id: entry.bodyID, generation: catalog.generation, digest: entry.digest)
            var plaintext = try open(ciphertext, key: key, aad: recordAAD(generation: catalog.generation, keyID: catalog.keyID, manifest: entry.originalManifest))
            defer { plaintext.resetBytes(in: 0..<plaintext.count) }
            recordDecryptions += 1
            let raw = try AutoFillV3JSON.object(plaintext)
            var identity = raw; identity.removeValue(forKey: "password")
            guard try AutoFillV3JSON.encode(identity) == AutoFillV3JSON.encode(entry.identity) else { throw AutoFillV3Error.invalid }
            let checked = try AutoFillPayloadValidator.validate(["version": 3, "manifest": entry.originalManifest, "records": [raw]], now: now, incremental: true)
            return (checked.records[0], entry.notAfter)
        }
    }

    func validate(_ catalog: AutoFillV3Catalog, now: Date, allowExpired: Bool = false) throws {
        _ = try AutoFillPayloadValidator.validateManifest(catalog.manifest, now: now, allowEmpty: true, allowExpired: allowExpired)
        guard Set(catalog.entries.keys) == coordinates(catalog.manifest), catalog.entries.count <= AutoFillPayloadValidator.maximumRecords else { throw AutoFillV3Error.invalid }
        for (coordinate, entry) in catalog.entries {
            let current = try singleManifest(catalog.manifest, coordinate: coordinate)
            guard try binding(current) == binding(entry.originalManifest),
                  entry.notAfter <= (try notAfter(current)), entry.notAfter <= (try notAfter(entry.originalManifest)), (allowExpired || entry.notAfter > now),
                  try self.coordinate(entry.identity) == coordinate else { throw AutoFillV3Error.recoveryRequired }
        }
    }
    func collectGarbage(retaining catalog: AutoFillV3Catalog, pointer: AutoFillV3Pointer) throws {
        let retained = Set(catalog.entries.values.map(\.bodyID)).union([pointer.catalogID])
        let prefix = "palladin_autofill_v3_\(catalog.generation)_"
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard file.lastPathComponent.hasPrefix(prefix) else { continue }
            let suffix = String(file.lastPathComponent.dropFirst(prefix.count))
            if UUID(uuidString: suffix) != nil && !retained.contains(suffix) { try FileManager.default.removeItem(at: file) }
        }
    }

    private func encrypt(_ raw: [String: Any], manifest: [String: Any], generation: Int, keyID: String, key: Data) throws -> AutoFillV3Entry {
        var plaintext = try AutoFillV3JSON.encode(raw)
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        let sealed = try seal(plaintext, key: key, aad: recordAAD(generation: generation, keyID: keyID, manifest: manifest))
        let id = UUID().uuidString.lowercased(); try write(sealed, id: id, generation: generation)
        recordEncryptions += 1
        var identity = raw; identity.removeValue(forKey: "password")
        return .init(bodyID: id, digest: AutoFillV3JSON.hash(sealed), originalManifest: manifest, identity: identity, notAfter: try notAfter(manifest))
    }
    private func coordinate(_ record: [String: Any]) throws -> String {
        try AutoFillV3JSON.coordinate(["vaultId": record["vaultId"] as Any, "entryId": record["id"] as Any])
    }
    private func coordinates(_ manifest: [String: Any]) -> Set<String> {
        Set((manifest["vaults"] as? [[String: Any]] ?? []).flatMap { vault in
            (vault["entries"] as? [[String: Any]] ?? []).compactMap { entry in
                guard let vaultID = vault["vaultId"] as? String, let id = entry["entryId"] as? String else { return nil }
                return vaultID + ":" + id
            }
        })
    }
    private func singleManifest(_ manifest: [String: Any], coordinate: String) throws -> [String: Any] {
        let pair = coordinate.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard pair.count == 2, let vaults = manifest["vaults"] as? [[String: Any]],
              var vault = vaults.first(where: { $0["vaultId"] as? String == pair[0] }),
              let entries = vault["entries"] as? [[String: Any]], let entry = entries.first(where: { $0["entryId"] as? String == pair[1] }) else { throw AutoFillV3Error.invalid }
        vault["entries"] = [entry]; var result = manifest; result["vaults"] = [vault]; return result
    }
    private func profile(_ manifest: [String: Any]) throws -> Data { var value = manifest; value.removeValue(forKey: "vaults"); return try AutoFillV3JSON.encode(value) }
    private func binding(_ manifest: [String: Any]) throws -> Data {
        var value = manifest
        value["vaults"] = (manifest["vaults"] as? [[String: Any]] ?? []).map { vault -> [String: Any] in
            var scope = vault; scope.removeValue(forKey: "issuedAt"); scope.removeValue(forKey: "notAfter"); return scope
        }
        return try AutoFillV3JSON.encode(value)
    }
    private func notAfter(_ manifest: [String: Any]) throws -> Date {
        guard let vault = (manifest["vaults"] as? [[String: Any]])?.first else { throw AutoFillV3Error.invalid }
        return try AutoFillV3JSON.instant(vault["notAfter"])
    }
    private func recordAAD(generation: Int, keyID: String, manifest: [String: Any]) throws -> Data {
        try AutoFillV3JSON.encode(["purpose": "record-v3", "generation": generation, "keyID": keyID, "manifest": manifest])
    }
    private func seal(_ plaintext: Data, key: Data, aad: Data) throws -> Data {
        guard key.count == 32, plaintext.count <= Self.maximumBytes else { throw AutoFillV3Error.invalid }
        guard let value = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), authenticating: aad).combined else { throw AutoFillV3Error.invalid }
        return value
    }
    private func open(_ sealed: Data, key: Data, aad: Data) throws -> Data {
        guard key.count == 32 else { throw AutoFillV3Error.invalid }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: SymmetricKey(data: key), authenticating: aad)
    }
    private func url(id: String, generation: Int) throws -> URL {
        guard UUID(uuidString: id) != nil, generation > 0 else { throw AutoFillV3Error.invalid }
        return directory.appendingPathComponent("palladin_autofill_v3_\(generation)_\(id)")
    }
    func load(id: String, generation: Int, digest: String) throws -> Data {
        do {
            let url = try url(id: id, generation: generation)
            guard let size = (try FileManager.default.attributesOfItem(atPath: url.path))[.size] as? NSNumber,
                  size.intValue > 0, size.intValue <= Self.maximumBytes else { throw AutoFillV3Error.recoveryRequired }
            let data = try Data(contentsOf: url)
            guard AutoFillV3JSON.hash(data) == digest else { throw AutoFillV3Error.recoveryRequired }
            return data
        } catch { throw AutoFillV3Error.recoveryRequired }
    }

    private func write(_ data: Data, id: String, generation: Int) throws {
        let url = try url(id: id, generation: generation)
        guard !FileManager.default.fileExists(atPath: url.path), data.count <= Self.maximumBytes else { throw AutoFillV3Error.invalid }
        try data.write(to: url, options: [.withoutOverwriting, .completeFileProtection])
        let file = Darwin.open(url.path, O_RDONLY); guard file >= 0 else { throw AutoFillV3Error.invalid }
        defer { close(file) }; guard fsync(file) == 0 else { throw AutoFillV3Error.invalid }
        let directoryFD = Darwin.open(directory.path, O_RDONLY); guard directoryFD >= 0 else { throw AutoFillV3Error.invalid }
        defer { close(directoryFD) }; guard fsync(directoryFD) == 0 else { throw AutoFillV3Error.invalid }
    }
}

struct AutoFillV3Publication {
    let pointer: AutoFillV3Pointer
    let identities: [[String: Any]]
    let previousIdentities: [[String: Any]]?
    var denyToken: String? = nil
    var updatesIdentities = true
    var response: [String: Any] {
        if let denyToken { return ["base": pointer.base.object, "denyToken": denyToken] }
        return pointer.base.object
    }
}
