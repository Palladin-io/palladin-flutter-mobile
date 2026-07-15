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
                    try store.clear()
                    DispatchQueue.main.async { result(nil) }
                case "replaceCache":
                    guard let records = call.arguments as? [[String: Any]] else {
                        throw AutoFillCacheError.invalidRecords
                    }
                    let validated = try store.replace(records: records)
                    AutoFillCacheStore.replaceIdentities(for: validated) { error in
                        if error == nil {
                            DispatchQueue.main.async { result(nil) }
                        } else {
                            try? store.clear()
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
                    try store.clear()
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
