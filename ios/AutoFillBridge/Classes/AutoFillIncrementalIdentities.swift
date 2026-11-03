import AuthenticationServices
import Foundation

struct AutoFillV3IdentityChange {
    let all: [ASPasswordCredentialIdentity]
    let removed: [ASPasswordCredentialIdentity]
    let saved: [ASPasswordCredentialIdentity]

    init(current: [[String: Any]], previous: [[String: Any]]?) throws {
        func identities(_ rows: [[String: Any]]) throws -> [String: ASPasswordCredentialIdentity] {
            var result: [String: ASPasswordCredentialIdentity] = [:]
            for row in rows {
                guard let id = row["id"] as? String, let username = row["username"] as? String,
                      let domains = row["domains"] as? [String] else { throw AutoFillV3Error.invalid }
                for domain in domains {
                    let key = try AutoFillV3JSON.encode([id, username, domain]).base64EncodedString()
                    result[key] = ASPasswordCredentialIdentity(serviceIdentifier: .init(identifier: domain, type: .domain), user: username, recordIdentifier: id)
                }
            }
            return result
        }
        let currentMap = try identities(current)
        let previousMap = try identities(previous ?? [])
        all = currentMap.keys.sorted().compactMap { currentMap[$0] }
        removed = previousMap.keys.sorted().filter { currentMap[$0] == nil }.compactMap { previousMap[$0] }
        saved = currentMap.keys.sorted().filter { previousMap[$0] == nil }.compactMap { currentMap[$0] }
    }
}

// Callers serialize OS operations until their callbacks complete. Revision
// validation happens at every asynchronous boundary, never only at dispatch.
enum AutoFillV3IdentityUpdater {
    typealias Mutation = ([ASPasswordCredentialIdentity], @escaping (Bool, Error?) -> Void) -> Void
    static func update(
        change: AutoFillV3IdentityChange,
        hasPrevious: Bool,
        isCurrent: @escaping () -> Bool,
        state: (@escaping (Bool) -> Void) -> Void,
        remove: @escaping Mutation,
        save: @escaping Mutation,
        replace: @escaping Mutation,
        completion: @escaping (Error?) -> Void
    ) {
        func finish(_ success: Bool, _ error: Error?) {
            guard isCurrent() else { completion(AutoFillV3Error.staleBase); return }
            completion(success ? error : (error ?? AutoFillCacheError.cacheUnavailable))
        }
        guard isCurrent() else { completion(AutoFillV3Error.staleBase); return }
        state { incremental in
            guard isCurrent() else { completion(AutoFillV3Error.staleBase); return }
            guard incremental && hasPrevious else { replace(change.all, finish); return }
            func saveCurrent() {
                guard isCurrent() else { completion(AutoFillV3Error.staleBase); return }
                if change.saved.isEmpty { finish(true, nil) } else { save(change.saved, finish) }
            }
            if change.removed.isEmpty { saveCurrent() }
            else {
                remove(change.removed) { success, error in
                    guard success && error == nil else { finish(success, error); return }
                    saveCurrent()
                }
            }
        }
    }
}

// A failed or skipped OS update invalidates the assumption behind a delta.
// This is only an optimization acknowledgement, never credential authority.
final class AutoFillV3IdentityAcknowledgement {
    private let lock = NSLock()
    private var base: AutoFillV3Base?
    func canApplyDelta(to next: AutoFillV3Base) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return base?.generation == next.generation && base?.revision == next.revision - 1
    }
    func set(_ value: AutoFillV3Base?) {
        lock.lock(); defer { lock.unlock() }; base = value
    }
}
