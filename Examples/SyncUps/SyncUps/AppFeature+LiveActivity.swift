/*
 HOW:
   This extension adds Live Activity management to AppFeature.
   Import ActivityKit and add the activityKit dependency to use.
   
   [Inputs]
   - Favorite stopwatch changes
   - Stopwatch state changes (running, elapsed time)
   
   [Outputs]
   - Live Activity started/updated/ended
   
   [Side Effects]
   - System UI updates (Lock Screen, Dynamic Island)

 WHO:
   Agent (Cursor), User
   (Context: Adding WidgetKit/Live Activity support)

 WHAT:
   Extension to AppFeature that manages Live Activity lifecycle:
   - Starts activity when favorite is created
   - Updates activity when favorite state changes
   - Ends activity when favorite is deleted/unfavorited

 WHEN:
   2025-12-16
   Last Modified: 2025-12-16

 WHERE:
   SyncUps/AppFeature+LiveActivity.swift

 WHY:
   Separating Live Activity logic into an extension keeps the main
   AppFeature focused on core navigation and state management.
   This makes the code more modular and easier to test.
*/

import ActivityKit
import ComposableArchitecture
import Foundation

// MARK: - Live Activity Actions

/// Actions related to Live Activity management.
///
/// This enum is referenced by `AppFeature.Action.liveActivity(_:)` which is defined
/// in the main `AppFeature.swift` file.
enum LiveActivity: Equatable {
  /// Check and restore Live Activity on app launch.
  /// If there's a favorite but no active Live Activity, start one.
  case checkAndRestoreOnLaunch
  
  /// Start observing @Shared changes from widget extension.
  /// This should be called once when the app starts.
  case startObservingSharedChanges
  
  /// Called when @Shared stopwatches changes (from widget extension or elsewhere).
  case sharedStopwatchesChanged
  
  /// A Live Activity was successfully started.
  case activityStarted(id: String)
  
  /// A Live Activity was successfully updated.
  case activityUpdated(id: String)
  
  /// A Live Activity was ended.
  case activityEnded(id: String)
  
  /// An error occurred with Live Activity management.
  case activityError(String)
  
  /// Deep link received from widget/Live Activity.
  case deepLinkReceived(URL)
}

// MARK: - Live Activity State

extension AppFeature.State {
  /// Returns the playing non-favorite stopwatch, if any.
  ///
  /// Note: `activeLiveActivityID` is defined in the main `AppFeature.State` struct
  /// because Swift does not allow stored properties (including `@Shared` property wrappers)
  /// in extensions.
  var playingNonFavorite: StopwatchItem? {
    stopwatches.first { stopwatch in
      stopwatch.isRunning && stopwatch.id != favoriteStopwatchID
    }
  }
}

// MARK: - Live Activity Reducer

/// A reducer that handles Live Activity lifecycle management.
///
/// This reducer should be composed with AppFeature to add Live Activity support.
/// It observes favorite stopwatch changes and manages the corresponding Live Activity.
///
/// ## Usage
///
/// ```swift
/// var body: some ReducerOf<Self> {
///   // ... existing reducers ...
///   
///   LiveActivityReducer()
/// }
/// ```
@Reducer
struct LiveActivityReducer {
  @Dependency(\.activityKit) var activityKit
  @Dependency(\.date.now) var now
  
  private enum CancelID {
    case sharedObservation
  }
  
