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
                case "revokeCacheAccess":
                    // Key/file revocation is intentionally separate from the
                    // identity-store callback, which is not guaranteed to
                    // return on a broken provider host.
                    guard let arguments = call.arguments as? [String: Any],
                          let generation = arguments["generation"] as? Int else {
                        throw AutoFillCacheError.invalidRecords
                    }
                    try store.revokeAccess(generation: generation)
                    AutoFillCacheStore.clearIdentities { _ in }
                    DispatchQueue.main.async { result(nil) }
                case "replaceCache":
                    guard let arguments = call.arguments as? [String: Any],
                          let records = arguments["records"] as? [[String: Any]],
                          let generation = arguments["generation"] as? Int else {
                        throw AutoFillCacheError.invalidRecords
                    }
                    let validated = try store.replace(
                        records: records,
                        generation: generation
                    )
                    AutoFillCacheStore.replaceIdentities(for: validated) { error in
                        if error == nil {
                            DispatchQueue.main.async { result(nil) }
                        } else {
                            try? store.clear(generation: generation)
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
                          let generation = arguments["generation"] as? Int else {
                        throw AutoFillCacheError.invalidRecords
                    }
                    try store.clear(generation: generation)
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
