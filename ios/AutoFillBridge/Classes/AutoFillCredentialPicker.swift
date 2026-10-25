import AuthenticationServices
import Foundation

struct AutoFillManualSelection {
    let credential: AutoFillCredentialLease
    fileprivate init(credential: AutoFillCredentialLease) { self.credential = credential }
}

/// Owns only credentials returned by a successful, authenticated cache read.
final class AutoFillCredentialPicker {
    let requiresManualConfirmation: Bool
    private var credentials: [AutoFillCredentialLease]
    private(set) var pendingConfirmation: AutoFillCredentialLease?

    init(credentials: [AutoFillCredentialLease], serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        requiresManualConfirmation = serviceIdentifiers.isEmpty
        self.credentials = serviceIdentifiers.isEmpty
            ? credentials
            : credentials.filter { $0.record.matches(serviceIdentifiers: serviceIdentifiers) }
    }

    func candidates(query: String) -> [AutoFillCredentialLease] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return credentials.filter {
            query.isEmpty || ([$0.record.label, $0.record.username] + $0.record.domains).contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func select(recordID: String) -> AutoFillCredentialLease? {
        pendingConfirmation = nil
        guard let credential = credentials.first(where: { $0.record.id == recordID }) else { return nil }
        if requiresManualConfirmation {
            pendingConfirmation = credential
            return nil
        }
        return credential
    }

    func confirmManualSelection() -> AutoFillManualSelection? {
        guard requiresManualConfirmation, let pendingConfirmation else { return nil }
        self.pendingConfirmation = nil
        return AutoFillManualSelection(credential: pendingConfirmation)
    }

    func cancelSelection() { pendingConfirmation = nil }

    func clear() {
        pendingConfirmation = nil
        credentials.removeAll(keepingCapacity: false)
    }
}
