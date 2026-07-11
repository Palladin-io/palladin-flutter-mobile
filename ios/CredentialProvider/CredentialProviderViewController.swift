import AuthenticationServices
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabel
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        showLockedMessage()
    }

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userInteractionRequired.rawValue
        ))
    }

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        showLockedMessage()
    }

    override func prepareInterfaceForExtensionConfiguration() {
        showLockedMessage()
    }

    @available(iOS 17.0, *)
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userInteractionRequired.rawValue
        ))
    }

    @available(iOS 17.0, *)
    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        showLockedMessage()
    }

    private func showLockedMessage() {
        statusLabel.text = NSLocalizedString(
            "credential_provider_locked",
            comment: "Message shown when the AutoFill credential provider cannot return credentials because Palladin is locked."
        )
    }
}
