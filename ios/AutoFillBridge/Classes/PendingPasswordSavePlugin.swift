import Flutter
import Foundation
import UIKit

/// Runner owns only the unlocked-account session and a value-free consumed lease.
final class PendingPasswordSavePlugin: NSObject, FlutterPlugin {
    private let channel: FlutterMethodChannel
    private let store: PendingPasswordSave?
    private var lease: PasswordSaveAuthority?
    private var operation: PasswordSaveOperation?
    private var operationID: String?
    private var backgroundObserver: NSObjectProtocol?

    private init(channel: FlutterMethodChannel) {
        self.channel = channel
        let candidate = try? PendingPasswordSave()
        do { try candidate?.revoke(); store = candidate }
        catch { store = nil }
        super.init()
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.invalidateLocalCapture()
        }
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "io.palladin.mobile/autofill-save",
                                          binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(PendingPasswordSavePlugin(channel: channel), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let store else { result(Self.failure()); return }
        let args = call.arguments as? [String: Any] ?? [:]
        do {
            switch call.method {
            case "activate":
                guard let principal = args["principalId"] as? String else { throw PasswordSaveError.invalid }
                result(try store.activate(principal: principal))
            case "revoke":
                invalidateLocalCapture()
                try store.revoke(); result(nil)
            case "cancel":
                let id = args["id"] as? String
                guard args["id"] == nil || id != nil else { throw PasswordSaveError.invalid }
                invalidateLocalCapture(id: id)
                try store.cancel(id: id); result(nil)
            case "pending":
                result(try store.pending())
            case "validate":
                guard let id = args["id"] as? String, let session = args["session"] as? String,
                      let domain = args["domain"] as? String, let lease, lease.pending?.id == id else {
                    result(false); return
                }
                let valid = try store.validate(lease, session: session, domain: domain)
                if !valid { invalidateLocalCapture(id: id) }
                result(valid)
            case "take":
                guard let id = args["id"] as? String, let session = args["session"] as? String,
                      let prompt = args["prompt"] as? String, !prompt.isEmpty else { throw PasswordSaveError.invalid }
                invalidateLocalCapture()
                let active = PasswordSaveOperation(); operation = active; operationID = id
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    do {
                        let payload = try store.take(id: id, session: session, prompt: prompt, operation: active)
                        DispatchQueue.main.async { [weak self] in
                            do {
                                try active.perform {
                                    guard let self, self.operation === active,
                                          UIApplication.shared.applicationState == .active else {
                                        throw PasswordSaveError.invalid
                                    }
                                    guard let payload, let binding = payload.authority.pending else {
                                        result(nil); return
                                    }
                                    let domain = String(binding.origin.dropFirst("https://".count))
                                    guard try store.validate(payload.authority, session: session, domain: domain) else {
                                        throw PasswordSaveError.invalid
                                    }
                                    self.lease = payload.authority
                                    result(["id": binding.id, "mode": "IOS_HTTPS", "packageName": "",
                                            "sourceLabel": domain, "domains": [domain],
                                            "username": payload.username, "password": payload.password,
                                            "remainingMs": store.remainingMillis(binding)])
                                }
                            } catch { result(Self.failure()) }
                        }
                    } catch { DispatchQueue.main.async { result(Self.failure()) } }
                }
            default: result(FlutterMethodNotImplemented)
            }
        } catch { result(Self.failure()) }
    }

    private func invalidateLocalCapture(id: String? = nil) {
        let previousLeaseID = lease?.pending?.id
        let previousOperationID = operationID
        if id == nil || id == previousOperationID {
            operation?.cancel()
            operation = nil
            operationID = nil
        }
        if id == nil || id == previousLeaseID { lease = nil }
        for oldID in Set([previousLeaseID, previousOperationID].compactMap { $0 })
            where id == nil || id == oldID {
            channel.invokeMethod("invalidated", arguments: oldID)
        }
    }

    private static func failure() -> FlutterError {
        FlutterError(code: "AUTOFILL_SAVE_UNAVAILABLE", message: "Password save unavailable", details: nil)
    }
}
