/*
 HOW:
   Live Activity is started from the main app via ActivityKitClient.
   This file defines the UI that appears on Lock Screen and Dynamic Island.

 WHO:
   Agent (Cursor), User
   (Context: Adding WidgetKit/Live Activity support)

 WHAT:
   Live Activity configuration for active stopwatch recordings.
   Provides UI for:
   - Lock Screen banner
   - Dynamic Island compact view
   - Dynamic Island expanded view
   - Dynamic Island minimal view

 WHEN:
   2025-12-16
   Last Modified: 2025-12-16

 WHERE:
   StopwatchWidgets/StopwatchLiveActivity.swift

 WHY:
   Live Activities provide persistent, glanceable UI for ongoing recordings.
   Users can see elapsed time and control playback without unlocking or
   opening the app.
*/

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Configuration

/// Live Activity for active stopwatch recordings.
///
/// This activity appears when a favorite (recording) stopwatch is active.
/// It provides:
/// - Lock Screen banner with time and controls
/// - Dynamic Island compact view (leading: icon, trailing: time)
/// - Dynamic Island expanded view (full controls)
/// - Dynamic Island minimal view (just running indicator)
struct StopwatchLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: StopwatchAttributes.self) { context in
      // Lock Screen presentation
      LockScreenView(context: context)
        .activityBackgroundTint(.black.opacity(0.8))
        .activitySystemActionForegroundColor(.white)
      
    } dynamicIsland: { context in
      DynamicIsland {
        // Expanded view (long press)
        DynamicIslandExpandedRegion(.leading) {
          ExpandedLeadingView(context: context)
        }
        
        DynamicIslandExpandedRegion(.trailing) {
          ExpandedTrailingView(context: context)
        }
        
        DynamicIslandExpandedRegion(.bottom) {
          ExpandedBottomView(context: context)
        }
        
        DynamicIslandExpandedRegion(.center) {
          ExpandedCenterView(context: context)
        }
        
      } compactLeading: {
        // Compact: Left side (icon/indicator)
        CompactLeadingView(context: context)
        
      } compactTrailing: {
        // Compact: Right side (time)
        CompactTrailingView(context: context)
        
      } minimal: {
        // Minimal: When multiple activities are active
        MinimalView(context: context)
      }
    }
  }
}

// MARK: - Lock Screen View

/// Full-width Lock Screen banner view.
///
/// Shows:
/// - Title and recording indicator
/// - Large elapsed time
/// - Control buttons (play/pause, favorite, open)
struct LockScreenView: View {
  let context: ActivityViewContext<StopwatchAttributes>
  
  var body: some View {
    HStack(spacing: 16) {
      // Left: Info
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          if context.state.isRunning {
            Circle()
              .fill(Color.green)
              .frame(width: 8, height: 8)
          }
          
          Text("Recording")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        
        Text(context.attributes.title)
          .font(.headline)
        
        // Time display using TimelineView for live updates
        TimelineView(.animation(minimumInterval: 0.1, paused: !context.state.isRunning)) { timeline in
          Text(formatTime(context.state.currentElapsedMilliseconds(now: timeline.date)))
            .font(.system(size: 28, weight: .medium, design: .monospaced))
            .monospacedDigit()
        }
        
        // Dual mode indicator
        if context.state.hasPlayingNonFavorite, let title = context.state.playingNonFavoriteTitle {
          HStack(spacing: 4) {
            Image(systemName: "speaker.wave.2")
              .font(.caption2)
            Text(title)
              .font(.caption2)
          }
          .foregroundStyle(.secondary)
        }
      }
      
      Spacer()
      
      // Right: Controls
      HStack(spacing: 12) {
        // Play/Pause
        Button(intent: ToggleStopwatchIntent(stopwatchID: context.attributes.stopwatchID.rawValue.uuidString)) {
          Image(systemName: context.state.isRunning ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 36))
            .foregroundStyle(context.state.isRunning ? .orange : .green)
        }
        .buttonStyle(.plain)
        
        // Unfavorite
        Button(intent: UnfavoriteStopwatchIntent(stopwatchID: context.attributes.stopwatchID.rawValue.uuidString)) {
          Image(systemName: "star.slash.fill")
            .font(.system(size: 24))
            .foregroundStyle(.yellow)
        }
        .buttonStyle(.plain)
      }
    }
    .padding()
  }
}

// MARK: - Dynamic Island Compact Views

/// Compact leading view (left side of Dynamic Island).
struct CompactLeadingView: View {
  let context: ActivityViewContext<StopwatchAttributes>
  
  var body: some View {
    HStack(spacing: 4) {
      if context.state.isRunning {
        Circle()
          .fill(Color.green)
          .frame(width: 8, height: 8)
      }
      
      Image(systemName: "stopwatch.fill")
        .font(.caption)
    }
  }
}

/// Compact trailing view (right side of Dynamic Island).
struct CompactTrailingView: View {
  let context: ActivityViewContext<StopwatchAttributes>
  
