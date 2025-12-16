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

import AppIntents
import Foundation
import WidgetKit

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
    // TODO: Access @Shared state via App Group and toggle
    // For now, this is a placeholder that will be implemented
    // when App Group is configured
    
    guard let uuid = UUID(uuidString: stopwatchID) else {
      throw IntentError.invalidStopwatchID
    }
    
    // Toggle the stopwatch in shared state
    // @Shared(.stopwatches) var stopwatches
    // stopwatches[id: StopwatchItem.ID(uuid)]?.toggle(now: Date())
    
    // Invalidate widget timeline to refresh UI
    WidgetCenter.shared.reloadTimelines(ofKind: "StopwatchWidget")
    
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
    // TODO: Clear favoriteStopwatchID in @Shared state
    // @Shared(.favoriteStopwatchID) var favoriteStopwatchID = nil
    
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
  
  func perform() async throws -> some IntentResult {
    // TODO: Create new stopwatch and set as favorite
    // This will trigger the main app to start a Live Activity
    
    // The app will handle this via deep link
    // For now, just open the app with a create-favorite route
    
    return .result()
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
  
  func perform() async throws -> some IntentResult {
    // The app will receive this via onOpenURL or scene delegate
    // and navigate to the stopwatch detail
    
    // Generate the deep link URL
    guard let uuid = UUID(uuidString: stopwatchID) else {
      throw IntentError.invalidStopwatchID
    }
    
    // The URL will be: syncups://stopwatches/{uuid}
    // This is handled by AppRouter in the main app
    
    return .result()
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


