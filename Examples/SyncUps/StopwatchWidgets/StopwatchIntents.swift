/*
 HOW:
   These intents are used by widget buttons and Live Activity controls.
   They execute when users tap buttons in the widget/Live Activity UI.

 WHO:
   Agent (Cursor), User
   (Context: Adding WidgetKit/Live Activity support)

 WHAT:
   App Intents for stopwatch widget and Live Activity interactivity.
   Provides:
   - ToggleStopwatchIntent: Play/pause a stopwatch
   - UnfavoriteStopwatchIntent: Remove favorite status
   - CreateFavoriteIntent: Create new favorite stopwatch
   - NavigateToStopwatchIntent: Deep link to stopwatch detail

 WHEN:
   2025-12-16
   Last Modified: 2025-12-16

 WHERE:
   StopwatchWidgets/StopwatchIntents.swift

 WHY:
   WidgetKit and Live Activities require App Intents for interactive buttons.
   These intents modify @Shared state directly, which the main app observes.
   For Live Activities, intents must conform to LiveActivityIntent.
*/

import ActivityKit
import AppIntents
import Foundation
import IdentifiedCollections
import os
import Sharing
import Tagged
import WidgetKit

private let logger = Logger(subsystem: "com.syncups.widgets", category: "LiveActivity")

// Also use print for easier debugging in Xcode console
private func debugLog(_ message: String) {
  print("[StopwatchIntent] \(message)")
  // Use .public privacy to see values in Console.app
  logger.debug("\(message, privacy: .public)")
}

// MARK: - Toggle Stopwatch Intent

/// Toggles a stopwatch between running and paused states.
///
/// Used by:
/// - Widget play/pause buttons
/// - Live Activity play/pause buttons
///
/// This intent modifies @Shared state, which both the widget and
/// main app observe. The widget timeline is invalidated after execution.
struct ToggleStopwatchIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Toggle Stopwatch"
  static var description = IntentDescription("Play or pause a stopwatch")
  
  /// The ID of the stopwatch to toggle.
  @Parameter(title: "Stopwatch ID")
  var stopwatchID: String
  
  init() {
    self.stopwatchID = ""
  }
  
  init(stopwatchID: String) {
    self.stopwatchID = stopwatchID
  }
  
  func perform() async throws -> some IntentResult {
    debugLog("🎯 ToggleStopwatchIntent.perform() - ID: \(self.stopwatchID)")
    
    guard let uuid = UUID(uuidString: stopwatchID) else {
      debugLog("❌ Invalid stopwatch ID: \(self.stopwatchID)")
      throw IntentError.invalidStopwatchID
    }
    
    // Access @Shared state via App Group and toggle
    @Shared(.stopwatches) var stopwatches
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID
    
    debugLog("   Stopwatches count: \(stopwatches.count)")
    debugLog("   Favorite ID: \(favoriteStopwatchID?.rawValue.uuidString ?? "nil")")
    
    let id = StopwatchItem.ID(uuid)
    let now = Date()
    
    // Toggle the stopwatch and capture the new state
    var updatedStopwatch: StopwatchItem?
    $stopwatches.withLock { items in
      let beforeState = items[id: id]
      debugLog("   Before toggle - isRunning: \(beforeState?.isRunning ?? false)")
      
      items[id: id]?.toggle(now: now)
      updatedStopwatch = items[id: id]
      
      debugLog("   After toggle - isRunning: \(updatedStopwatch?.isRunning ?? false)")
    }
    
    // Update Live Activity directly with the captured state
    if let stopwatch = updatedStopwatch {
      debugLog("✅ Captured updated stopwatch, updating Live Activity...")
      
      // Find playing non-favorite
      let playingNonFavorite = stopwatches.first { sw in
        sw.isRunning && sw.id != favoriteStopwatchID
      }
      
      await updateLiveActivityForStopwatch(
        stopwatch,
        hasFavorite: favoriteStopwatchID != nil,
        playingNonFavorite: playingNonFavorite
      )
    } else {
      debugLog("⚠️ No stopwatch found with ID: \(uuid.uuidString)")
    }
    
    // Invalidate widget timeline to refresh UI
    WidgetCenter.shared.reloadTimelines(ofKind: "StopwatchWidget")
    
    debugLog("✅ ToggleStopwatchIntent completed")
    return .result()
  }
}

