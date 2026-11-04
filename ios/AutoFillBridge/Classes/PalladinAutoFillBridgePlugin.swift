import AuthenticationServices
import Flutter
import Foundation

final class AutoFillBridgeMutationQueue {
    private let queue = DispatchQueue(
        label: "io.palladin.mobile.autofill.bridge-mutations",
        qos: .userInitiated
    )

    func submit(_ operation: @escaping () -> Void) {
        queue.async(execute: operation)
    }
}

public final class PalladinAutoFillBridgePlugin: NSObject, FlutterPlugin {
    private let mutationQueue = AutoFillBridgeMutationQueue()
    private let memberSource = try? SharedMemberSourceBridge()
    private let incrementalWriter = AutoFillV3Writer()
    private let historyQueue = DispatchQueue(
        label: "io.palladin.mobile.autofill.generated-history",
        qos: .userInitiated
    )

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.palladin.mobile/autofill",
            binaryMessenger: registrar.messenger()
        )
        PendingPasswordSavePlugin.register(with: registrar)
        let instance = PalladinAutoFillBridgePlugin()
        if let bridge = instance.memberSource {
            SharedBiometricUnlockPlugin.register(with: registrar, source: bridge.source,
                containerURL: bridge.containerURL, accessGroup: bridge.accessGroup, allowLegacyMigration: true)
        }
        instance.historyQueue.async {
            try? GeneratedPasswordHistory().revokeAll()
        }
        registrar.addMethodCallDelegate(instance, channel: channel)
        // The app source controller uses the request channel on both platforms.
        // Share the same fence and RAM capability owner with the legacy bridge.
        let requestChannel = FlutterMethodChannel(
            name: "io.palladin.mobile/autofill-request",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: requestChannel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if SharedMemberSourceBridge.methods.contains(call.method) {
            do {
                guard let bridge = memberSource else { throw SharedMemberSourceError.unavailable }
                // Source denial must not sit behind legacy publication/identity work.
                result(try bridge.handle(call.method, arguments: call.arguments as? [String: Any] ?? [:]))
            } catch {
                result(FlutterError(code: "AUTOFILL_SOURCE_UNAVAILABLE", message: nil, details: nil))
            }
            return
        }
        if call.method == "getProviderStatus" {
            ASCredentialIdentityStore.shared.getState { state in
                DispatchQueue.main.async {
                    if #available(iOS 17.0, *) {
                        result(state.isEnabled ? "enabled" : "disabled")
                    } else {
                        result(state.isEnabled ? "enabledManual" : "manual")
                    }
                }
            }
            return
        }
        if call.method == "openProviderSettings" {
            if #available(iOS 17.0, *) {
                ASSettingsHelper.openCredentialProviderAppSettings { error in
                    DispatchQueue.main.async {
                        if error == nil {
                            result(nil)
                        } else {
                            result(FlutterError(code: "AUTOFILL_SETTINGS_ERROR",
                                message: "AutoFill settings are unavailable", details: nil))
                        }
                    }
                }
            } else {
                result(FlutterError(code: "AUTOFILL_MANUAL_SETUP",
                    message: "Open AutoFill settings manually", details: nil))
            }
            return
        }
        if call.method == "endWriterSession" {
            guard let arguments = call.arguments as? [String: Any],
                  let epoch = AutoFillV3JSON.positive(arguments["writerEpoch"]) else {
                result(FlutterError(code: "AUTOFILL_CACHE_ERROR", message: "Invalid writer epoch", details: nil)); return
            }
            // Bypass queued crypto/identity work; pending commits recheck epoch.
            incrementalWriter.end(epoch: epoch)
            result(nil)
            return
        }
        if ["beginCacheSession", "revokeCacheAccess"].contains(call.method) {
            incrementalWriter.invalidate()
        } else if call.method == "clearCache",
                  let arguments = call.arguments as? [String: Any],
                  let token = AutoFillV3JSON.positive(arguments["sessionToken"]) {
            incrementalWriter.invalidate(generation: token)
        }
        let action = {
            do {
                let store = try AutoFillCacheStore()
                switch call.method {
                case "beginCacheSession":
                    let sessionToken = try store.beginSession()
                    DispatchQueue.main.async { result(sessionToken) }
                case "revokeCacheAccess":
                    // The durable generation fence is the revocation commit
                    // point. Physical artifacts and identity metadata are
                    // cleaned asynchronously and never delay logout.
                    let cleanupToken = try store.revokeAccess()
                    DispatchQueue.main.async { result(cleanupToken) }
                    DispatchQueue.global(qos: .utility).async {
                        try? store.cleanupRevoked(generation: cleanupToken)
                    }
                    AutoFillCacheStore.clearIdentities(
                        store: store,
                        onlyIf: { !store.hasActiveCache() }
                    ) { _ in }
                case "beginWriterSession":
                    guard let arguments = call.arguments as? [String: Any],
                          let token = AutoFillV3JSON.positive(arguments["sessionToken"]) else { throw AutoFillV3Error.invalid }
                    let epoch = try store.beginWriterSession(sessionToken: token, writer: self.incrementalWriter)
                    DispatchQueue.main.async { result(epoch) }
                case "replaceCacheV3", "denyEntries", "applyCacheDelta":
                    guard let arguments = call.arguments as? [String: Any] else { throw AutoFillV3Error.invalid }
                    let publication: AutoFillV3Publication
                    if call.method == "replaceCacheV3" {
                        guard let payload = arguments["payload"] as? [String: Any],
                              let token = AutoFillV3JSON.positive(arguments["sessionToken"]),
                              let epoch = AutoFillV3JSON.positive(arguments["writerEpoch"]) else { throw AutoFillV3Error.invalid }
                        let base = try (arguments["base"] as? [String: Any]).map(AutoFillV3Base.init)
                        let releasing = arguments["releasingDenies"] as? [String] ?? []
                        publication = try store.replaceV3(payload: payload, sessionToken: token, epoch: epoch,
                                                          writer: self.incrementalWriter, expectedBase: base, releasingDenies: releasing)
                    } else {
                        publication = try store.mutateV3(arguments: arguments, writer: self.incrementalWriter, deny: call.method == "denyEntries")
                    }
                    if !publication.updatesIdentities {
                        DispatchQueue.main.async { result(publication.response) }
                        return
                    }
                    AutoFillCacheStore.publishV3Identities(publication, store: store) { error in
                        DispatchQueue.main.async {
                            if let error {
                                result(FlutterError(code: (error as? AutoFillV3Error)?.code ?? "AUTOFILL_IDENTITY_ERROR", message: "Unable to update credential identities", details: nil))
                            } else { result(publication.response) }
                        }
                    }
                case "replaceCache":
                    guard let arguments = call.arguments as? [String: Any],
                          let payload = arguments["payload"] as? [String: Any],
                          let sessionToken = arguments["sessionToken"] as? Int else {
                        throw AutoFillCacheError.invalidRecords
                    }
                    let replacement = try store.replace(
                        payload: payload,
                        sessionToken: sessionToken
                    )
                    AutoFillCacheStore.replaceIdentities(
                        for: replacement,
                        store: store
                    ) { error in
                        if error == nil {
                            DispatchQueue.main.async { result(nil) }
                        } else {
                            try? store.quarantine(
                                generation: replacement.generation,
                                cacheId: replacement.cacheId
                            )
                            DispatchQueue.main.async {
                                result(FlutterError(
                                    code: "AUTOFILL_IDENTITY_ERROR",
                                    message: "Unable to update credential identities",
                                    details: nil
                                ))
                            }
                        }
                    }
                case "clearCache":
                    guard let arguments = call.arguments as? [String: Any],
                          let sessionToken = arguments["sessionToken"] as? Int else {
                        throw AutoFillCacheError.invalidRecords
                    }
                    try store.clear(sessionToken: sessionToken)
                    AutoFillCacheStore.clearIdentities(
                        store: store,
                        onlyIf: { !store.hasActiveCache() }
                    ) { error in
                        DispatchQueue.main.async {
                            if error == nil {
                                result(nil)
                            } else {
                                result(FlutterError(
                                    code: "AUTOFILL_IDENTITY_ERROR",
                                    message: "Unable to clear credential identities",
                                    details: nil
                                ))
                            }
                        }
                    }
                case "activateGeneratedPasswordHistory":
                    guard let args = call.arguments as? [String: Any],
                          let principalId = args["principalId"] as? String else {
                        throw GeneratedPasswordHistoryError.invalidState
                    }
                    let token = try GeneratedPasswordHistory().activate(principalId: principalId)
                    DispatchQueue.main.async { result(token) }
                case "revokeGeneratedPasswordHistory":
                    guard let args = call.arguments as? [String: Any],
                          let token = args["token"] as? String else {
                        throw GeneratedPasswordHistoryError.invalidState
                    }
                    try GeneratedPasswordHistory().revoke(token: token)
                    DispatchQueue.main.async { result(nil) }
                case "revokeAllGeneratedPasswordSessions":
                    try GeneratedPasswordHistory().revokeAll()
                    DispatchQueue.main.async { result(nil) }
                case "listGeneratedPasswords", "revealGeneratedPassword",
                     "deleteGeneratedPassword", "clearGeneratedPasswords",
                     "generatePasswordForEntry":
                    guard let args = call.arguments as? [String: Any],
                          let principalId = args["principalId"] as? String else {
                        throw GeneratedPasswordHistoryError.invalidState
                    }
                    let history = try GeneratedPasswordHistory()
                    guard let prompt = args["prompt"] as? String,
                          !prompt.isEmpty else {
                        throw GeneratedPasswordHistoryError.invalidState
                    }
                    switch call.method {
                    case "generatePasswordForEntry":
                        guard let domain = args["domain"] as? String else {
                            throw GeneratedPasswordHistoryError.invalidState
                        }
                        let password = try StrongPasswordGenerator.generate()
                        try history.appendAndHandoff(
                            domain: domain,
                            password: password,
                            prompt: prompt,
                            expectedPrincipal: principalId
                        ) {
                            DispatchQueue.main.sync { result(password) }
                        }
                    case "listGeneratedPasswords":
                        let records = try history.list(expectedPrincipal: principalId, prompt: prompt)
                        DispatchQueue.main.async {
                            result(records.map { record in
                                ["id": record.id, "domain": record.domain,
                                 "createdAtMillis": record.createdAtMillis]
                            })
                        }
                    case "revealGeneratedPassword":
                        guard let id = args["id"] as? String else {
                            throw GeneratedPasswordHistoryError.invalidState
                        }
                        let password = try history.list(
                            expectedPrincipal: principalId, prompt: prompt
                        ).first(where: { $0.id == id })?.password
                        guard let password else { throw GeneratedPasswordHistoryError.invalidState }
                        DispatchQueue.main.async { result(password) }
                    case "deleteGeneratedPassword":
                        guard let id = args["id"] as? String else {
                            throw GeneratedPasswordHistoryError.invalidState
                        }
                        try history.delete(expectedPrincipal: principalId, id: id, prompt: prompt)
                        DispatchQueue.main.async { result(nil) }
                    default:
                        try history.clear(expectedPrincipal: principalId, prompt: prompt)
                        DispatchQueue.main.async { result(nil) }
                    }
                default:
                    DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: (error as? AutoFillV3Error)?.code ?? "AUTOFILL_CACHE_ERROR",
                        message: "Native cache operation failed",
                        details: nil
                    ))
                }
            }
        }
        if call.method.contains("GeneratedPassword") ||
            call.method == "generatePasswordForEntry" {
            historyQueue.async(execute: action)
        } else {
            mutationQueue.submit(action)
        }
    }
}