  var body: some ReducerOf<AppFeature> {
    Reduce { state, action in
      switch action {
      // MARK: - Observe @Shared Changes from Widget Extension
      //
      // When the widget extension modifies @Shared(.stopwatches) via an intent,
      // the main app's @Shared state will automatically update. We need to
      // detect these changes and update the Live Activity accordingly.
      //
      // TCA's @Shared automatically triggers view updates, but we need to
      // handle Live Activity updates explicitly here.
        
      // MARK: - Check and Restore on App Launch
        
      case .liveActivity(.checkAndRestoreOnLaunch):
        // If there's a favorite but no active Live Activity, start one
        print("🚀 checkAndRestoreOnLaunch called")
        print("   favoriteStopwatchID: \(String(describing: state.favoriteStopwatchID))")
        print("   activeLiveActivityID: \(String(describing: state.activeLiveActivityID))")
        print("   stopwatches count: \(state.stopwatches.count)")
        
        // Check system activities
        let systemActivityIDs = activityKit.activeActivityIDs()
        print("   🔍 System active activities: \(systemActivityIDs)")
        print("   🔍 Activities enabled: \(activityKit.areActivitiesEnabled())")
        
        guard state.favoriteStopwatchID != nil else {
          print("   ❌ No favorite - skipping Live Activity")
          return .none
        }
        
        // Check if we already have an active Live Activity
        if state.activeLiveActivityID != nil {
          print("   📝 Activity exists, updating...")
          // Activity exists, just update it to sync state
          return updateLiveActivityEffect(state: state)
        }
        
        print("   ✅ Starting new Live Activity...")
        // No active activity but have a favorite - start one
        return startLiveActivityEffect(state: state)
        
      case .liveActivity(.startObservingSharedChanges):
        // Start a long-running effect that observes @Shared changes
        // This catches changes made by the widget extension
        print("👀 Starting to observe @Shared stopwatches changes")
        return .run { send in
          @Shared(.stopwatches) var stopwatches
          
          // Skip the first value (current state) and observe subsequent changes
          for await _ in $stopwatches.publisher.dropFirst().values {
            print("📱 @Shared stopwatches changed externally")
            await send(.liveActivity(.sharedStopwatchesChanged))
          }
        }
        .cancellable(id: CancelID.sharedObservation, cancelInFlight: true)
        
      case .liveActivity(.sharedStopwatchesChanged):
        // @Shared state changed (likely from widget extension)
        // Update Live Activity if we have one active
        print("🔄 sharedStopwatchesChanged - checking if Live Activity update needed")
        print("   activeLiveActivityID: \(String(describing: state.activeLiveActivityID))")
        print("   favoriteStopwatchID: \(String(describing: state.favoriteStopwatchID))")
        print("   stopwatches count: \(state.stopwatches.count)")
        
        // Log all stopwatches to see current state
        for sw in state.stopwatches {
          print("   - \(sw.id): isRunning=\(sw.isRunning), elapsed=\(sw.elapsedMilliseconds), lastStartTime=\(String(describing: sw.lastStartTime))")
        }
        
        // If we have an active activity but no favorite, end the activity
        // This handles the case where the widget extension cleared the favorite
        if state.activeLiveActivityID != nil && state.favoriteStopwatchID == nil {
          print("   🛑 Favorite was cleared - ending Live Activity")
          return endLiveActivityEffect(state: state)
        }
        
        guard state.activeLiveActivityID != nil,
              let favoriteID = state.favoriteStopwatchID,
              let stopwatch = state.stopwatches[id: favoriteID] else {
          print("   ❌ No active activity or favorite - skipping update")
          return .none
        }
        
        print("   ✅ Updating Live Activity with new state")
        print("   favorite stopwatch: \(stopwatch.title)")
        print("   isRunning: \(stopwatch.isRunning)")
        print("   elapsed: \(stopwatch.elapsedMilliseconds)")
        print("   lastStartTime: \(String(describing: stopwatch.lastStartTime))")
        
        // Also log the ContentState we're about to send
        let contentState = StopwatchAttributes.ContentState(
          from: stopwatch,
          hasFavorite: true,
          playingNonFavorite: state.playingNonFavorite
        )
        print("   ContentState.isRunning: \(contentState.isRunning)")
        print("   ContentState.lastStartTime: \(String(describing: contentState.lastStartTime))")
        print("   ContentState.elapsedMilliseconds: \(contentState.elapsedMilliseconds)")
        
        return updateLiveActivityEffect(state: state)
        
      // MARK: - Start Live Activity on Favorite Creation
        
      case .floatingControls(.delegate(.createAndNavigateToNewFavorite)):
        // The favorite was just created - start a Live Activity
        return startLiveActivityEffect(state: state)
        
      case let .stopwatchList(.favoriteTapped(id)):
        // Check if this sets or clears the favorite
        let willBeFavorite = state.favoriteStopwatchID != id
        
        if willBeFavorite {
          // Setting a new favorite - start Live Activity
          // (The state change happens in main reducer, we just react)
          return .run { [stopwatches = state.stopwatches] send in
            // Wait a tick for state to update
            try await Task.sleep(nanoseconds: 10_000_000)
            
            guard let stopwatch = stopwatches[id: id] else { return }
            
            let attributes = StopwatchAttributes(from: stopwatch)
            let contentState = StopwatchAttributes.ContentState(
              from: stopwatch,
              hasFavorite: true,
              playingNonFavorite: nil
            )
            
            do {
              let activityID = try await activityKit.start(attributes, contentState)
              await send(.liveActivity(.activityStarted(id: activityID)))
            } catch {
              await send(.liveActivity(.activityError(error.localizedDescription)))
            }
          }
        } else {
          // Clearing favorite - end Live Activity
          return endLiveActivityEffect(state: state)
        }
        
      // MARK: - End Live Activity on Favorite Deletion
        
      case let .floatingControls(.delegate(.deleteRequested(id))):
        // If deleting the favorite, end the Live Activity
        if state.favoriteStopwatchID == id {
          return endLiveActivityEffect(state: state)
        }
        return .none
        
      // MARK: - Update Live Activity on State Changes
        
      case let .stopwatchList(.toggleTapped(id)):
        // If toggling the favorite, update Live Activity
        if id == state.favoriteStopwatchID {
          return updateLiveActivityEffect(state: state)
        }
        // If toggling a non-favorite, also update (affects dual-mode display)
        if state.activeLiveActivityID != nil {
          return updateLiveActivityEffect(state: state)
        }
        return .none
        
      case let .floatingControls(.delegate(.nonFavoriteStarted(_))):
        // Non-favorite started - update Live Activity to show dual mode
        return updateLiveActivityEffect(state: state)
        
      // MARK: - Live Activity Response Actions
        
      case let .liveActivity(.activityStarted(id)):
        state.$activeLiveActivityID.withLock { $0 = id }
        return .none
        
      case .liveActivity(.activityUpdated):
        return .none
        
      case let .liveActivity(.activityEnded(id)):
        if state.activeLiveActivityID == id {
          state.$activeLiveActivityID.withLock { $0 = nil }
        }
        return .none
        
      case let .liveActivity(.activityError(message)):
        // Log error - could show alert in production
        print("Live Activity error: \(message)")
        return .none
        
      // MARK: - Deep Link Handling
        
      case let .liveActivity(.deepLinkReceived(url)):
        return handleDeepLink(url: url, state: &state)
        
      default:
        return .none
      }
    }
  }
  
