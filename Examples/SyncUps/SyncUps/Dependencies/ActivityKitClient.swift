/*
 HOW:
   Inject via TCA's dependency system:
   ```swift
   @Dependency(\.activityKit) var activityKit
   ```
   
   [Inputs]
   - StopwatchAttributes: Static activity data
   - StopwatchAttributes.ContentState: Dynamic activity data
   
   [Outputs]
   - Activity ID (String) for tracking/updating
   - AsyncStream for activity state changes
   
   [Side Effects]
   - Creates/updates/ends Live Activities on device
   - System UI updates (Lock Screen, Dynamic Island)

 WHO:
   Agent (Cursor), User
   (Context: Adding WidgetKit/Live Activity support)

 WHAT:
   TCA dependency client for ActivityKit interactions.
   Provides a testable interface for starting, updating, and ending
   Live Activities for stopwatches.
   
   Follows the isowords pattern for TCA dependencies:
   - Interface defined with @DependencyClient
   - Live implementation using real ActivityKit
   - Test implementation (unimplemented by default)
   - Preview implementation with mock behavior

 WHEN:
   2025-12-16
   Last Modified: 2025-12-16
   [Change Log:
     - 2025-12-16: Initial creation following isowords patterns
   ]

 WHERE:
   SyncUps/Dependencies/ActivityKitClient.swift

 WHY:
   Wrapping ActivityKit in a TCA dependency provides:
   1. Testability - can verify correct calls without real activities
   2. Preview support - mock activities in SwiftUI previews
   3. Consistent patterns - matches other TCA dependencies
   4. Compile-time safety - @DependencyClient generates unimplemented stubs
*/

import ActivityKit
import ComposableArchitecture
import Foundation

// MARK: - ActivityKitClient

/// A TCA dependency client for managing stopwatch Live Activities.
///
/// This client wraps ActivityKit's APIs to provide a testable, mockable
/// interface for Live Activity management.
///
/// ## Usage in Reducers
///
/// ```swift
/// @Reducer
/// struct AppFeature {
///   @Dependency(\.activityKit) var activityKit
///
///   var body: some ReducerOf<Self> {
///     Reduce { state, action in
///       switch action {
///       case .startRecording:
///         return .run { [stopwatch = state.favoriteStopwatch] send in
///           let id = try await activityKit.start(
///             StopwatchAttributes(from: stopwatch),
///             .init(from: stopwatch, hasFavorite: true, playingNonFavorite: nil)
///           )
///           await send(.activityStarted(id))
///         }
///       }
///     }
///   }
/// }
/// ```
///
/// ## Testing
///
/// ```swift
/// let store = TestStore(initialState: AppFeature.State()) {
///   AppFeature()
/// } withDependencies: {
///   $0.activityKit.start = { attrs, state in "test-activity-id" }
/// }
/// ```
@DependencyClient
struct ActivityKitClient: Sendable {
  /// Starts a new Live Activity for a stopwatch.
  ///
  /// - Parameters:
  ///   - attributes: Static activity data (stopwatch ID, title)
  ///   - contentState: Initial dynamic state (elapsed time, running state)
  /// - Returns: The activity's unique identifier for future updates
  /// - Throws: If Live Activities are disabled or the request fails
  ///
  /// ## System Behavior
  ///
  /// - Activity appears on Lock Screen and Dynamic Island
  /// - System may decline if too many activities are active
  /// - Returns immediately; UI appears asynchronously
  var start: @Sendable (
    _ attributes: StopwatchAttributes,
    _ contentState: StopwatchAttributes.ContentState
  ) async throws -> String
  
  /// Updates an existing Live Activity with new state.
  ///
  /// - Parameters:
  ///   - activityID: The activity to update (from `start`)
  ///   - contentState: New dynamic state to display
  /// - Throws: If the activity doesn't exist or update fails
  ///
  /// ## Rate Limiting
  ///
  /// ActivityKit rate-limits updates to preserve battery:
  /// - ~10-15 updates/hour when backgrounded
  /// - More frequent when foregrounded
  ///
  /// Updates are coalesced - only the latest state matters.
  var update: @Sendable (
    _ activityID: String,
    _ contentState: StopwatchAttributes.ContentState
  ) async throws -> Void
  
  /// Ends a Live Activity.
  ///
  /// - Parameters:
  ///   - activityID: The activity to end
  ///   - finalContentState: Optional final state to show (e.g., "Recording ended")
  ///   - dismissalPolicy: How long the activity remains visible after ending
  /// - Throws: If the activity doesn't exist
  ///
  /// ## Dismissal Policies
  ///
  /// - `.immediate`: Remove from Lock Screen immediately
  /// - `.default`: Stay visible for up to 4 hours
  /// - `.after(Date)`: Stay until specified date
  var end: @Sendable (
    _ activityID: String,
    _ finalContentState: StopwatchAttributes.ContentState?,
    _ dismissalPolicy: ActivityUIDismissalPolicy
  ) async throws -> Void
  
  /// Checks if Live Activities are enabled for this app.
  ///
  /// Users can disable Live Activities in Settings.
  /// Check this before attempting to start an activity.
  ///
  /// - Returns: `true` if activities can be started
  var areActivitiesEnabled: @Sendable () -> Bool = { false }
  
