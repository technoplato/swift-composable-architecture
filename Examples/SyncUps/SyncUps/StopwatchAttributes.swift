/*
 HOW:
   Import this file in both the main app and widget extension.
   Use StopwatchAttributes to start/update Live Activities.
   
   [Inputs]
   - StopwatchItem: The stopwatch to display in the Live Activity
   
   [Outputs]
   - ActivityAttributes conforming type for ActivityKit
   
   [Side Effects]
   - None (data model only)

 WHO:
   Agent (Cursor), User
   (Context: Adding WidgetKit/Live Activity support)

 WHAT:
   ActivityAttributes model for stopwatch Live Activities.
   Defines the static (unchanging) and dynamic (ContentState) data
   that the Live Activity displays.
   
   This file must be shared between:
   - Main app target (to start/update activities)
   - Widget extension target (to render the Live Activity UI)

 WHEN:
   2025-12-16
   Last Modified: 2025-12-16
   [Change Log:
     - 2025-12-16: Initial creation for Live Activity support
   ]

 WHERE:
   SyncUps/StopwatchAttributes.swift

 WHY:
   ActivityKit requires an ActivityAttributes type to define what data
   a Live Activity displays. The attributes are split into:
   - Static data (set at start, never changes): stopwatch ID, title
   - Dynamic data (ContentState, updated via ActivityKit): elapsed time, running state
   
   This separation allows efficient updates - only ContentState is sent
   when calling Activity.update().
*/

import ActivityKit
import Foundation
import Tagged

// MARK: - StopwatchAttributes

/// Defines the data model for stopwatch Live Activities.
///
/// Live Activities display real-time stopwatch information on the Lock Screen
/// and Dynamic Island. This type defines what data is available to the UI.
///
/// ## Static vs Dynamic Data
///
/// - **Static (attributes)**: Set when activity starts, never changes
///   - `stopwatchID`: Which stopwatch this activity represents
///   - `title`: Display name (e.g., "Meeting Notes")
///
/// - **Dynamic (ContentState)**: Updated throughout the activity lifecycle
///   - `elapsedMilliseconds`: Current elapsed time
///   - `isRunning`: Whether the stopwatch is actively running
///   - `lastStartTime`: When the stopwatch was last started (for client-side calculation)
///
/// ## Example Usage
///
/// ```swift
/// // Start a Live Activity
/// let attributes = StopwatchAttributes(
///   stopwatchID: stopwatch.id,
///   title: stopwatch.title
/// )
/// let contentState = StopwatchAttributes.ContentState(
///   elapsedMilliseconds: stopwatch.elapsedMilliseconds,
///   isRunning: stopwatch.isRunning,
///   lastStartTime: stopwatch.lastStartTime
/// )
/// let activity = try Activity.request(
///   attributes: attributes,
///   content: .init(state: contentState, staleDate: nil)
/// )
///
/// // Update the Live Activity
/// let newState = StopwatchAttributes.ContentState(...)
/// await activity.update(ActivityContent(state: newState, staleDate: nil))
/// ```
struct StopwatchAttributes: ActivityAttributes {
  // MARK: - Static Attributes
  
  /// The ID of the stopwatch this Live Activity represents.
  ///
  /// Used to:
  /// - Deep link back to the correct stopwatch when tapped
  /// - Identify which activity to update when stopwatch state changes
  let stopwatchID: StopwatchItem.ID
  
  /// The display title for this stopwatch.
  ///
  /// Shown in the Live Activity UI. Set once at creation time.
  /// If the user renames the stopwatch, we don't update this -
  /// the activity represents the recording session, not the item.
  let title: String
  
  // MARK: - ContentState (Dynamic)
  
  /// Dynamic state that changes throughout the Live Activity lifecycle.
  ///
  /// This is the data that gets updated via `Activity.update()`.
  /// Keep this minimal for performance - updates are rate-limited by the system.
  ///
  /// ## Update Frequency
  ///
  /// ActivityKit limits updates to prevent battery drain:
  /// - Budget of ~10-15 updates per hour when app is backgrounded
  /// - More frequent updates allowed when app is foregrounded
  ///
  /// For stopwatches, we update when:
  /// - Play/pause state changes
  /// - Reset occurs
  /// - App goes to background (final state snapshot)
  ///
  /// The UI uses `lastStartTime` to calculate display time client-side,
  /// avoiding the need for frequent server pushes.
  struct ContentState: Codable, Hashable {
    /// The elapsed time in milliseconds at the last update.
    ///
    /// When `isRunning` is true, the UI adds time since `lastStartTime`
    /// to get the current display value.
    let elapsedMilliseconds: Int
    
    /// Whether the stopwatch is currently running.
    ///
    /// When true, the UI should animate/update the time display.
    /// When false, the UI shows the static `elapsedMilliseconds`.
    let isRunning: Bool
    
