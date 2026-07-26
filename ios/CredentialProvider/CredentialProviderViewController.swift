import AuthenticationServices
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController {
    private let statusLabel = UILabel()
    private let credentialsStack = UIStackView()
    private var visibleRecords: [AutoFillCredentialRecord] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabel

        credentialsStack.translatesAutoresizingMaskIntoConstraints = false
        credentialsStack.axis = .vertical
        credentialsStack.spacing = 12

        let container = UIStackView(arrangedSubviews: [statusLabel, credentialsStack])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .vertical
        container.spacing = 20
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        unlockRecords { [weak self] records in
            self?.show(records.filter { $0.matches(serviceIdentifiers: serviceIdentifiers) })
        }
    }

    override func provideCredentialWithoutUserInteraction(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        requireUserInteraction()
    }

    override func prepareInterfaceToProvideCredential(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        unlockAndComplete(
            recordIdentifier: credentialIdentity.recordIdentifier,
            serviceIdentifiers: [credentialIdentity.serviceIdentifier]
        )
    }

    override func prepareInterfaceForExtensionConfiguration() {
        showLockedMessage()
    }

    @available(iOS 17.0, *)
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        requireUserInteraction()
    }

    @available(iOS 17.0, *)
    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        let identity = credentialRequest.credentialIdentity as? ASPasswordCredentialIdentity
        unlockAndComplete(
            recordIdentifier: identity?.recordIdentifier,
            serviceIdentifiers: identity.map { [$0.serviceIdentifier] } ?? []
        )
    }

    private func unlockAndComplete(
        recordIdentifier: String?,
        serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) {
        guard let recordIdentifier, !serviceIdentifiers.isEmpty else {
            requireUserInteraction()
            return
        }
        unlockRecords { [weak self] records in
            guard let self,
                  let record = records.first(where: {
                      $0.id == recordIdentifier &&
                      $0.matches(serviceIdentifiers: serviceIdentifiers)
                  }) else {
                self?.showUnavailableMessage()
                return
            }
            self.complete(record)
        }
    }

    private func unlockRecords(completion: @escaping ([AutoFillCredentialRecord]) -> Void) {
        statusLabel.text = NSLocalizedString(
            "credential_provider_unlocking",
            comment: "Shown while the provider waits for biometric authentication."
        )
        credentialsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let store = try AutoFillCacheStore()
                let records = try store.read(
                    authenticationPrompt: NSLocalizedString(
                        "credential_provider_biometric_prompt",
                        comment: "Biometric prompt for releasing an AutoFill credential."
                    )
                )
                DispatchQueue.main.async { completion(records) }
            } catch {
                if let store = try? AutoFillCacheStore() {
                    try? store.clear()
                    AutoFillCacheStore.clearIdentities { _ in }
                }
                DispatchQueue.main.async { [weak self] in self?.showUnavailableMessage() }
            }
        }
    }

    private func show(_ records: [AutoFillCredentialRecord]) {
        visibleRecords = records
        credentialsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !records.isEmpty else {
            statusLabel.text = NSLocalizedString(
                "credential_provider_no_matches",
                comment: "Shown when no credential matches the requested service."
            )
            return
        }
        statusLabel.text = nil
        for (index, record) in records.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle("\(record.label)\n\(record.username)", for: .normal)
            button.setImage(UIImage(systemName: "key.fill"), for: .normal)
            button.titleLabel?.numberOfLines = 2
            button.contentHorizontalAlignment = .leading
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
            button.tag = index
            button.addTarget(self, action: #selector(selectCredential(_:)), for: .touchUpInside)
            credentialsStack.addArrangedSubview(button)
        }
    }

    @objc private func selectCredential(_ sender: UIButton) {
        guard visibleRecords.indices.contains(sender.tag) else { return }
        complete(visibleRecords[sender.tag])
    }

    private func complete(_ record: AutoFillCredentialRecord) {
        let credential = ASPasswordCredential(user: record.username, password: record.password)
        extensionContext.completeRequest(withSelectedCredential: credential, completionHandler: nil)
        visibleRecords.removeAll(keepingCapacity: false)
    }

    private func requireUserInteraction() {
        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userInteractionRequired.rawValue
        ))
    }

    private func showLockedMessage() {
        statusLabel.text = NSLocalizedString(
            "credential_provider_locked",
            comment: "Message shown when Palladin must be unlocked."
        )
    }

    private func showUnavailableMessage() {
        visibleRecords.removeAll(keepingCapacity: false)
        statusLabel.text = NSLocalizedString(
            "credential_provider_unavailable",
            comment: "Shown when biometric authentication or cache access fails."
        )
    }
}