  var body: some View {
    TimelineView(.animation(minimumInterval: 1, paused: !context.state.isRunning)) { timeline in
      let ms = context.state.currentElapsedMilliseconds(now: timeline.date)
      let minutes = (ms % 3_600_000) / 60_000
      let seconds = (ms % 60_000) / 1_000
      
      Text(String(format: "%d:%02d", minutes, seconds))
        .font(.system(size: 14, weight: .semibold, design: .monospaced))
        .monospacedDigit()
    }
  }
}

// MARK: - Dynamic Island Minimal View

/// Minimal view when multiple Live Activities are active.
struct MinimalView: View {
  let context: ActivityViewContext<StopwatchAttributes>
  
  var body: some View {
    if context.state.isRunning {
      Circle()
        .fill(Color.green)
        .frame(width: 10, height: 10)
    } else {
      Image(systemName: "stopwatch.fill")
        .font(.caption2)
    }
  }
}

// MARK: - Dynamic Island Expanded Views

/// Expanded leading view (left column).
struct ExpandedLeadingView: View {
  let context: ActivityViewContext<StopwatchAttributes>
  
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        if context.state.isRunning {
          Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
        }
        Text("REC")
          .font(.caption2.bold())
          .foregroundStyle(context.state.isRunning ? .green : .secondary)
      }
      
      Image(systemName: "stopwatch.fill")
        .font(.title2)
    }
  }
}

/// Expanded trailing view (right column).
struct ExpandedTrailingView: View {
  let context: ActivityViewContext<StopwatchAttributes>
  
  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      Text(context.attributes.title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      
      // Dual mode indicator
      if context.state.hasPlayingNonFavorite {
        HStack(spacing: 2) {
          Image(systemName: "speaker.wave.2")
          Text("Playing")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
  }
}

/// Expanded center view (main content).
struct ExpandedCenterView: View {
  let context: ActivityViewContext<StopwatchAttributes>
  
  var body: some View {
    TimelineView(.animation(minimumInterval: 0.1, paused: !context.state.isRunning)) { timeline in
      Text(formatTime(context.state.currentElapsedMilliseconds(now: timeline.date)))
        .font(.system(size: 32, weight: .medium, design: .monospaced))
        .monospacedDigit()
    }
  }
}

/// Expanded bottom view (control bar).
struct ExpandedBottomView: View {
  let context: ActivityViewContext<StopwatchAttributes>
  
  var body: some View {
    HStack(spacing: 16) {
      // Play/Pause
      Button(intent: ToggleStopwatchIntent(stopwatchID: context.attributes.stopwatchID.rawValue.uuidString)) {
        Label(
          context.state.isRunning ? "Pause" : "Play",
          systemImage: context.state.isRunning ? "pause.fill" : "play.fill"
        )
        .font(.caption.bold())
      }
      .buttonStyle(.borderedProminent)
      .tint(context.state.isRunning ? .orange : .green)
      
      // Unfavorite
      Button(intent: UnfavoriteStopwatchIntent(stopwatchID: context.attributes.stopwatchID.rawValue.uuidString)) {
        Image(systemName: "star.slash")
          .font(.caption)
      }
      .buttonStyle(.bordered)
      
      // Open in app
      Button(intent: NavigateToStopwatchIntent(stopwatchID: context.attributes.stopwatchID.rawValue.uuidString)) {
        Label("Open", systemImage: "arrow.right")
          .font(.caption)
      }
      .buttonStyle(.bordered)
    }
  }
}

// MARK: - Helpers

/// Formats milliseconds as HH:MM:SS.mm or MM:SS.mm
private func formatTime(_ milliseconds: Int) -> String {
  let hours = milliseconds / 3_600_000
  let minutes = (milliseconds % 3_600_000) / 60_000
  let seconds = (milliseconds % 60_000) / 1_000
  let cs = (milliseconds % 1_000) / 10  // Centiseconds
  
  if hours > 0 {
    return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, cs)
  } else {
    return String(format: "%02d:%02d.%02d", minutes, seconds, cs)
  }
}

// MARK: - Previews

#Preview("Lock Screen", as: .content, using: StopwatchAttributes.preview) {
  StopwatchLiveActivity()
} contentStates: {
  StopwatchAttributes.ContentState.previewRunning
  StopwatchAttributes.ContentState.previewPaused
  StopwatchAttributes.ContentState.previewDualMode
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: StopwatchAttributes.preview) {
  StopwatchLiveActivity()
} contentStates: {
  StopwatchAttributes.ContentState.previewRunning
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: StopwatchAttributes.preview) {
  StopwatchLiveActivity()
} contentStates: {
  StopwatchAttributes.ContentState.previewRunning
  StopwatchAttributes.ContentState.previewDualMode
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: StopwatchAttributes.preview) {
  StopwatchLiveActivity()
} contentStates: {
  StopwatchAttributes.ContentState.previewRunning
}

