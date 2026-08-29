import AuthenticationServices
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController {
    private let statusLabel = UILabel()
    private let credentialsStack = UIStackView()
    private var visibleCredentials: [AutoFillCredentialLease] = []
    private var visibleServiceIdentifiers: [ASCredentialServiceIdentifier] = []

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
        unlockRecords { [weak self] result in
            self?.show(
                result.credentials.filter {
                    $0.record.matches(serviceIdentifiers: serviceIdentifiers)
                },
                serviceIdentifiers: serviceIdentifiers
            )
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
        unlockRecords { [weak self] result in
            guard let self,
                  let credential = result.credentials.first(where: {
                      $0.record.id == recordIdentifier &&
                      $0.record.matches(serviceIdentifiers: serviceIdentifiers)
                  }) else {
                self?.showUnavailableMessage()
                return
            }
            self.complete(credential, serviceIdentifiers: serviceIdentifiers)
        }
    }

    private func unlockRecords(completion: @escaping (AutoFillCacheReadResult) -> Void) {
        statusLabel.text = NSLocalizedString(
            "credential_provider_unlocking",
            comment: "Shown while the provider waits for biometric authentication."
        )
        credentialsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        DispatchQueue.global(qos: .userInitiated).async {
            var operation: AutoFillUnwrapOperation?
            do {
                let store = try AutoFillCacheStore()
                let preparedOperation = try store.createUnwrapOperation()
                operation = preparedOperation
                let result = try store.read(
                    operation: preparedOperation,
                    authenticationPrompt: NSLocalizedString(
                        "credential_provider_biometric_prompt",
                        comment: "Biometric prompt for releasing an AutoFill credential."
                    )
                )
                DispatchQueue.main.async { completion(result) }
            } catch {
                if let store = try? AutoFillCacheStore(), let operation {
                    try? store.quarantine(
                        generation: operation.generation,
                        cacheId: operation.cacheId
                    )
                    AutoFillCacheStore.clearIdentities(
                        store: store,
                        onlyIf: { !store.hasActiveCache() }
                    ) { _ in }
                }
                DispatchQueue.main.async { [weak self] in self?.showUnavailableMessage() }
            }
        }
    }

    private func show(
        _ credentials: [AutoFillCredentialLease],
        serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) {
        visibleCredentials = credentials
        visibleServiceIdentifiers = serviceIdentifiers
        credentialsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !credentials.isEmpty else {
            statusLabel.text = NSLocalizedString(
                "credential_provider_no_matches",
                comment: "Shown when no credential matches the requested service."
            )
            return
        }
        statusLabel.text = nil
        for (index, credential) in credentials.enumerated() {
            let record = credential.record
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
        guard visibleCredentials.indices.contains(sender.tag) else { return }
        complete(
            visibleCredentials[sender.tag],
            serviceIdentifiers: visibleServiceIdentifiers
        )
    }

    private func complete(
        _ credential: AutoFillCredentialLease,
        serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) {
        do {
            let store = try AutoFillCacheStore()
            try store.withRevalidatedCredential(
                credential,
                serviceIdentifiers: serviceIdentifiers
            ) {
                let passwordCredential = ASPasswordCredential(
                    user: credential.record.username,
                    password: credential.record.password
                )
                extensionContext.completeRequest(
                    withSelectedCredential: passwordCredential,
                    completionHandler: nil
                )
            }
            visibleCredentials.removeAll(keepingCapacity: false)
            visibleServiceIdentifiers.removeAll(keepingCapacity: false)
        } catch {
            if let store = try? AutoFillCacheStore() {
                try? store.quarantine(
                    generation: credential.generation,
                    cacheId: credential.cacheId
                )
            }
            showUnavailableMessage()
        }
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
        visibleCredentials.removeAll(keepingCapacity: false)
        visibleServiceIdentifiers.removeAll(keepingCapacity: false)
        statusLabel.text = NSLocalizedString(
            "credential_provider_unavailable",
            comment: "Shown when biometric authentication or cache access fails."
        )
    }
}
