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

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.palladin.mobile/autofill",
            binaryMessenger: registrar.messenger()
        )
        let instance = PalladinAutoFillBridgePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        mutationQueue.submit {
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
                default:
                    DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "AUTOFILL_CACHE_ERROR",
                        message: "Native cache operation failed",
                        details: nil
                    ))
                }
            }
        }
    }
}