// MARK: - Unfavorite Stopwatch Intent

/// Removes favorite status from a stopwatch.
///
/// Used by:
/// - Widget unfavorite buttons
/// - Live Activity unfavorite buttons
///
/// This ends the Live Activity since there's no longer a favorite.
struct UnfavoriteStopwatchIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Unfavorite Stopwatch"
  static var description = IntentDescription("Remove favorite status from a stopwatch")
  
  @Parameter(title: "Stopwatch ID")
  var stopwatchID: String
  
  init() {
    self.stopwatchID = ""
  }
  
  init(stopwatchID: String) {
    self.stopwatchID = stopwatchID
  }
  
  func perform() async throws -> some IntentResult {
    // Clear favoriteStopwatchID in @Shared state
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID
    
    $favoriteStopwatchID.withLock { $0 = nil }
    
    // End all Live Activities since there's no longer a favorite
    await endAllStopwatchActivities()
    
    // Clear the stored activity ID
    @Shared(.activeLiveActivityID) var activeLiveActivityID
    $activeLiveActivityID.withLock { $0 = nil }
    
    // Invalidate widget timeline
    WidgetCenter.shared.reloadTimelines(ofKind: "StopwatchWidget")
    
    return .result()
  }
}

// MARK: - Create Favorite Intent

/// Creates a new stopwatch and sets it as the favorite.
///
/// Used by:
/// - Widget "Start Recording" buttons when no favorite exists
///
/// This starts a new Live Activity for the created stopwatch.
struct CreateFavoriteIntent: AppIntent {
  static var title: LocalizedStringResource = "Create Favorite Stopwatch"
  static var description = IntentDescription("Create a new stopwatch and set it as favorite")
  
  /// Opens the app after creating the stopwatch.
  static var openAppWhenRun: Bool = true
  
  func perform() async throws -> some IntentResult & OpensIntent {
    // Create new stopwatch
    @Shared(.stopwatches) var stopwatches
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID
    
    let newID = StopwatchItem.ID(UUID())
    let now = Date()
    
    let newStopwatch = StopwatchItem(
      id: newID,
      title: "Stopwatch \(stopwatches.count + 1)",
      isRunning: true,
      lastStartTime: now
    )
    
    $stopwatches.withLock { _ = $0.append(newStopwatch) }
    $favoriteStopwatchID.withLock { $0 = newID }
    
    // Invalidate widget timeline
    WidgetCenter.shared.reloadTimelines(ofKind: "StopwatchWidget")
    
    // Open the app and navigate to the new stopwatch
    let url = URL(string: "syncups://stopwatches/\(newID.rawValue.uuidString)")!
    return .result(opensIntent: OpenURLIntent(url))
  }
}

// MARK: - Navigate to Stopwatch Intent

/// Deep links to a specific stopwatch's detail view.
///
/// Used by:
/// - Widget "Open" buttons
/// - Live Activity tap handlers
/// - Tapping the widget background
struct NavigateToStopwatchIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Stopwatch"
  static var description = IntentDescription("Open a stopwatch in the app")
  
  /// Opens the app to show the stopwatch.
  static var openAppWhenRun: Bool = true
  
  @Parameter(title: "Stopwatch ID")
  var stopwatchID: String
  
  init() {
    self.stopwatchID = ""
  }
  
  init(stopwatchID: String) {
    self.stopwatchID = stopwatchID
  }
  
  func perform() async throws -> some IntentResult & OpensIntent {
    guard let uuid = UUID(uuidString: stopwatchID) else {
      throw IntentError.invalidStopwatchID
    }
    
    // Generate the deep link URL: syncups://stopwatches/{uuid}
    let url = URL(string: "syncups://stopwatches/\(uuid.uuidString)")!
    return .result(opensIntent: OpenURLIntent(url))
  }
}

