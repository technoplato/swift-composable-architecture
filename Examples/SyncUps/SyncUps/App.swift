import ComposableArchitecture
import SwiftUI

@main
struct SyncUpsApp: App {
  // NB: This is static to avoid interference with Xcode previews, which create this entry
  //     point each time they are run.
  static let store = Store(initialState: AppFeature.State()) {
    CombineReducers {
      AppFeature()
      LiveActivityReducer()
    }
    ._printSmartChanges()
  } withDependencies: {
    if ProcessInfo.processInfo.environment["UITesting"] == "true" {
      $0.defaultFileStorage = .inMemory
    }
  }
  
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      if isTesting {
        // NB: Don't run application in tests to avoid interference between the app and the test.
        EmptyView()
      } else {
        AppView(store: Self.store)
          .onAppear {
            // Check if we need to start/restore a Live Activity
            Self.store.send(.liveActivity(.checkAndRestoreOnLaunch))
            // Start observing @Shared changes from widget extension
            Self.store.send(.liveActivity(.startObservingSharedChanges))
          }
          .onOpenURL { url in
            // Handle deep links from widgets/Live Activity
            Self.store.send(.liveActivity(.deepLinkReceived(url)))
          }
          .onChange(of: scenePhase) { oldPhase, newPhase in
            print("📱 Scene phase changed: \(oldPhase) -> \(newPhase)")
            if newPhase == .active {
              // App came to foreground - sync Live Activity with @Shared state
              // This catches changes made while app was backgrounded
              print("   App became active - syncing Live Activity")
              Self.store.send(.liveActivity(.sharedStopwatchesChanged))
            }
          }
      }
    }
  }
}
