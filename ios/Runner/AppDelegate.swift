import Flutter
import PalladinAutoFillBridge
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let exportQueue = DispatchQueue(label: "io.palladin.mobile.protected-export")
  private let exportStore = ProtectedExportStore()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: sharingSafe(launchOptions))
  }

  override func application(
    _ application: UIApplication,
    willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, willFinishLaunchingWithOptions: sharingSafe(launchOptions))
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if EntryShareLinkPolicy.intercepts(url) {
      EntryShareNativeIngress.shared.reject()
      return true
    }
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if EntryShareNativeIngress.shared.consume(userActivity) { return true }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  private func sharingSafe(
    _ options: [UIApplication.LaunchOptionsKey: Any]?
  ) -> [UIApplication.LaunchOptionsKey: Any]? {
    guard var options else { return nil }
    if let url = options[.url] as? URL, EntryShareLinkPolicy.intercepts(url) {
      options.removeValue(forKey: .url)
      EntryShareNativeIngress.shared.reject()
    }
    if let activities = options[.userActivityDictionary] as? [AnyHashable: Any] {
      let sensitive = activities.values.compactMap { $0 as? NSUserActivity }
        .filter(EntryShareActivityPrivacy.intercepts)
      if !sensitive.isEmpty {
        // Launch dictionaries are not a verified Universal Link continuation.
        sensitive.forEach(EntryShareActivityPrivacy.scrub)
        options.removeValue(forKey: .userActivityDictionary)
        EntryShareNativeIngress.shared.reject()
      }
    }
    return options
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PalladinEntrySharing") {
      EntryShareIngressPlugin.register(with: registrar)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "PalladinAutoFillBridge"
    ) else { return }
    PalladinAutoFillBridgePlugin.register(with: registrar)
    guard let exportRegistrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "PalladinProtectedExport"
    ) else { return }
    let channel = FlutterMethodChannel(
      name: "io.palladin.mobile/protected-export",
      binaryMessenger: exportRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleExportCall(call, result: result)
    }
    exportQueue.async { [exportStore] in _ = try? exportStore.sweepStale() }
  }

  private func handleExportCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    exportQueue.async { [exportStore] in
      do {
        let arguments = call.arguments as? [String: Any]
        let value: Any
        switch call.method {
        case "createExport":
          guard let ext = arguments?["extension"] as? String else {
            throw ProtectedExportError.invalidArguments
          }
          value = try exportStore.create(extension: ext)
        case "appendExport":
          guard let data = (arguments?["bytes"] as? FlutterStandardTypedData)?.data,
                let id = arguments?["id"] as? String else {
            throw ProtectedExportError.invalidArguments
          }
          try exportStore.append(id: id, data: data)
          value = NSNull()
        case "finishExport":
          guard let id = arguments?["id"] as? String else {
            throw ProtectedExportError.invalidArguments
          }
          value = try exportStore.finish(id: id)
        case "abortExport":
          guard let id = arguments?["id"] as? String else {
            throw ProtectedExportError.invalidArguments
          }
          exportStore.abort(id: id)
          value = NSNull()
        case "deleteExport":
          guard let path = arguments?["path"] as? String else {
            throw ProtectedExportError.invalidArguments
          }
          value = exportStore.delete(path: path)
        case "sweepStaleExports":
          value = try exportStore.sweepStale()
        case "cleanupExports":
          value = try exportStore.cleanupAll()
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(value) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "PROTECTED_EXPORT_ERROR",
            message: "Native export operation failed",
            details: nil
          ))
        }
      }
    }
  }
}

private enum ProtectedExportError: Error {
  case invalidArguments
  case invalidExtension
  case invalidDirectory
}

private final class ProtectedExportStore {
  private let fileManager = FileManager.default
  private let maxAge: TimeInterval = 24 * 60 * 60
  private let extensionPattern = try! NSRegularExpression(pattern: "^[a-z0-9]{1,10}$")
  private var open: [String: OpenExport] = [:]
  private let maxChunkBytes = 256 * 1024
  private let maxExportBytes = 50 * 1024 * 1024

  func create(extension ext: String) throws -> String {
    guard extensionPattern.firstMatch(
      in: ext,
      range: NSRange(ext.startIndex..., in: ext)
    ) != nil else { throw ProtectedExportError.invalidExtension }
    let directory = try stagingDirectory()
    let destination = directory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(ext)
    guard fileManager.createFile(
      atPath: destination.path,
      contents: nil,
      attributes: [.protectionKey: FileProtectionType.complete]
    ) else { throw ProtectedExportError.invalidDirectory }
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var protectedDestination = destination
    try protectedDestination.setResourceValues(values)
    let id = destination.deletingPathExtension().lastPathComponent
    open[id] = OpenExport(
      url: destination,
      handle: try FileHandle(forWritingTo: destination),
      bytes: 0
    )
    return id
  }

  func append(id: String, data: Data) throws {
    guard data.count <= maxChunkBytes, var item = open[id],
          item.bytes + data.count <= maxExportBytes else {
      throw ProtectedExportError.invalidArguments
    }
    try item.handle.write(contentsOf: data)
    item.bytes += data.count
    open[id] = item
  }

  func finish(id: String) throws -> String {
    guard let item = open[id] else {
      throw ProtectedExportError.invalidArguments
    }
    try item.handle.synchronize()
    try item.handle.close()
    open.removeValue(forKey: id)
    return item.url.path
  }

  func abort(id: String) {
    guard let item = open.removeValue(forKey: id) else { return }
    try? item.handle.close()
    try? fileManager.removeItem(at: item.url)
  }

  private struct OpenExport {
    let url: URL
    let handle: FileHandle
    var bytes: Int
  }

  func delete(path: String) -> Bool {
    guard let directory = try? stagingDirectory() else { return false }
    let candidate = URL(fileURLWithPath: path).standardizedFileURL
    guard candidate.deletingLastPathComponent() == directory.standardizedFileURL,
          UUID(uuidString: candidate.deletingPathExtension().lastPathComponent) != nil else {
      return false
    }
    guard fileManager.fileExists(atPath: candidate.path) else { return true }
    do {
      try fileManager.removeItem(at: candidate)
      return true
    } catch {
      return false
    }
  }

  func sweepStale(now: Date = Date()) throws -> Int {
    let directory = try stagingDirectory()
    let files = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
    var deleted = 0
    for file in files {
      let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
      guard values?.isRegularFile == true,
            let modified = values?.contentModificationDate,
            now.timeIntervalSince(modified) >= maxAge else { continue }
      do {
        try fileManager.removeItem(at: file)
        deleted += 1
      } catch {
        // Deletion is best effort; a future startup sweep retries it.
      }
    }
    return deleted
  }

  func cleanupAll() throws -> Int {
    for item in open.values { try? item.handle.close() }
    open.removeAll()
    let directory = try stagingDirectory()
    let files = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
    var deleted = 0
    for file in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
      do {
        try fileManager.removeItem(at: file)
        deleted += 1
      } catch {
        // Best effort; the startup stale sweep retries later.
      }
    }
    return deleted
  }

  private func stagingDirectory() throws -> URL {
    guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      throw ProtectedExportError.invalidDirectory
    }
    let directory = caches.appendingPathComponent("ProtectedExports", isDirectory: true)
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete]
    )
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var protectedDirectory = directory
    try protectedDirectory.setResourceValues(values)
    return directory
  }
}