  // MARK: - Private Helpers
  
  private func startLiveActivityEffect(state: AppFeature.State) -> Effect<AppFeature.Action> {
    print("🎬 startLiveActivityEffect called")
    
    guard let favoriteID = state.favoriteStopwatchID,
          let stopwatch = state.stopwatches[id: favoriteID] else {
      print("   ❌ No favorite or stopwatch not found")
      return .none
    }
    
    print("   Favorite stopwatch: \(stopwatch.title) (id: \(favoriteID))")
    
    return .run { [playingNonFavorite = state.playingNonFavorite] send in
      let attributes = StopwatchAttributes(from: stopwatch)
      let contentState = StopwatchAttributes.ContentState(
        from: stopwatch,
        hasFavorite: true,
        playingNonFavorite: playingNonFavorite
      )
      
      print("   📤 Calling activityKit.start...")
      
      do {
        let activityID = try await activityKit.start(attributes, contentState)
        print("   ✅ Activity started with ID: \(activityID)")
        await send(.liveActivity(.activityStarted(id: activityID)))
      } catch {
        print("   ❌ Activity start failed: \(error)")
        await send(.liveActivity(.activityError(error.localizedDescription)))
      }
    }
  }
  
  private func updateLiveActivityEffect(state: AppFeature.State) -> Effect<AppFeature.Action> {
    print("📝 updateLiveActivityEffect called")
    print("   activeLiveActivityID: \(String(describing: state.activeLiveActivityID))")
    print("   favoriteStopwatchID: \(String(describing: state.favoriteStopwatchID))")
    
    guard let activityID = state.activeLiveActivityID,
          let favoriteID = state.favoriteStopwatchID,
          let stopwatch = state.stopwatches[id: favoriteID] else {
      print("   ❌ Missing required state - returning .none")
      return .none
    }
    
    print("   ✅ Have all required state")
    print("   stopwatch.isRunning: \(stopwatch.isRunning)")
    print("   stopwatch.elapsedMilliseconds: \(stopwatch.elapsedMilliseconds)")
    print("   stopwatch.lastStartTime: \(String(describing: stopwatch.lastStartTime))")
    
    return .run { [playingNonFavorite = state.playingNonFavorite, debugText = stopwatch.title] send in
      let contentState = StopwatchAttributes.ContentState(
        from: stopwatch,
        hasFavorite: true,
        playingNonFavorite: playingNonFavorite,
        debugText: debugText
      )
      
      print("   📤 Calling activityKit.update...")
      print("   contentState.isRunning: \(contentState.isRunning)")
      print("   contentState.elapsedMilliseconds: \(contentState.elapsedMilliseconds)")
      print("   contentState.lastStartTime: \(String(describing: contentState.lastStartTime))")
      print("   contentState.debugText: \(String(describing: contentState.debugText))")
      
      do {
        try await activityKit.update(activityID, contentState)
        print("   ✅ activityKit.update succeeded")
        await send(.liveActivity(.activityUpdated(id: activityID)))
      } catch {
        print("   ❌ activityKit.update failed: \(error)")
        await send(.liveActivity(.activityError(error.localizedDescription)))
      }
    }
  }
  
