import Flutter
import Foundation
import sqflite_darwin

/// One short-lived engine uses the app's existing Dart crypto and readonly DB.
/// No app registrar, network bootstrap, analytics or persistent plaintext bridge.
final class MemberCredentialRuntime {
    let request: SharedMemberCredentialRequest
    private var engine: FlutterEngine?
    private var channel: FlutterMethodChannel?
    private var opening: [String: Any]?
    private var onRows: (([SharedMemberCandidate]) -> Void)?
    private var onFailure: (() -> Void)?
    private let handoff: (String, String) throws -> Void
    private var closed = false
    private var attempt: UUID?

    init(request: SharedMemberCredentialRequest, handoff: @escaping (String, String) throws -> Void) {
        self.request = request; self.handoff = handoff
    }

    func open(databaseURL: URL, masterPassword: String?, masterKey: Data?,
              rows: @escaping ([SharedMemberCandidate]) -> Void, failure: @escaping () -> Void) throws {
        guard engine == nil, !closed, (masterPassword != nil) != (masterKey != nil) else { throw SharedMemberSourceError.stale }
        attempt = try request.beginAuthentication()
        var arguments: [String: Any] = ["databasePath": databaseURL.path, "request": request.arguments,
            "claims": request.snapshot.claims.arguments,
            "accountUnlock": try JSONSerialization.jsonObject(with: request.snapshot.accountUnlock)]
        if let masterPassword { arguments["masterPassword"] = masterPassword }
        if let masterKey { arguments["masterKey"] = FlutterStandardTypedData(bytes: masterKey) }
        opening = arguments; onRows = rows; onFailure = failure
        guard let assets = Bundle(path: Bundle.main.bundlePath + "/Frameworks/App.framework") else {
            close(); throw SharedMemberSourceError.unavailable
        }
        let project = FlutterDartProject(precompiledDartBundle: assets)
        let runtime = FlutterEngine(name: "palladin-credential-" + request.id, project: project, allowHeadlessExecution: true)
        engine = runtime
        guard runtime.run(withEntrypoint: "autoFillExtensionMain", libraryURI: "package:mobile_palladin/autofill_extension.dart") else {
            close(); throw SharedMemberSourceError.unavailable
        }
        if let registrar = runtime.registrar(forPlugin: "SqflitePlugin") { SqflitePlugin.register(with: registrar) }
        let bridge = FlutterMethodChannel(name: "io.palladin.mobile/autofill-extension", binaryMessenger: runtime.binaryMessenger)
        channel = bridge
        bridge.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) ?? result(false) }
    }

    func select(_ candidate: SharedMemberCandidate, host: String, manualConfirmed: Bool) throws {
        let selection = try request.prepareSelection(id: candidate.id, host: host, manualConfirmed: manualConfirmed)
        guard !closed, let channel else { throw SharedMemberSourceError.stale }
        channel.invokeMethod("select", arguments: selection) { [weak self] value in
            guard let self, !self.closed else { return }
            if value is FlutterError { self.fail() }
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard !closed else { result(false); return }
        switch call.method {
        case "ready":
            result(nil)
            guard let arguments = opening, let attempt, let channel else { fail(); return }
            opening = nil
            channel.invokeMethod("open", arguments: arguments) { [weak self] value in
                guard let self, !self.closed else { return }
                do {
                    guard let rows = value as? [[String: Any]] else { throw SharedMemberSourceError.unavailable }
                    // This callback belongs to this request's actual successful
                    // KDF/private-key unwrap, not an external authenticated flag.
                    try self.request.authenticationSucceeded(attempt, rows: rows)
                    self.onRows?(self.request.candidates)
                } catch { self.fail() }
            }
        case "validateSource":
            do { try request.validate(); result(true) } catch { result(false) }
        case "complete":
            do {
                guard let response = call.arguments as? [String: Any] else { throw SharedMemberSourceError.invalid }
                try request.complete(response, handoff: handoff)
                result(true)
                DispatchQueue.main.async { [weak self] in self?.close() }
            } catch { result(false); fail() }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func fail() {
        let callback = onFailure
        close()
        callback?()
    }

    func close() {
        guard !closed else { return }
        closed = true; request.cancel(); opening = nil; onRows = nil; onFailure = nil; attempt = nil
        guard let channel, let engine else { return }
        self.channel = nil; self.engine = nil
        // Runtime closes its readonly DB and wipes its key before engine teardown.
        channel.invokeMethod("close", arguments: nil) { _ in
            channel.setMethodCallHandler(nil)
            engine.destroyContext()
        }
    }
}
