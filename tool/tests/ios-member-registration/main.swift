import Flutter
import Foundation
import UIKit

final class Messenger: NSObject, FlutterBinaryMessenger {
    var handlers: [String: FlutterBinaryMessageHandler] = [:]
    func send(onChannel: String, message: Data?) {}
    func send(onChannel: String, message: Data?, binaryReply: FlutterBinaryReply?) {}
    func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
        handlers[channel] = binaryMessageHandler
        return Int64(handlers.count)
    }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
final class Registrar: NSObject, FlutterPluginRegistrar, FlutterTextureRegistry {
    let transport = Messenger()
    var delegates: [FlutterPlugin] = []
    var viewController: UIViewController? { nil }
    func messenger() -> FlutterBinaryMessenger { transport }
    func textures() -> FlutterTextureRegistry { self }
    func register(_ factory: FlutterPlatformViewFactory, withId: String) {}
    func register(_ factory: FlutterPlatformViewFactory, withId: String, gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicy) {}
    func publish(_ value: NSObject) {}
    func addMethodCallDelegate(_ delegate: FlutterPlugin, channel: FlutterMethodChannel) {
        delegates.append(delegate)
        channel.setMethodCallHandler { call, result in delegate.handle?(call, result: result) }
    }
    func addApplicationDelegate(_ delegate: FlutterPlugin) {}
    func addSceneDelegate(_ delegate: FlutterSceneLifeCycleDelegate) {}
    func lookupKey(forAsset asset: String) -> String { asset }
    func lookupKey(forAsset asset: String, fromPackage package: String) -> String { asset }
    func register(_ texture: FlutterTexture) -> Int64 { 0 }
    func textureFrameAvailable(_ textureId: Int64) {}
    func unregisterTexture(_ textureId: Int64) {}
}
let registrar = Registrar()
PalladinAutoFillBridgePlugin.register(with: registrar)
let codec = FlutterStandardMethodCodec.sharedInstance()
for channel in ["io.palladin.mobile/autofill-request", "io.palladin.mobile/autofill"] {
    guard let handler = registrar.transport.handlers[channel] else {
        fputs("FAIL: source bootstrap channel is unregistered: \(channel)\n", stderr)
        exit(1)
    }
    var answered = false
    handler(codec.encode(FlutterMethodCall(methodName: "sourceSnapshot", arguments: nil))) { reply in
        // This unsigned command-line harness has no App Group. The real plugin
        // must handle the request and fail closed, rather than MissingPlugin.
        guard let reply, let failure = codec.decodeEnvelope(reply) as? FlutterError,
              failure.code == "AUTOFILL_SOURCE_UNAVAILABLE" else {
            fputs("FAIL: source bootstrap did not reach native authority guard\n", stderr)
            exit(1)
        }
        answered = true
    }
    precondition(answered)
}
let bridges = registrar.delegates.compactMap { $0 as? PalladinAutoFillBridgePlugin }
precondition(bridges.count == 2 && bridges[0] === bridges[1], "channels must share one source owner")
print("PASS: both bootstrap channels dispatch to the same native source owner")
