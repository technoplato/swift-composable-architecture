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

extension AppFeature.Action {
  /// Actions related to Live Activity management.
  enum LiveActivity: Equatable {
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
}

// MARK: - Live Activity State

extension AppFeature.State {
  /// The ID of the currently active Live Activity, if any.
  ///
  /// Stored in App Group so the widget can check if an activity exists.
  @Shared(.activeLiveActivityID) var activeLiveActivityID: String?
  
  /// Returns the playing non-favorite stopwatch, if any.
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
  
  var body: some ReducerOf<AppFeature> {
    Reduce { state, action in
      switch action {
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
    guard let favoriteID = state.favoriteStopwatchID,
          let stopwatch = state.stopwatches[id: favoriteID] else {
      return .none
    }
    
    return .run { [playingNonFavorite = state.playingNonFavorite] send in
      let attributes = StopwatchAttributes(from: stopwatch)
      let contentState = StopwatchAttributes.ContentState(
        from: stopwatch,
        hasFavorite: true,
        playingNonFavorite: playingNonFavorite
      )
      
      do {
        let activityID = try await activityKit.start(attributes, contentState)
        await send(.liveActivity(.activityStarted(id: activityID)))
      } catch {
        await send(.liveActivity(.activityError(error.localizedDescription)))
      }
    }
  }
  
  private func updateLiveActivityEffect(state: AppFeature.State) -> Effect<AppFeature.Action> {
    guard let activityID = state.activeLiveActivityID,
          let favoriteID = state.favoriteStopwatchID,
          let stopwatch = state.stopwatches[id: favoriteID] else {
      return .none
    }
    
    return .run { [playingNonFavorite = state.playingNonFavorite] send in
      let contentState = StopwatchAttributes.ContentState(
        from: stopwatch,
        hasFavorite: true,
        playingNonFavorite: playingNonFavorite
      )
      
      do {
        try await activityKit.update(activityID, contentState)
        await send(.liveActivity(.activityUpdated(id: activityID)))
      } catch {
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

// MARK: - Extension for Action Equatable

extension AppFeature.Action.LiveActivity {
  static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case let (.activityStarted(l), .activityStarted(r)): return l == r
    case let (.activityUpdated(l), .activityUpdated(r)): return l == r
    case let (.activityEnded(l), .activityEnded(r)): return l == r
    case let (.activityError(l), .activityError(r)): return l == r
    case let (.deepLinkReceived(l), .deepLinkReceived(r)): return l == r
    default: return false
    }
  }
}


