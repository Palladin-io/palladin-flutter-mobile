import AuthenticationServices
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController, UISearchBarDelegate {
    private let statusLabel = UILabel()
    private let credentialsStack = UIStackView()
    private let searchBar = UISearchBar()
    private var picker: AutoFillCredentialPicker?
    private var requestGeneration = 0
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

        searchBar.placeholder = NSLocalizedString("credential_provider_search", comment: "Credential search")
        searchBar.delegate = self
        searchBar.autocorrectionType = .no
        searchBar.spellCheckingType = .no
        searchBar.isHidden = true

        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.addSubview(credentialsStack)
        NSLayoutConstraint.activate([
            credentialsStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            credentialsStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            credentialsStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            credentialsStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            credentialsStack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        let cancel = UIButton(type: .system)
        cancel.setTitle(NSLocalizedString("credential_provider_cancel", comment: "Cancel AutoFill"), for: .normal)
        cancel.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.clearCredentials()
            self.extensionContext.cancelRequest(withError: NSError(
                domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue
            ))
        }, for: .touchUpInside)
        let container = UIStackView(arrangedSubviews: [statusLabel, searchBar, scroll, cancel])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .vertical
        container.spacing = 20
        view.addSubview(container)

        let bottomAnchor: NSLayoutYAxisAnchor
        if #available(iOS 15.0, *) {
            bottomAnchor = view.keyboardLayoutGuide.topAnchor
        } else {
            bottomAnchor = view.safeAreaLayoutGuide.bottomAnchor
        }
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        unlockRecords { [weak self] result in
            self?.show(
                result.credentials,
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

    @available(iOS 26.2, *)
    override func prepareInterface(for generatePasswordsRequest: ASGeneratePasswordsRequest) {
        loadViewIfNeeded()
        clearCredentials()
        let service = generatePasswordsRequest.serviceIdentifier
        let domain: String?
        switch service.type {
        case .URL:
            let components = URLComponents(string: service.identifier)
            domain = components?.scheme?.lowercased() == "https"
                ? AutoFillCredentialRecord.normalizeDomain(service.identifier) : nil
        case .domain:
            domain = AutoFillCredentialRecord.normalizeDomain(service.identifier)
        default:
            domain = nil
        }
        guard let domain,
              let rules = try? StrongPasswordGenerator.Rules.parse([
                generatePasswordsRequest.passwordFieldPasswordRules,
                generatePasswordsRequest.confirmPasswordFieldPasswordRules,
                generatePasswordsRequest.passwordRulesFromQuirks,
              ]),
              (try? GeneratedPasswordHistory().hasActiveSession()) == true else {
            showUnavailableMessage()
            return
        }
        statusLabel.text = String(format: NSLocalizedString(
            "credential_provider_generate_prompt",
            comment: "New password generation confirmation"
        ), domain)
        let generate = UIButton(type: .system)
        generate.setTitle(NSLocalizedString(
            "credential_provider_generate_action", comment: "Generate password action"
        ), for: .normal)
        generate.addAction(UIAction { [weak self] _ in
            self?.generatePassword(for: domain, rules: rules)
        }, for: .touchUpInside)
        credentialsStack.addArrangedSubview(generate)

        let cancel = UIButton(type: .system)
        cancel.setTitle(NSLocalizedString(
            "credential_provider_cancel", comment: "Cancel generation"
        ), for: .normal)
        cancel.addAction(UIAction { [weak self] _ in
            self?.extensionContext.cancelRequest(withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userCanceled.rawValue
            ))
        }, for: .touchUpInside)
        credentialsStack.addArrangedSubview(cancel)
    }

    @available(iOS 26.2, *)
    private func generatePassword(for domain: String, rules: StrongPasswordGenerator.Rules) {
        credentialsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statusLabel.text = NSLocalizedString(
            "credential_provider_unlocking", comment: "Waiting for biometric authentication"
        )
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let history = try GeneratedPasswordHistory()
                let password = try StrongPasswordGenerator.generate(rules: rules)
                let prompt = NSLocalizedString(
                    "credential_provider_generate_biometric",
                    comment: "Biometric prompt for generated password history"
                )
                try history.appendAndHandoff(
                    domain: domain, password: password, prompt: prompt
                ) {
                    DispatchQueue.main.sync {
                        self.extensionContext.completeGeneratePasswordRequest(
                            results: [ASGeneratedPassword(kind: .strong, value: password)],
                            completionHandler: nil
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.showUnavailableMessage() }
            }
        }
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
        loadViewIfNeeded()
        clearCredentials()
        let generation = requestGeneration
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
                DispatchQueue.main.async { [weak self] in
                    guard self?.requestGeneration == generation else { return }
                    completion(result)
                }
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
                DispatchQueue.main.async { [weak self] in
                    guard self?.requestGeneration == generation else { return }
                    self?.showUnavailableMessage()
                }
            }
        }
    }

    private func show(
        _ credentials: [AutoFillCredentialLease],
        serviceIdentifiers: [ASCredentialServiceIdentifier]
    ) {
        picker = AutoFillCredentialPicker(credentials: credentials, serviceIdentifiers: serviceIdentifiers)
        visibleServiceIdentifiers = serviceIdentifiers
        searchBar.isHidden = !serviceIdentifiers.isEmpty
        renderCandidates()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        renderCandidates()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    private func renderCandidates() {
        visibleCredentials = picker?.candidates(query: searchBar.text ?? "") ?? []
        credentialsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let manual = picker?.requiresManualConfirmation == true
        statusLabel.text = manual
            ? NSLocalizedString("credential_provider_manual_warning", comment: "Unverified destination warning")
            : nil
        if visibleCredentials.isEmpty {
            let noMatches = NSLocalizedString("credential_provider_no_matches", comment: "No matching credentials")
            statusLabel.text = [statusLabel.text, noMatches].compactMap { $0 }.joined(separator: "\n\n")
        }
        for (index, credential) in visibleCredentials.enumerated() {
            let record = credential.record
            let button = UIButton(type: .system)
            let details = manual ? "\(record.username)\n\(record.domains.joined(separator: ", "))" : record.username
            button.setTitle("\(record.label)\n\(details)", for: .normal)
            button.setImage(UIImage(systemName: "key.fill"), for: .normal)
            button.titleLabel?.numberOfLines = 0
            button.contentHorizontalAlignment = .leading
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
            button.tag = index
            button.addTarget(self, action: #selector(selectCredential(_:)), for: .touchUpInside)
            credentialsStack.addArrangedSubview(button)
        }
    }

    @objc private func selectCredential(_ sender: UIButton) {
        guard visibleCredentials.indices.contains(sender.tag), let picker else { return }
        if let credential = picker.select(recordID: visibleCredentials[sender.tag].record.id) {
            complete(credential, serviceIdentifiers: visibleServiceIdentifiers)
            return
        }
        guard let pending = picker.pendingConfirmation else { return }
        let generation = requestGeneration
        let alert = UIAlertController(
            title: NSLocalizedString("credential_provider_manual_confirm_title", comment: "Manual fill confirmation"),
            message: String(format: NSLocalizedString(
                "credential_provider_manual_confirm_message", comment: "Selected credential and domains"
            ), pending.record.label, pending.record.domains.joined(separator: ", ")),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("credential_provider_cancel", comment: "Cancel manual selection"), style: .cancel
        ) { [weak picker] _ in picker?.cancelSelection() })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("credential_provider_manual_fill", comment: "Confirm one manual fill"), style: .default
        ) { [weak self, weak picker] _ in
            guard let self, let picker, self.picker === picker,
                  self.requestGeneration == generation,
                  let selection = picker.confirmManualSelection() else { return }
            self.completeManualSelection(selection)
        })
        present(alert, animated: true)
    }

    private func completeManualSelection(_ selection: AutoFillManualSelection) {
        do {
            let store = try AutoFillCacheStore()
            try store.withRevalidatedManualSelection(selection) {
                extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(
                    user: selection.credential.record.username,
                    password: selection.credential.record.password
                ), completionHandler: nil)
            }
            clearCredentials()
        } catch {
            if let store = try? AutoFillCacheStore() {
                try? store.quarantine(
                    generation: selection.credential.generation,
                    cacheId: selection.credential.cacheId
                )
            }
            showUnavailableMessage()
        }
    }

    private func clearCredentials() {
        requestGeneration += 1
        picker?.clear()
        picker = nil
        visibleCredentials.removeAll(keepingCapacity: false)
        visibleServiceIdentifiers.removeAll(keepingCapacity: false)
        credentialsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        searchBar.text = nil
        searchBar.isHidden = true
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
            clearCredentials()
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
        clearCredentials()
        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userInteractionRequired.rawValue
        ))
    }

    private func showLockedMessage() {
        clearCredentials()
        statusLabel.text = NSLocalizedString(
            "credential_provider_locked",
            comment: "Message shown when Palladin must be unlocked."
        )
    }

    private func showUnavailableMessage() {
        clearCredentials()
        statusLabel.text = NSLocalizedString(
            "credential_provider_unavailable",
            comment: "Shown when biometric authentication or cache access fails."
        )
    }
}