// MARK: - Intent Errors

/// Errors that can occur during intent execution.
enum IntentError: Error, LocalizedError {
  case invalidStopwatchID
  case stopwatchNotFound
  case sharedStateUnavailable
  
  var errorDescription: String? {
    switch self {
    case .invalidStopwatchID:
      return "Invalid stopwatch ID format"
    case .stopwatchNotFound:
      return "Stopwatch not found"
    case .sharedStateUnavailable:
      return "Unable to access shared state"
    }
  }
}

// MARK: - App Intent Shortcuts

/// Provides Siri shortcuts for stopwatch actions.
struct StopwatchShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: CreateFavoriteIntent(),
      phrases: [
        "Start recording in \(.applicationName)",
        "New stopwatch in \(.applicationName)",
        "Start timer in \(.applicationName)"
      ],
      shortTitle: "Start Recording",
      systemImageName: "record.circle"
    )
  }
}

// MARK: - Live Activity Helpers

/// Updates the Live Activity for a specific stopwatch with the given state.
/// This avoids re-reading from @Shared which might have stale data.
///
/// NOTE: Widget extensions run in a separate process from the main app.
/// Activity<T>.activities only returns activities for the current process.
/// We must use push notifications or the main app to update activities.
/// For now, we use a workaround: request a new activity with updated content
/// or rely on the main app to handle updates.
private func updateLiveActivityForStopwatch(
  _ stopwatch: StopwatchItem,
  hasFavorite: Bool,
  playingNonFavorite: StopwatchItem?
) async {
  debugLog("🔍 updateLiveActivityForStopwatch called")
  debugLog("   Stopwatch ID: \(stopwatch.id.rawValue.uuidString)")
  debugLog("   isRunning: \(stopwatch.isRunning)")
  debugLog("   elapsed: \(stopwatch.elapsedMilliseconds)")
  debugLog("   lastStartTime: \(String(describing: stopwatch.lastStartTime))")
  
  // Get the activity ID from shared state
  @Shared(.activeLiveActivityID) var activeLiveActivityID
  
  debugLog("   activeLiveActivityID from @Shared: \(activeLiveActivityID ?? "nil")")
  
  // Check local activities (this will be empty in widget extension process)
  let localActivities = Activity<StopwatchAttributes>.activities
  debugLog("   Local activities count: \(localActivities.count)")
  
  // If we have local activities (running in main app), update them
  if let activity = localActivities.first(where: { $0.attributes.stopwatchID == stopwatch.id }) {
    debugLog("✅ Found local activity: \(activity.id)")
    
    let contentState = StopwatchAttributes.ContentState(
      from: stopwatch,
      hasFavorite: hasFavorite,
      playingNonFavorite: playingNonFavorite
    )
    
    debugLog("   New ContentState - isRunning: \(contentState.isRunning), elapsed: \(contentState.elapsedMilliseconds)")
    
    let content = ActivityContent(state: contentState, staleDate: nil)
    await activity.update(content)
    
    debugLog("✅ Activity.update() called successfully")
    return
  }
  
  // Widget extension can't directly update activities created by main app.
  // The @Shared state change will be picked up by the main app, which should
  // observe the change and update the Live Activity.
  debugLog("ℹ️ No local activity found - state change saved to @Shared")
  debugLog("   Main app should observe @Shared changes and update Live Activity")
}

/// Ends all Live Activities for stopwatches.
/// Called when unfavoriting.
private func endAllStopwatchActivities() async {
  let activities = Activity<StopwatchAttributes>.activities
  for activity in activities {
    await activity.end(nil, dismissalPolicy: .immediate)
  }
}


