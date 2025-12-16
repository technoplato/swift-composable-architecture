/*
 HOW:
   Import this file in both the main app and widget extension.
   Use the shared keys to access stopwatch state across processes.
   
   [Inputs]
   - App Group identifier: "group.syncups.stopwatch"
   
   [Outputs]
   - @Shared state accessible from both app and widget extension
   
   [Side Effects]
   - Reads/writes to App Group container

 WHO:
   Agent (Cursor), User
   (Context: Adding WidgetKit/Live Activity support)

 WHAT:
   Shared key definitions for cross-process state sharing.
   These keys use the App Group container URL so both the main app
   and widget extension can access the same state.

 WHEN:
   2025-12-16
   Last Modified: 2025-12-16
   [Change Log:
     - 2025-12-16: Initial creation for widget extension support
   ]

 WHERE:
   SyncUps/Stopwatch+SharedKeys.swift

 WHY:
   Widget extensions run in a separate process from the main app.
   To share @Shared state, both must use the same file storage location.
   App Groups provide a shared container accessible to both processes.
   
   This file redefines the shared keys from Stopwatch.swift to use
   the App Group container instead of the documents directory.
*/

import Foundation
import IdentifiedCollections
import Sharing
import Tagged

// MARK: - App Group Configuration

/// The App Group identifier for sharing state between app and widget.
///
/// This must match the App Group capability configured in:
/// - Main app target (SyncUps)
/// - Widget extension target (StopwatchWidgets)
///
/// To configure in Xcode:
/// 1. Select target → Signing & Capabilities
/// 2. Add "App Groups" capability
/// 3. Add this identifier to both targets
let appGroupIdentifier = "group.syncups.stopwatch"

/// Returns the shared container URL for the App Group.
///
/// Falls back to documents directory if App Group is unavailable
/// (e.g., in tests or previews without entitlements).
private var sharedContainerURL: URL {
  if let containerURL = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: appGroupIdentifier
  ) {
    return containerURL
  }
  
  // Fallback for tests/previews
  return URL.documentsDirectory
}

// MARK: - Shared Keys (App Group)

/// These keys override the ones in Stopwatch.swift to use App Group storage.
/// Import this file AFTER Stopwatch.swift to use the App Group versions.

extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<StopwatchItem>>.Default {
  /// Shared stopwatches list, stored in App Group container.
  ///
  /// Accessible from both main app and widget extension.
  ///
  /// ## Usage
  ///
  /// ```swift
  /// @Shared(.stopwatches) var stopwatches
  /// ```
  static var stopwatches: Self {
    Self[
      .fileStorage(sharedContainerURL.appending(component: "stopwatches.json")),
      default: []
    ]
  }
}

extension SharedKey where Self == FileStorageKey<StopwatchItem.ID?>.Default {
  /// The favorite stopwatch ID, stored in App Group container.
  ///
  /// Accessible from both main app and widget extension.
  ///
  /// ## Usage
  ///
  /// ```swift
  /// @Shared(.favoriteStopwatchID) var favoriteStopwatchID
  /// ```
  static var favoriteStopwatchID: Self {
    Self[
      .fileStorage(sharedContainerURL.appending(component: "favorite-stopwatch-id.json")),
      default: nil
    ]
  }
}

// MARK: - Widget-Specific Keys

extension SharedKey where Self == FileStorageKey<String?>.Default {
  /// The ID of the currently active Live Activity.
  ///
  /// Stored so the widget can check if a Live Activity exists.
  /// Updated by the main app when starting/ending activities.
  ///
  /// ## Usage
  ///
  /// ```swift
  /// @Shared(.activeLiveActivityID) var activityID
  /// ```
  static var activeLiveActivityID: Self {
    Self[
      .fileStorage(sharedContainerURL.appending(component: "active-live-activity-id.json")),
      default: nil
    ]
  }
}

// MARK: - Note on lastPlayedLocalStopwatchID

// The lastPlayedLocalStopwatchID remains in-memory only (InMemoryKey)
// because it's session-specific and doesn't need to persist across
// app launches or be shared with the widget.
//
// The widget doesn't need to know which non-favorite was last played;
// it only needs to know if ANY non-favorite is currently playing,
// which it can determine from the stopwatches array.

