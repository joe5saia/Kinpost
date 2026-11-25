import CloudKit
import KinpostCore
import SwiftUI

@MainActor @Observable final class Session {
  static let shared = Session()
  let desk: Desk, sample: SampleExchange?, cloud: CloudExchange?
  let contacts = AddressBook()
  var incoming: URL?
  var identityToken = UUID()
  private init() {
    #if targetEnvironment(simulator)
      if !ProcessInfo.processInfo.arguments.contains("-iCloud") {
        do {
          let sample = try SampleExchange(
            file: URL.applicationSupportDirectory.appending(path: "sample-book.json"))
          self.sample = sample
          self.cloud = nil
          self.desk = Desk(sample)
          return
        } catch {
          // Preserve a damaged sample on disk; make the failure visible without touching iCloud.
          let fallback = try! SampleExchange()
          self.sample = fallback
          self.cloud = nil
          self.desk = Desk(fallback)
          self.desk.problem =
            "The saved sample could not be opened. Changes in this session are temporary."
          return
        }
      }
    #endif
    let cloud = CloudExchange()
    self.cloud = cloud
    self.sample = nil
    self.desk = Desk(cloud)
  }
  @discardableResult func refresh() async -> Bool {
    guard await desk.refresh() else { return false }
    do {
      try contacts.reconcile(desk.book)
      return true
    } catch {
      desk.problem = error.localizedDescription
      return false
    }
  }
  func changePerson(_ key: String) async {
    guard let sample, !desk.busy else { return }
    do {
      try sample.switchTo(key)
      desk.clearSession()
      _ = await refresh()
      identityToken = UUID()
    } catch { desk.problem = error.localizedDescription }
  }
  func accept(_ meta: CKShare.Metadata) async {
    guard let cloud else {
      desk.problem =
        "This simulator is using sample people. Open iCloud invitations in a signed iCloud build."
      return
    }
    do {
      try await cloud.accept(meta)
      _ = await refresh()
    } catch { desk.problem = error.localizedDescription }
  }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions
  ) {
    if let share = options.cloudKitShareMetadata { Task { await Session.shared.accept(share) } }
  }
  func windowScene(
    _ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
  ) { Task { await Session.shared.accept(metadata) } }
}
final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ app: UIApplication, configurationForConnecting session: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let config = UISceneConfiguration(name: nil, sessionRole: session.role)
    config.delegateClass = SceneDelegate.self
    return config
  }
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if Session.shared.cloud != nil { application.registerForRemoteNotifications() }
    return true
  }
  func application(
    _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    guard
      CKNotification(fromRemoteNotificationDictionary: userInfo)?.containerIdentifier
        == CloudExchange.containerID
    else {
      completion(.noData)
      return
    }
    Task { completion(await Session.shared.refresh() ? .newData : .failed) }
  }
}
@main struct KinpostApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @Environment(\.scenePhase) private var phase
  @State private var session = Session.shared
  var body: some Scene {
    WindowGroup {
      RootView(session: session).id(session.identityToken).tint(.postBlue)
        .onOpenURL { url in
          if session.sample != nil && url.scheme == "kinpost" { session.incoming = url }
        }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
          guard session.cloud != nil else { return }
          session.desk.clearSession()
          session.identityToken = UUID()
          Task { await session.refresh() }
        }
        .onChange(of: phase, initial: true) { _, phase in
          if phase == .active { Task { await session.refresh() } }
        }
    }
  }
}
