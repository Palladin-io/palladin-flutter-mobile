import Foundation

struct SharedMemberCandidate {
    let id: String
    let label: String
    let domains: [String]
}

/// Native owns the OS destination and one operation's lifetime. Only the
/// callback of its own successful crypto opening may admit metadata/selection.
final class SharedMemberCredentialRequest {
    let id = UUID().uuidString
    let source: SharedMemberSourceFence
    let snapshot: SharedMemberSourceSnapshot
    let verifiedHosts: Set<String>
    private let started = ProcessInfo.processInfo.systemUptime
    private let lock = NSRecursiveLock()
    private var attempt: UUID?
    private var authenticated = false
    private var canceled = false
    private var selected: (id: String, host: String)?
    private(set) var candidates: [SharedMemberCandidate] = []

    init(source: SharedMemberSourceFence, snapshot: SharedMemberSourceSnapshot, verifiedHosts: Set<String>) throws {
        self.source = source; self.snapshot = snapshot; self.verifiedHosts = verifiedHosts
        try validate()
    }

    var arguments: [String: Any] {
        ["id": id, "remainingMs": max(0, Int((120 - (ProcessInfo.processInfo.systemUptime - started)) * 1000)),
         "mode": verifiedHosts.isEmpty ? "MANUAL_NATIVE" : "WEB",
         "verifiedHosts": verifiedHosts.sorted(), "usernameOnly": false]
    }

    func validate() throws {
        lock.lock(); defer { lock.unlock() }
        guard !canceled, ProcessInfo.processInfo.systemUptime - started < 120 else { throw SharedMemberSourceError.stale }
        try source.withCurrentSource(snapshot, requireActive: true) {}
    }

    func beginAuthentication() throws -> UUID {
        lock.lock(); defer { lock.unlock() }
        try validate()
        guard attempt == nil, !authenticated else { throw SharedMemberSourceError.stale }
        let token = UUID(); attempt = token
        return token
    }

    func authenticationSucceeded(_ token: UUID, rows: [[String: Any]]) throws {
        lock.lock(); defer { lock.unlock() }
        try validate()
        guard attempt == token, !authenticated else { throw SharedMemberSourceError.stale }
        var seen = Set<String>()
        let parsed = try rows.map { row -> SharedMemberCandidate in
            guard let selection = row["selectionId"] as? String, selection.hasPrefix(id + "/"),
                  seen.insert(selection).inserted, let label = row["label"] as? String,
                  let domains = row["domains"] as? [String], !domains.isEmpty,
                  verifiedHosts.isEmpty || !verifiedHosts.isDisjoint(with: domains) else { throw SharedMemberSourceError.invalid }
            return SharedMemberCandidate(id: selection, label: label, domains: domains)
        }
        candidates = parsed; authenticated = true; attempt = nil
    }

    func prepareSelection(id: String, host: String, manualConfirmed: Bool) throws -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        try validate()
        guard authenticated, selected == nil,
              let candidate = candidates.first(where: { $0.id == id }), candidate.domains.contains(host),
              verifiedHosts.isEmpty ? manualConfirmed : verifiedHosts.contains(host) else { throw SharedMemberSourceError.stale }
        selected = (id, host)
        return ["selectionId": id, "selectedHost": host, "manualConfirmed": manualConfirmed]
    }

    func complete(_ response: [String: Any], handoff: (String, String) throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        try validate()
        guard authenticated, let selected,
              response["requestId"] as? String == id,
              response["selectionId"] as? String == selected.id,
              response["selectedHost"] as? String == selected.host,
              let username = response["username"] as? String, let password = response["password"] as? String,
              let context = response["accessContext"] as? [String: Any],
              context["principalId"] as? String == snapshot.claims.principalId,
              context["organizationId"] as? String == snapshot.claims.organizationId,
              context["organizationMembershipGeneration"] as? String == snapshot.claims.organizationMembershipGeneration,
              context["offlinePolicy"] as? String == snapshot.claims.offlinePolicy,
              context["offlinePolicyVersion"] as? Int == snapshot.claims.offlinePolicyVersion,
              snapshot.claims.offlinePolicy != "disabled",
              let expiry = context["notAfter"] as? String, let notAfter = Self.instant(expiry), notAfter > Date() else {
            throw SharedMemberSourceError.stale
        }
        // Do not dispatch away from this lock: admission and invalidation share
        // the source flock. Dart has already checked the full crypto/lease contract.
        try source.withCurrentSource(snapshot, requireActive: true) {
            canceled = true
            try handoff(username, password)
        }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        canceled = true; authenticated = false; attempt = nil; selected = nil; candidates.removeAll()
    }

    private static func instant(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
