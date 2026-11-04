import AuthenticationServices
import UIKit
import LocalAuthentication

final class CredentialProviderViewController: ASCredentialProviderViewController, UISearchBarDelegate {
    private let statusLabel = UILabel()
    private let credentialsStack = UIStackView()
    private let searchBar = UISearchBar()
    private var saveOperation: PasswordSaveOperation?
    private var memberRuntime: MemberCredentialRuntime?
    private var memberRequest: SharedMemberCredentialRequest?
    private var sourceBridge: SharedMemberSourceBridge?
    private var authenticationContext: LAContext?
    private var requestActive = false
    private lazy var requestLifecycle = AutoFillCredentialRequestLifecycle(
        notificationCenter: .default,
        hostBackgroundNotification: .NSExtensionHostDidEnterBackground,
        onHostBackground: { [weak self] in self?.cancelForHostLoss() }
    )
    private var visibleCredentials: [SharedMemberCandidate] = []
    private var allCredentials: [SharedMemberCandidate] = []
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent || parent?.isBeingDismissed == true {
            cancelForHostLoss()
        }
    }

    private func cancelForHostLoss() {
        guard requestActive else { return }
        clearCredentials()
        presentedViewController?.dismiss(animated: false)
        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue
        ))
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        prepareMemberRequest(serviceIdentifiers: serviceIdentifiers)
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
    override func performWithoutUserInteractionIfPossible(savePasswordRequest: ASSavePasswordRequest) {
        requireUserInteraction()
    }

    @available(iOS 26.2, *)
    override func prepareInterface(for savePasswordRequest: ASSavePasswordRequest) {
        loadViewIfNeeded()
        clearCredentials()
        guard let origin = PendingPasswordSave.origin(for: savePasswordRequest),
              let session = try? PendingPasswordSave().activeSession()
        else {
            extensionContext.cancelRequest(withError: NSError(
                domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue))
            return
        }
        let operation = PasswordSaveOperation()
        saveOperation = operation
        requestActive = true
        statusLabel.text = String(format: NSLocalizedString(
            "credential_provider_save_prompt", comment: "Two-stage save consent"), origin)
        let save = UIButton(type: .system)
        save.setTitle(NSLocalizedString("credential_provider_save_action", comment: "Stage password"), for: .normal)
        save.addAction(UIAction { [weak self, weak save] _ in
            guard let self, self.requestActive else { return }
            save?.isEnabled = false
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    let store = try PendingPasswordSave()
                    let id = try store.stage(expectedSession: session, origin: origin,
                        formSession: savePasswordRequest.sessionID,
                        username: savePasswordRequest.credential.user,
                        password: savePasswordRequest.credential.password,
                        prompt: NSLocalizedString("credential_provider_save_biometric", comment: "Save biometric"),
                        operation: operation)
                    DispatchQueue.main.async { [weak self] in
                        do {
                            try store.completeStaging(id: id, session: session, operation: operation) {
                                guard let self, self.requestActive else { throw PasswordSaveError.invalid }
                                self.requestActive = false
                                self.extensionContext.completeSavePasswordRequest { expired in
                                    if expired {
                                        DispatchQueue.global(qos: .userInitiated).async { try? store.discard(id: id) }
                                    }
                                }
                            }
                            self?.clearCredentials()
                        } catch { try? store.discard(id: id) }
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        guard self?.saveOperation === operation else { return }
                        self?.showUnavailableMessage()
                    }
                }
            }
        }, for: .touchUpInside)
        credentialsStack.addArrangedSubview(save)
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

    private func unlockAndComplete(recordIdentifier: String?, serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        // OS identity metadata is only a navigation hint. Resolve current local
        // index metadata after authentication, never trust an old record ID.
        prepareMemberRequest(serviceIdentifiers: serviceIdentifiers)
    }

    private func prepareMemberRequest(serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        loadViewIfNeeded()
        clearCredentials()
        do {
            var hosts = Set<String>()
            for service in serviceIdentifiers {
                if service.type == .URL {
                    guard URLComponents(string: service.identifier)?.scheme?.lowercased() == "https" else {
                        throw SharedMemberSourceError.invalid
                    }
                } else if service.type != .domain { throw SharedMemberSourceError.invalid }
                guard let host = AutoFillCredentialRecord.normalizeDomain(service.identifier) else {
                    throw SharedMemberSourceError.invalid
                }
                hosts.insert(host)
            }
            let bridge = try SharedMemberSourceBridge()
            let request = try SharedMemberCredentialRequest(source: bridge.source,
                snapshot: bridge.source.current(), verifiedHosts: hosts)
            sourceBridge = bridge; memberRequest = request
            visibleServiceIdentifiers = serviceIdentifiers
            requestActive = true
            statusLabel.text = NSLocalizedString("credential_provider_unlock_choice", comment: "Unlock choices")
            let password = UITextField()
            password.isSecureTextEntry = true
            password.textContentType = .password
            password.borderStyle = .roundedRect
            password.placeholder = NSLocalizedString("credential_provider_master_password", comment: "Master password")
            password.accessibilityLabel = password.placeholder
            let unlock = UIButton(type: .system)
            unlock.setTitle(NSLocalizedString("credential_provider_unlock_password", comment: "Unlock with password"), for: .normal)
            unlock.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            unlock.addAction(UIAction { [weak self, weak password] _ in
                guard let self, let value = password?.text, !value.isEmpty else { return }
                password?.text = nil
                self.openMemberRuntime(password: value, key: nil, request: request)
            }, for: .touchUpInside)
            let biometric = UIButton(type: .system)
            biometric.setTitle(NSLocalizedString("credential_provider_unlock_biometric", comment: "Optional biometric unlock"), for: .normal)
            biometric.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            biometric.addAction(UIAction { [weak self] _ in self?.unlockMemberBiometrically(request: request, bridge: bridge) }, for: .touchUpInside)
            [password, unlock, biometric].forEach { credentialsStack.addArrangedSubview($0) }
        } catch { showUnavailableMessage() }
    }

    private func unlockMemberBiometrically(request: SharedMemberCredentialRequest, bridge: SharedMemberSourceBridge) {
        guard memberRequest === request, requestActive, memberRuntime == nil else { return }
        let context = LAContext()
        context.localizedReason = NSLocalizedString("credential_provider_biometric_prompt", comment: "Biometric prompt")
        authenticationContext?.invalidate()
        authenticationContext = context
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let store = try SharedBiometricUnlock(containerURL: bridge.containerURL, accessGroup: bridge.accessGroup)
                var key = try store.read(profileBinding: request.snapshot.profileBinding, context: context,
                    validateOperation: { try request.validate() })
                DispatchQueue.main.sync {
                    defer { key.resetBytes(in: 0..<key.count) }
                    guard let self, self.memberRequest === request, self.requestActive else { return }
                    self.authenticationContext = nil
                    self.openMemberRuntime(password: nil, key: key, request: request)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.memberRequest === request else { return }
                    self.authenticationContext = nil
                    // Cancellation does not revoke the source or make password mandatory biometry.
                    self.statusLabel.text = NSLocalizedString("credential_provider_unlock_choice", comment: "Unlock choices")
                }
            }
        }
    }

    private func openMemberRuntime(password: String?, key: Data?, request: SharedMemberCredentialRequest) {
        guard memberRequest === request, requestActive, memberRuntime == nil, let sourceBridge else { return }
        authenticationContext?.invalidate(); authenticationContext = nil
        credentialsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statusLabel.text = NSLocalizedString("credential_provider_unlocking", comment: "Unlocking")
        let runtime = MemberCredentialRuntime(request: request) { [weak self] user, password in
            guard let self, self.memberRequest === request, self.requestActive else { throw SharedMemberSourceError.stale }
            self.requestActive = false
            self.extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: user, password: password), completionHandler: nil)
        }
        memberRuntime = runtime
        do {
            try runtime.open(databaseURL: sourceBridge.containerURL.appendingPathComponent("member-source/vault_member_sync.db"),
                masterPassword: password, masterKey: key, rows: { [weak self] rows in
                    guard let self, self.memberRequest === request, self.requestActive else { return }
                    self.allCredentials = rows
                    self.searchBar.isHidden = !request.verifiedHosts.isEmpty
                    self.renderCandidates()
                }, failure: { [weak self] in
                    guard self?.memberRequest === request else { return }
                    self?.showUnavailableMessage()
                })
        } catch { showUnavailableMessage() }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { renderCandidates() }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }

    private func renderCandidates() {
        let query = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        visibleCredentials = allCredentials.filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) || $0.domains.contains(where: { $0.localizedCaseInsensitiveContains(query) }) }
        credentialsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let manual = memberRequest?.verifiedHosts.isEmpty == true
        statusLabel.text = manual ? NSLocalizedString("credential_provider_manual_warning", comment: "Unverified destination warning") : nil
        if visibleCredentials.isEmpty {
            statusLabel.text = [statusLabel.text, NSLocalizedString("credential_provider_no_matches", comment: "No matches")].compactMap { $0 }.joined(separator: "\n\n")
        }
        for (index, credential) in visibleCredentials.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle("\(credential.label)\n\(credential.domains.joined(separator: ", "))", for: .normal)
            button.setImage(UIImage(systemName: "key.fill"), for: .normal)
            button.titleLabel?.numberOfLines = 0
            button.contentHorizontalAlignment = .leading
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            button.tag = index
            button.addTarget(self, action: #selector(selectCredential(_:)), for: .touchUpInside)
            credentialsStack.addArrangedSubview(button)
        }
    }

    @objc private func selectCredential(_ sender: UIButton) {
        guard presentedViewController == nil, requestActive, visibleCredentials.indices.contains(sender.tag),
              let request = memberRequest else { return }
        let credential = visibleCredentials[sender.tag]
        if let host = credential.domains.first(where: { request.verifiedHosts.contains($0) }) {
            complete(credential, host: host, manual: false)
            return
        }
        guard request.verifiedHosts.isEmpty, let host = credential.domains.first else { return }
        let alert = UIAlertController(title: NSLocalizedString("credential_provider_manual_confirm_title", comment: "Manual confirmation"),
            message: String(format: NSLocalizedString("credential_provider_manual_confirm_message", comment: "Manual destination"), credential.label, host), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("credential_provider_cancel", comment: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("credential_provider_manual_fill", comment: "Fill once"), style: .default) { [weak self] _ in
            guard let self, self.memberRequest === request, self.requestActive else { return }
            self.complete(credential, host: host, manual: true)
        })
        present(alert, animated: true)
    }

    private func complete(_ credential: SharedMemberCandidate, host: String, manual: Bool) {
        do { try memberRuntime?.select(credential, host: host, manualConfirmed: manual) }
        catch { showUnavailableMessage() }
    }

    private func clearCredentials() {
        saveOperation?.cancel(); saveOperation = nil
        requestActive = false; requestLifecycle.invalidate()
        authenticationContext?.invalidate(); authenticationContext = nil
        memberRuntime?.close(); memberRuntime = nil
        memberRequest?.cancel(); memberRequest = nil; sourceBridge = nil
        visibleCredentials.removeAll(); allCredentials.removeAll(); visibleServiceIdentifiers.removeAll()
        credentialsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        searchBar.text = nil; searchBar.isHidden = true
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