  private func endLiveActivityEffect(state: AppFeature.State) -> Effect<AppFeature.Action> {
    guard let activityID = state.activeLiveActivityID else {
      return .none
    }
    
    return .run { send in
      do {
        try await activityKit.end(activityID, nil, .default)
        await send(.liveActivity(.activityEnded(id: activityID)))
      } catch {
        await send(.liveActivity(.activityError(error.localizedDescription)))
      }
    }
  }
  
  private func handleDeepLink(url: URL, state: inout AppFeature.State) -> Effect<AppFeature.Action> {
    guard let route = try? appRouter.match(url: url) else {
      return .none
    }
    
    switch route {
    case .stopwatchList:
      state.destination = nil
      
    case let .stopwatchDetail(id):
      guard let sharedStopwatch = Shared(state.$stopwatches[id: id]) else {
        return .none
      }
      state.destination = .stopwatchDetail(StopwatchDetail.State(stopwatch: sharedStopwatch))
      
    case .createStopwatch:
      return .send(.addStopwatchTapped)
      
    case .createFavorite:
      return .send(.floatingControls(.delegate(.createAndNavigateToNewFavorite)))
    }
    
    return .none
  }
}

// MARK: - App.swift Integration

/*
 To integrate Live Activity support, update App.swift:
 
 1. Add the LiveActivityReducer to the store:
 
 ```swift
 static let store = Store(initialState: AppFeature.State()) {
   AppFeature()
   LiveActivityReducer()  // Add this
 }
 ```
 
 2. Add deep link handling:
 
 ```swift
 var body: some Scene {
   WindowGroup {
     AppView(store: Self.store)
       .onOpenURL { url in
         Self.store.send(.liveActivity(.deepLinkReceived(url)))
       }
   }
 }
 ```
 
 3. Add the liveActivity action case to AppFeature.Action:
 
 ```swift
 enum Action {
   // ... existing cases ...
   case liveActivity(LiveActivity)
 }
 ```
*/



