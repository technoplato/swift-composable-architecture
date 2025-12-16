/*
 HOW:
   This is the entry point for the widget extension.
   Xcode automatically loads this when the widget extension runs.

 WHO:
   Agent (Cursor), User
   (Context: Adding WidgetKit/Live Activity support)

 WHAT:
   Widget bundle that registers all widgets and Live Activity configurations.
   Contains:
   - StopwatchWidget: Home screen/Lock Screen widgets
   - StopwatchLiveActivity: Live Activity for active recordings

 WHEN:
   2025-12-16
   Last Modified: 2025-12-16

 WHERE:
   StopwatchWidgets/StopwatchWidgetBundle.swift

 WHY:
   WidgetKit requires a WidgetBundle to register multiple widgets/activities.
   This bundle exposes both the static widgets and the Live Activity.
*/

import SwiftUI
import WidgetKit

/// The main entry point for the stopwatch widget extension.
///
/// This bundle registers all widgets and Live Activities available
/// from this extension.
///
/// ## Registered Components
///
/// - `StopwatchWidget`: Home screen widgets (all sizes)
/// - `StopwatchLiveActivity`: Live Activity for active recordings
@main
struct StopwatchWidgetBundle: WidgetBundle {
  var body: some Widget {
    // Home screen widgets
    StopwatchWidget()
    
    // Live Activity
    StopwatchLiveActivity()
  }
}


