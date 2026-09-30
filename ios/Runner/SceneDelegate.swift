import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var receivedSharingGeneration: Int64?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    let sharing = connectionOptions.userActivities.filter(EntryShareActivityPrivacy.intercepts)
    if sharing.count == 1, let activity = sharing.first {
      if EntryShareNativeIngress.shared.consume(activity) {
        receivedSharingGeneration = EntryShareNativeIngress.shared.generation
      }
    } else if !sharing.isEmpty {
      sharing.forEach(EntryShareActivityPrivacy.scrub)
      reject()
    }
    if connectionOptions.urlContexts.contains(where: { EntryShareLinkPolicy.intercepts($0.url) }) {
      reject()
      // UIKit's immutable URL contexts cannot be safely retained by Flutter.
      if let controller = window?.rootViewController as? FlutterViewController {
        _ = registerSceneLifeCycle(with: controller.engine)
      }
      return
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if EntryShareNativeIngress.shared.consume(userActivity) {
      receivedSharingGeneration = EntryShareNativeIngress.shared.generation
      return
    }
    super.scene(scene, continue: userActivity)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let safe = URLContexts.filter { !EntryShareLinkPolicy.intercepts($0.url) }
    if safe.count != URLContexts.count { reject() }
    if !safe.isEmpty { super.scene(scene, openURLContexts: safe) }
  }

  override func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
    guard receivedSharingGeneration == nil else { return nil }
    let activity = super.stateRestorationActivity(for: scene)
    if let activity, EntryShareActivityPrivacy.intercepts(activity) {
      EntryShareActivityPrivacy.scrub(activity)
      return nil
    }
    return activity
  }

  override func scene(_ scene: UIScene, restoreInteractionStateWith stateRestorationActivity: NSUserActivity) {
    if EntryShareActivityPrivacy.intercepts(stateRestorationActivity) {
      EntryShareActivityPrivacy.scrub(stateRestorationActivity)
      reject()
      return
    }
    super.scene(scene, restoreInteractionStateWith: stateRestorationActivity)
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    if let generation = receivedSharingGeneration {
      EntryShareNativeIngress.shared.disconnect(expectedGeneration: generation)
    }
    super.sceneDidDisconnect(scene)
  }

  private func reject() {
    EntryShareNativeIngress.shared.reject()
    receivedSharingGeneration = EntryShareNativeIngress.shared.generation
  }
}