    /// When the stopwatch was last started, if running.
    ///
    /// Used for client-side time calculation:
    /// `displayTime = elapsedMilliseconds + (now - lastStartTime)`
    ///
    /// This allows the Live Activity to show accurate time without
    /// requiring constant updates from the app.
    let lastStartTime: Date?
    
    // MARK: - Mode Context (for UI adaptation)
    
    /// Whether a favorite (active recording) exists.
    ///
    /// Used by the Live Activity UI to determine which controls to show.
    /// When this Live Activity IS the favorite, this is always true.
    let hasFavorite: Bool
    
    /// Whether a non-favorite stopwatch is currently playing.
    ///
    /// Used for dual-mode UI: when both favorite (recording) and
    /// non-favorite (playback) are active simultaneously.
    let hasPlayingNonFavorite: Bool
    
    /// The title of the playing non-favorite, if any.
    ///
    /// Shown in the Live Activity when in dual mode to indicate
    /// what's playing alongside the recording.
    let playingNonFavoriteTitle: String?
    
    /// Debug text for testing Live Activity updates.
    /// Shows accumulated words when testing update flow.
    let debugText: String?
    
    // MARK: - Computed Properties
    
    /// Calculates the current display time in milliseconds.
    ///
    /// - Parameter now: The current date
    /// - Returns: The total elapsed milliseconds to display
    ///
    /// This mirrors `StopwatchItem.currentElapsedMilliseconds(now:)`.
    func currentElapsedMilliseconds(now: Date) -> Int {
      guard isRunning, let startTime = lastStartTime else {
        return elapsedMilliseconds
      }
      let additionalMs = Int(now.timeIntervalSince(startTime) * 1000)
      return elapsedMilliseconds + additionalMs
    }
  }
}

// MARK: - Convenience Initializers

extension StopwatchAttributes.ContentState {
  /// Creates a ContentState from a StopwatchItem.
  ///
  /// - Parameters:
  ///   - stopwatch: The stopwatch to create state from
  ///   - hasFavorite: Whether any favorite exists
  ///   - playingNonFavorite: The currently playing non-favorite, if any
  ///
  /// ## Example
  ///
  /// ```swift
  /// let state = StopwatchAttributes.ContentState(
  ///   from: stopwatch,
  ///   hasFavorite: favoriteStopwatchID != nil,
  ///   playingNonFavorite: stopwatches.first { $0.isRunning && $0.id != favoriteStopwatchID }
  /// )
  /// ```
  init(
    from stopwatch: StopwatchItem,
    hasFavorite: Bool,
    playingNonFavorite: StopwatchItem?,
    debugText: String? = nil
  ) {
    self.elapsedMilliseconds = stopwatch.elapsedMilliseconds
    self.isRunning = stopwatch.isRunning
    self.lastStartTime = stopwatch.lastStartTime
    self.hasFavorite = hasFavorite
    self.hasPlayingNonFavorite = playingNonFavorite != nil
    self.playingNonFavoriteTitle = playingNonFavorite?.title
    self.debugText = debugText
  }
}

extension StopwatchAttributes {
  /// Creates attributes from a StopwatchItem.
  ///
  /// - Parameter stopwatch: The stopwatch to create attributes from
  ///
  /// ## Example
  ///
  /// ```swift
  /// let attributes = StopwatchAttributes(from: favoriteStopwatch)
  /// ```
  init(from stopwatch: StopwatchItem) {
    self.stopwatchID = stopwatch.id
    self.title = stopwatch.title.isEmpty ? "Stopwatch" : stopwatch.title
  }
}

// MARK: - Mock Data for Previews

extension StopwatchAttributes {
  /// Mock attributes for widget/Live Activity previews.
  static let preview = StopwatchAttributes(
    stopwatchID: StopwatchItem.ID(UUID()),
    title: "Meeting Notes"
  )
}

extension StopwatchAttributes.ContentState {
  /// Mock running state for previews.
  static let previewRunning = StopwatchAttributes.ContentState(
    elapsedMilliseconds: 125_432,  // 2:05.432
    isRunning: true,
    lastStartTime: Date(),
    hasFavorite: true,
    hasPlayingNonFavorite: false,
    playingNonFavoriteTitle: nil,
    debugText: nil
  )
  
  /// Mock paused state for previews.
  static let previewPaused = StopwatchAttributes.ContentState(
    elapsedMilliseconds: 65_000,  // 1:05.000
    isRunning: false,
    lastStartTime: nil,
    hasFavorite: true,
    hasPlayingNonFavorite: false,
    playingNonFavoriteTitle: nil,
    debugText: nil
  )
  
  /// Mock dual-mode state (recording + playback) for previews.
  static let previewDualMode = StopwatchAttributes.ContentState(
    elapsedMilliseconds: 300_000,  // 5:00.000
    isRunning: true,
    lastStartTime: Date(),
    hasFavorite: true,
    hasPlayingNonFavorite: true,
    playingNonFavoriteTitle: "Reference Audio",
    debugText: nil
  )
}


