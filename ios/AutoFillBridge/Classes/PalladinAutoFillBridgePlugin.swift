import Flutter
import Foundation

public final class PalladinAutoFillBridgePlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "io.palladin.mobile/autofill",
            binaryMessenger: registrar.messenger()
        )
        let instance = PalladinAutoFillBridgePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let store = try AutoFillCacheStore()
                switch call.method {
                case "beginCacheSession":
                    let sessionToken = store.beginSession()
                    DispatchQueue.main.async { result(sessionToken) }
                case "revokeCacheAccess":
                    // Key/file revocation is intentionally separate from the
                    // identity-store callback, which is not guaranteed to
                    // return on a broken provider host.
                    let cleanupToken = try store.revokeAccess()
                    AutoFillCacheStore.clearIdentities { _ in }
                    DispatchQueue.main.async { result(cleanupToken) }
                case "replaceCache":
                    guard let arguments = call.arguments as? [String: Any],
                          let records = arguments["records"] as? [[String: Any]],
                          let sessionToken = arguments["sessionToken"] as? Int else {
                        throw AutoFillCacheError.invalidRecords
                    }
                    let validated = try store.replace(
                        records: records,
                        sessionToken: sessionToken
                    )
                    AutoFillCacheStore.replaceIdentities(for: validated) { error in
                        if error == nil {
                            DispatchQueue.main.async { result(nil) }
                        } else {
                            try? store.clear(sessionToken: sessionToken)
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
                    AutoFillCacheStore.clearIdentities { error in
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
