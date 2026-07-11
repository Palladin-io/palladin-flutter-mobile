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
                case "replaceCache":
                    guard let records = call.arguments as? [[String: Any]] else {
                        throw AutoFillCacheError.invalidRecords
                    }
                    let validated = try store.replace(records: records)
                    AutoFillCacheStore.replaceIdentities(for: validated) { error in
                        if error == nil {
                            DispatchQueue.main.async { result(nil) }
                        } else {
                            store.clear()
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
                    store.clear()
                    AutoFillCacheStore.clearIdentities {
                        DispatchQueue.main.async { result(nil) }
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