  /// Returns the IDs of all currently active Live Activities.
  ///
  /// Use to:
  /// - Check if an activity already exists for a stopwatch
  /// - Clean up stale activities on app launch
  ///
  /// - Returns: Array of activity IDs
  var activeActivityIDs: @Sendable () -> [String] = { [] }
  
  /// Observes state changes for a specific activity.
  ///
  /// The stream emits when:
  /// - Activity is dismissed by user
  /// - Activity ends due to dismissal policy
  /// - System terminates the activity
  ///
  /// - Parameter activityID: The activity to observe
  /// - Returns: AsyncStream of activity states
  var observeActivityState: @Sendable (
    _ activityID: String
  ) -> AsyncStream<ActivityState> = { _ in .finished }
}

// MARK: - DependencyKey Conformance

extension ActivityKitClient: DependencyKey {
  /// Live implementation using real ActivityKit APIs.
  ///
  /// Only available on iOS 16.1+ where ActivityKit exists.
  static let liveValue: Self = {
    // Track activities by ID for updates/ending
    let activitiesActor = ActivityTracker()
    
    return Self(
      start: { attributes, contentState in
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
          throw ActivityKitClientError.activitiesDisabled
        }
        
        let content = ActivityContent(
          state: contentState,
          staleDate: nil,
          relevanceScore: 100  // High priority for active recording
        )
        
        let activity = try Activity.request(
          attributes: attributes,
          content: content,
          pushType: nil  // Local updates only for now
        )
        
        await activitiesActor.track(activity)
        return activity.id
      },
      
      update: { activityID, contentState in
        guard let activity = await activitiesActor.activity(for: activityID) else {
          throw ActivityKitClientError.activityNotFound(activityID)
        }
        
        let content = ActivityContent(
          state: contentState,
          staleDate: nil
        )
        
        await activity.update(content)
      },
      
      end: { activityID, finalContentState, dismissalPolicy in
        guard let activity = await activitiesActor.activity(for: activityID) else {
          throw ActivityKitClientError.activityNotFound(activityID)
        }
        
        let finalContent = finalContentState.map { state in
          ActivityContent(state: state, staleDate: nil)
        }
        
        await activity.end(finalContent, dismissalPolicy: dismissalPolicy)
        await activitiesActor.remove(activityID)
      },
      
      areActivitiesEnabled: {
        ActivityAuthorizationInfo().areActivitiesEnabled
      },
      
      activeActivityIDs: {
        Activity<StopwatchAttributes>.activities.map(\.id)
      },
      
      observeActivityState: { activityID in
        AsyncStream { continuation in
          Task {
            guard let activity = await activitiesActor.activity(for: activityID) else {
              continuation.finish()
              return
            }
            
            for await state in activity.activityStateUpdates {
              continuation.yield(state)
              if state == .dismissed || state == .ended {
                continuation.finish()
                return
              }
            }
            continuation.finish()
          }
        }
      }
    )
  }()
  
  /// Test implementation with unimplemented stubs.
  ///
  /// Using `@DependencyClient` auto-generates this with XCTFail calls.
  static let testValue = Self()
  
  /// Preview implementation with mock behavior.
  ///
  /// Returns fake activity IDs and succeeds without side effects.
  static let previewValue: Self = Self(
    start: { _, _ in "preview-activity-\(UUID().uuidString)" },
    update: { _, _ in },
    end: { _, _, _ in },
    areActivitiesEnabled: { true },
    activeActivityIDs: { [] },
    observeActivityState: { _ in .finished }
  )
}

// MARK: - DependencyValues Extension

extension DependencyValues {
  /// Access the ActivityKit client dependency.
  ///
  /// ```swift
  /// @Dependency(\.activityKit) var activityKit
  /// ```
  var activityKit: ActivityKitClient {
    get { self[ActivityKitClient.self] }
    set { self[ActivityKitClient.self] = newValue }
  }
}

// MARK: - Activity Tracker Actor

/// Thread-safe storage for active Activity instances.
///
/// ActivityKit requires holding references to Activity objects
/// for updates and ending. This actor provides safe concurrent access.
private actor ActivityTracker {
  private var activities: [String: Activity<StopwatchAttributes>] = [:]
  
  func track(_ activity: Activity<StopwatchAttributes>) {
    activities[activity.id] = activity
  }
  
  func activity(for id: String) -> Activity<StopwatchAttributes>? {
    // Also check system's activities in case we lost track
    if let tracked = activities[id] {
      return tracked
    }
    return Activity<StopwatchAttributes>.activities.first { $0.id == id }
  }
  
  func remove(_ id: String) {
    activities.removeValue(forKey: id)
  }
}

// MARK: - Errors

/// Errors that can occur when using ActivityKitClient.
enum ActivityKitClientError: LocalizedError {
  /// Live Activities are disabled by the user in Settings.
  case activitiesDisabled
  
  /// The specified activity ID was not found.
  case activityNotFound(String)
  
  var errorDescription: String? {
    switch self {
    case .activitiesDisabled:
      return "Live Activities are disabled. Enable them in Settings > \(Bundle.main.displayName ?? "App") > Live Activities."
    case .activityNotFound(let id):
      return "Activity '\(id)' not found. It may have been dismissed or ended."
    }
  }
}

// MARK: - Bundle Extension

private extension Bundle {
  var displayName: String? {
    object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? object(forInfoDictionaryKey: "CFBundleName") as? String
  }
}

