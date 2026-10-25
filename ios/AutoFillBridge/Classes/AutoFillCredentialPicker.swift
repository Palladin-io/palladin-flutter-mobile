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
    private(set) var pendingConfirmationID: UUID?

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
        cancelSelection()
        guard let credential = credentials.first(where: { $0.record.id == recordID }) else { return nil }
        if requiresManualConfirmation {
            pendingConfirmation = credential
            pendingConfirmationID = UUID()
            return nil
        }
        return credential
    }

    func confirmManualSelection(confirmationID: UUID) -> AutoFillManualSelection? {
        guard requiresManualConfirmation, pendingConfirmationID == confirmationID,
              let pendingConfirmation else { return nil }
        cancelSelection()
        return AutoFillManualSelection(credential: pendingConfirmation)
    }

    func cancelSelection() {
        pendingConfirmation = nil
        pendingConfirmationID = nil
    }

    func clear() {
        cancelSelection()
        credentials.removeAll(keepingCapacity: false)
    }
}

/// Tracks request validity independently of temporary biometric focus changes.
final class AutoFillCredentialRequestLifecycle {
    private(set) var generation = 0
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter,
        hostBackgroundNotification: Notification.Name,
        onHostBackground: @escaping () -> Void
    ) {
        self.notificationCenter = notificationCenter
        observer = notificationCenter.addObserver(
            forName: hostBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.invalidate()
            onHostBackground()
        }
    }

    deinit {
        if let observer { notificationCenter.removeObserver(observer) }
    }

    func invalidate() { generation += 1 }
}
