import Flutter
import Foundation

final class EntryShareNativeIngress {
  static let shared = EntryShareNativeIngress()
  private let mailbox = EntryShareMailbox()
  private var channel: FlutterMethodChannel?
  private var attachment: UUID?
  private var expiry: DispatchWorkItem?
  private let origin: String
  private(set) var generation: Int64 = 0

  private init() {
    let host = Bundle.main.object(forInfoDictionaryKey: "PalladinSharingHost") as? String ?? ""
    origin = "https://" + host
  }

  @discardableResult
  func consume(_ activity: NSUserActivity) -> Bool {
    guard EntryShareActivityPrivacy.intercepts(activity) else { return false }
    let candidate = activity.activityType == NSUserActivityTypeBrowsingWeb
      ? activity.webpageURL?.absoluteString : nil
    EntryShareActivityPrivacy.scrub(activity)
    offer(candidate)
    return true
  }

  func reject() { offer(nil) }

  func disconnect(expectedGeneration: Int64) {
    precondition(Thread.isMainThread)
    guard let next = mailbox.clear(expectedGeneration: expectedGeneration) else { return }
    expiry?.cancel()
    expiry = nil
    publish(next)
  }

  private func offer(_ candidate: String?) {
    precondition(Thread.isMainThread)
    expiry?.cancel()
    let generation = mailbox.offer(candidate, expectedOrigin: origin)
    publish(generation)
    let expiry = DispatchWorkItem { [weak self] in
      self?.disconnect(expectedGeneration: generation)
    }
    self.expiry = expiry
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .milliseconds(Int(EntryShareMailbox.maximumAgeMilliseconds)),
      execute: expiry
    )
  }

  private func publish(_ generation: Int64) {
    self.generation = generation
    channel?.invokeMethod("pending", arguments: generation)
  }

  func attach(_ channel: FlutterMethodChannel) -> UUID {
    precondition(Thread.isMainThread)
    self.channel = channel
    let owner = UUID()
    attachment = owner
    return owner
  }

  func take(owner: UUID) -> [String: Any]? {
    precondition(Thread.isMainThread)
    guard attachment == owner else { return nil }
    expiry?.cancel()
    expiry = nil
    return mailbox.take()
  }

  func detach(owner: UUID) {
    precondition(Thread.isMainThread)
    guard attachment == owner else { return }
    attachment = nil
    channel = nil
  }
}

final class EntryShareIngressPlugin: NSObject, FlutterPlugin {
  private let owner: UUID

  private init(channel: FlutterMethodChannel) {
    owner = EntryShareNativeIngress.shared.attach(channel)
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "io.palladin.mobile/entry-sharing", binaryMessenger: registrar.messenger()
    )
    let plugin = EntryShareIngressPlugin(channel: channel)
    registrar.addMethodCallDelegate(plugin, channel: channel)
    registrar.publish(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "takePending" {
      result(EntryShareNativeIngress.shared.take(owner: owner))
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    EntryShareNativeIngress.shared.detach(owner: owner)
  }
}
