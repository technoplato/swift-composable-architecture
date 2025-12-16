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

@preconcurrency import ActivityKit
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
  ) async -> AsyncStream<ActivityState> = { _ in .finished }
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
        print("[ActivityKitClient] 🚀 start() called")
        print("   attributes.stopwatchID: \(attributes.stopwatchID)")
        print("   attributes.title: \(attributes.title)")
        print("   contentState.isRunning: \(contentState.isRunning)")
        print("   contentState.elapsedMilliseconds: \(contentState.elapsedMilliseconds)")
        print("   areActivitiesEnabled: \(ActivityAuthorizationInfo().areActivitiesEnabled)")
        
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
          print("[ActivityKitClient] ❌ Activities disabled!")
          throw ActivityKitClientError.activitiesDisabled
        }
        
        let content = ActivityContent(
          state: contentState,
          staleDate: nil,
          relevanceScore: 100  // High priority for active recording
        )
        
        let activityID = try await activitiesActor.start(attributes: attributes, content: content)
        print("[ActivityKitClient] ✅ Activity started with ID: \(activityID)")
        return activityID
      },
      
      update: { activityID, contentState in
        print("[ActivityKitClient] 📝 update() called")
        print("   activityID: \(activityID)")
        print("   contentState.isRunning: \(contentState.isRunning)")
        print("   contentState.elapsedMilliseconds: \(contentState.elapsedMilliseconds)")
        print("   contentState.lastStartTime: \(String(describing: contentState.lastStartTime))")
        
        let content = ActivityContent(
          state: contentState,
          staleDate: nil
        )
        
        let found = await activitiesActor.update(activityID, with: content)
        if !found {
          print("[ActivityKitClient] ❌ Activity not found for update!")
          throw ActivityKitClientError.activityNotFound(activityID)
        }
        print("[ActivityKitClient] ✅ Activity updated successfully")
      },
      
      end: { activityID, finalContentState, dismissalPolicy in
        print("[ActivityKitClient] 🛑 end() called")
        print("   activityID: \(activityID)")
        
        let finalContent = finalContentState.map { state in
          ActivityContent(state: state, staleDate: nil)
        }
        
        let found = await activitiesActor.end(activityID, content: finalContent, dismissalPolicy: dismissalPolicy)
        if !found {
          print("[ActivityKitClient] ❌ Activity not found for end!")
          throw ActivityKitClientError.activityNotFound(activityID)
        }
        print("[ActivityKitClient] ✅ Activity ended successfully")
      },
      
      areActivitiesEnabled: {
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        print("[ActivityKitClient] areActivitiesEnabled: \(enabled)")
        return enabled
      },
      
      activeActivityIDs: {
        let ids = Activity<StopwatchAttributes>.activities.map(\.id)
        print("[ActivityKitClient] activeActivityIDs: \(ids)")
        return ids
      },
      
      observeActivityState: { activityID in
        print("[ActivityKitClient] observeActivityState() called for: \(activityID)")
        return await activitiesActor.observeStateUpdates(activityID)
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
/// Actor to manage Live Activity lifecycle.
///
/// All Activity operations happen within this actor to avoid sendability issues.
/// Activity<T> is not Sendable, so we keep all references isolated here.
private actor ActivityTracker {
  private var activities: [String: Activity<StopwatchAttributes>] = [:]
  
  /// Starts a new activity and tracks it. Returns the activity ID.
  func start(
    attributes: StopwatchAttributes,
    content: ActivityContent<StopwatchAttributes.ContentState>
  ) throws -> String {
    let activity = try Activity.request(
      attributes: attributes,
      content: content,
      pushType: nil  // Local updates only for now
    )
    activities[activity.id] = activity
    return activity.id
  }
  
  /// Updates an activity's content state. Returns true if found and updated.
  func update(_ id: String, with content: ActivityContent<StopwatchAttributes.ContentState>) async -> Bool {
    print("[ActivityTracker] update() - looking for activity: \(id)")
    print("   tracked activities: \(activities.keys.joined(separator: ", "))")
    print("   system activities: \(Activity<StopwatchAttributes>.activities.map(\.id).joined(separator: ", "))")
    
    guard let activity = findActivity(for: id) else {
      print("[ActivityTracker] ❌ Activity not found!")
      return false
    }
    
    print("[ActivityTracker] ✅ Found activity, calling activity.update()")
    print("   activity.id: \(activity.id)")
    print("   activity.activityState: \(activity.activityState)")
    
    await activity.update(content)
    
    print("[ActivityTracker] ✅ activity.update() completed")
    return true
  }
  
  /// Ends an activity. Returns true if found and ended.
  func end(_ id: String, content: ActivityContent<StopwatchAttributes.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy) async -> Bool {
    guard let activity = findActivity(for: id) else { return false }
    await activity.end(content, dismissalPolicy: dismissalPolicy)
    activities.removeValue(forKey: id)
    return true
  }
  
  /// Observes state updates for an activity.
  /// Returns an AsyncStream that yields ActivityState values.
  func observeStateUpdates(_ id: String) -> AsyncStream<ActivityState> {
    guard let activity = findActivity(for: id) else {
      return .finished
    }
    
    // Capture activity ID to look up fresh each iteration
    let activityID = id
    
    return AsyncStream { [weak self] continuation in
      let task = Task { [weak self] in
        // Re-fetch activity within the task to avoid sendability issues
        guard let tracker = self else {
          continuation.finish()
          return
        }
        
        // We need to observe from within the actor
        await tracker.observeActivityStateInternal(activityID, continuation: continuation)
      }
      
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
  
  /// Internal method to observe activity state, called from within actor isolation.
  private func observeActivityStateInternal(_ id: String, continuation: AsyncStream<ActivityState>.Continuation) async {
    guard let activity = findActivity(for: id) else {
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
  
  func exists(_ id: String) -> Bool {
    findActivity(for: id) != nil
  }
  
  func remove(_ id: String) {
    activities.removeValue(forKey: id)
  }
  
  private func findActivity(for id: String) -> Activity<StopwatchAttributes>? {
    // Check tracked activities first
    if let tracked = activities[id] {
      return tracked
    }
    // Also check system's activities in case we lost track
    return Activity<StopwatchAttributes>.activities.first { $0.id == id }
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


