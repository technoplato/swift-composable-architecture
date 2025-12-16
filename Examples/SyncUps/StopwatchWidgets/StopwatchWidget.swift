/*
 HOW:
   Add to Home Screen via long-press > Edit Home Screen > + button.
   Widget reads from @Shared state via App Group.

 WHO:
   Agent (Cursor), User
   (Context: Adding WidgetKit/Live Activity support)

 WHAT:
   Home screen widget showing stopwatch information.
   Supports all widget sizes:
   - systemSmall: Time display + play/pause
   - systemMedium: Title + time + controls
   - systemLarge: Full control bar
   - accessoryCircular: Minimal time (Lock Screen)
   - accessoryRectangular: Title + time (Lock Screen)

 WHEN:
   2025-12-16
   Last Modified: 2025-12-16

 WHERE:
   StopwatchWidgets/StopwatchWidget.swift

 WHY:
   Widgets provide at-a-glance stopwatch information without opening the app.
   Users can see elapsed time and control playback directly from Home Screen.
*/

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Widget Definition

/// Home screen widget for stopwatch display and control.
///
/// This widget shows the favorite stopwatch (if any) or a prompt to
/// create one. It adapts its UI based on the widget size family.
struct StopwatchWidget: Widget {
  /// Unique identifier for this widget type.
  let kind: String = "StopwatchWidget"
  
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: StopwatchTimelineProvider()) { entry in
      StopwatchWidgetEntryView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Stopwatch")
    .description("View and control your stopwatch.")
    .supportedFamilies([
      .systemSmall,
      .systemMedium,
      .systemLarge,
      .accessoryCircular,
      .accessoryRectangular,
    ])
  }
}

// MARK: - Timeline Entry

/// A single point in time for the widget to display.
///
/// Contains all the data needed to render the widget at a specific moment.
struct StopwatchWidgetEntry: TimelineEntry {
  /// When this entry should be displayed.
  let date: Date
  
  /// The favorite stopwatch, if any.
  let favoriteStopwatch: StopwatchItem?
  
  /// Whether a non-favorite is currently playing.
  let hasPlayingNonFavorite: Bool
  
  /// Title of the playing non-favorite, if any.
  let playingNonFavoriteTitle: String?
  
  /// Placeholder entry for widget gallery.
  static let placeholder = StopwatchWidgetEntry(
    date: Date(),
    favoriteStopwatch: StopwatchItem(
      id: StopwatchItem.ID(UUID()),
      title: "Meeting Notes",
      elapsedMilliseconds: 125_432,
      isRunning: true,
      lastStartTime: Date()
    ),
    hasPlayingNonFavorite: false,
    playingNonFavoriteTitle: nil
  )
  
  /// Empty entry when no favorite exists.
  static func empty(date: Date = Date()) -> StopwatchWidgetEntry {
    StopwatchWidgetEntry(
      date: date,
      favoriteStopwatch: nil,
      hasPlayingNonFavorite: false,
      playingNonFavoriteTitle: nil
    )
  }
}

// MARK: - Timeline Provider

/// Provides timeline entries for the stopwatch widget.
///
/// Reads from @Shared state to get current stopwatch information.
/// Updates timeline when stopwatch state changes.
struct StopwatchTimelineProvider: TimelineProvider {
  // TODO: Read from @Shared state via App Group
  // For now, return placeholder data
  
  func placeholder(in context: Context) -> StopwatchWidgetEntry {
    .placeholder
  }
  
  func getSnapshot(in context: Context, completion: @escaping (StopwatchWidgetEntry) -> Void) {
    // For preview/gallery, show placeholder
    if context.isPreview {
      completion(.placeholder)
      return
    }
    
    // TODO: Read actual state from @Shared
    completion(.empty())
  }
  
  func getTimeline(in context: Context, completion: @escaping (Timeline<StopwatchWidgetEntry>) -> Void) {
    // TODO: Read from @Shared state
    // For now, return empty timeline that refreshes in 15 minutes
    let entry = StopwatchWidgetEntry.empty()
    let timeline = Timeline(
      entries: [entry],
      policy: .after(Date().addingTimeInterval(15 * 60))
    )
    completion(timeline)
  }
}

// MARK: - Widget Entry View

/// The main view for the stopwatch widget.
///
/// Adapts layout based on widget family (size).
struct StopwatchWidgetEntryView: View {
  @Environment(\.widgetFamily) var family
  let entry: StopwatchWidgetEntry
  
  var body: some View {
    switch family {
    case .systemSmall:
      SmallWidgetView(entry: entry)
    case .systemMedium:
      MediumWidgetView(entry: entry)
    case .systemLarge:
      LargeWidgetView(entry: entry)
    case .accessoryCircular:
      CircularAccessoryView(entry: entry)
    case .accessoryRectangular:
      RectangularAccessoryView(entry: entry)
    default:
      SmallWidgetView(entry: entry)
    }
  }
}

// MARK: - Small Widget View

/// Widget view for systemSmall family.
///
/// Shows:
/// - Elapsed time (large)
/// - Running indicator
/// - Play/pause button
struct SmallWidgetView: View {
  let entry: StopwatchWidgetEntry
  
  var body: some View {
    if let stopwatch = entry.favoriteStopwatch {
      VStack(spacing: 8) {
        // Running indicator
        if stopwatch.isRunning {
          HStack(spacing: 4) {
            Circle()
              .fill(Color.green)
              .frame(width: 8, height: 8)
            Text("Recording")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        
        Spacer()
        
        // Time display
        Text(formatTime(stopwatch.currentElapsedMilliseconds(now: entry.date)))
          .font(.system(size: 28, weight: .medium, design: .monospaced))
          .minimumScaleFactor(0.5)
        
        Spacer()
        
        // Play/pause button (via App Intent)
        Button(intent: ToggleStopwatchIntent(stopwatchID: stopwatch.id.rawValue.uuidString)) {
          Image(systemName: stopwatch.isRunning ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(stopwatch.isRunning ? .orange : .green)
        }
        .buttonStyle(.plain)
      }
      .padding()
    } else {
      // No favorite - show create prompt
      VStack(spacing: 8) {
        Image(systemName: "stopwatch")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
        
        Text("No Recording")
          .font(.caption)
          .foregroundStyle(.secondary)
        
        Button(intent: CreateFavoriteIntent()) {
          Label("Start", systemImage: "plus.circle.fill")
            .font(.caption)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
      .padding()
    }
  }
}

// MARK: - Medium Widget View

/// Widget view for systemMedium family.
///
/// Shows:
/// - Title
/// - Elapsed time
/// - Running indicator
/// - Play/pause and favorite buttons
struct MediumWidgetView: View {
  let entry: StopwatchWidgetEntry
  
  var body: some View {
    if let stopwatch = entry.favoriteStopwatch {
      HStack(spacing: 16) {
        // Left: Title and time
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Text(stopwatch.title.isEmpty ? "Stopwatch" : stopwatch.title)
              .font(.headline)
            
            if stopwatch.isRunning {
              Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            }
          }
          
          Text(formatTime(stopwatch.currentElapsedMilliseconds(now: entry.date)))
            .font(.system(size: 36, weight: .medium, design: .monospaced))
            .minimumScaleFactor(0.5)
          
          if entry.hasPlayingNonFavorite, let title = entry.playingNonFavoriteTitle {
            Text("Playing: \(title)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        
        Spacer()
        
        // Right: Controls
        VStack(spacing: 8) {
          Button(intent: ToggleStopwatchIntent(stopwatchID: stopwatch.id.rawValue.uuidString)) {
            Image(systemName: stopwatch.isRunning ? "pause.circle.fill" : "play.circle.fill")
              .font(.system(size: 36))
              .foregroundStyle(stopwatch.isRunning ? .orange : .green)
          }
          .buttonStyle(.plain)
          
          Button(intent: NavigateToStopwatchIntent(stopwatchID: stopwatch.id.rawValue.uuidString)) {
            Image(systemName: "arrow.right.circle")
              .font(.system(size: 24))
              .foregroundStyle(.blue)
          }
          .buttonStyle(.plain)
        }
      }
      .padding()
    } else {
      // No favorite
      HStack {
        VStack(alignment: .leading, spacing: 8) {
          Text("No Active Recording")
            .font(.headline)
          Text("Tap to start a new recording")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        
        Spacer()
        
        Button(intent: CreateFavoriteIntent()) {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 44))
            .foregroundStyle(.green)
        }
        .buttonStyle(.plain)
      }
      .padding()
    }
  }
}

// MARK: - Large Widget View

/// Widget view for systemLarge family.
///
/// Shows full FloatingStopwatchControls-style UI with all actions.
struct LargeWidgetView: View {
  let entry: StopwatchWidgetEntry
  
  var body: some View {
    if let stopwatch = entry.favoriteStopwatch {
      VStack(spacing: 16) {
        // Header
        HStack {
          VStack(alignment: .leading) {
            Text("Recording")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(stopwatch.title.isEmpty ? "Stopwatch" : stopwatch.title)
              .font(.title2.bold())
          }
          
          Spacer()
          
          if stopwatch.isRunning {
            Circle()
              .fill(Color.green)
              .frame(width: 12, height: 12)
          }
        }
        
        Spacer()
        
        // Large time display
        Text(formatTime(stopwatch.currentElapsedMilliseconds(now: entry.date)))
          .font(.system(size: 56, weight: .thin, design: .monospaced))
          .minimumScaleFactor(0.5)
        
        Spacer()
        
        // Dual mode indicator
        if entry.hasPlayingNonFavorite, let title = entry.playingNonFavoriteTitle {
          HStack {
            Image(systemName: "speaker.wave.2")
            Text("Playing: \(title)")
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(.ultraThinMaterial, in: Capsule())
        }
        
        // Control bar
        HStack(spacing: 16) {
          // Play/Pause
          Button(intent: ToggleStopwatchIntent(stopwatchID: stopwatch.id.rawValue.uuidString)) {
            Label(
              stopwatch.isRunning ? "Pause" : "Play",
              systemImage: stopwatch.isRunning ? "pause.fill" : "play.fill"
            )
          }
          .buttonStyle(.borderedProminent)
          .tint(stopwatch.isRunning ? .orange : .green)
          
          // Unfavorite
          Button(intent: UnfavoriteStopwatchIntent(stopwatchID: stopwatch.id.rawValue.uuidString)) {
            Label("Unfavorite", systemImage: "star.slash")
          }
          .buttonStyle(.bordered)
          
          // Open in app
          Button(intent: NavigateToStopwatchIntent(stopwatchID: stopwatch.id.rawValue.uuidString)) {
            Label("Open", systemImage: "arrow.right")
          }
          .buttonStyle(.bordered)
        }
      }
      .padding()
    } else {
      // No favorite - prominent create UI
      VStack(spacing: 24) {
        Spacer()
        
        Image(systemName: "stopwatch")
          .font(.system(size: 64))
          .foregroundStyle(.secondary)
        
        VStack(spacing: 8) {
          Text("No Active Recording")
            .font(.title2.bold())
          Text("Start a new recording to track time")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        
        Spacer()
        
        Button(intent: CreateFavoriteIntent()) {
          Label("Start Recording", systemImage: "record.circle")
            .font(.headline)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
      .padding()
    }
  }
}

// MARK: - Circular Accessory View (Lock Screen)

/// Widget view for accessoryCircular family (Lock Screen).
///
/// Shows minimal time with running indicator.
struct CircularAccessoryView: View {
  let entry: StopwatchWidgetEntry
  
  var body: some View {
    if let stopwatch = entry.favoriteStopwatch {
      ZStack {
        // Running indicator ring
        if stopwatch.isRunning {
          Circle()
            .stroke(lineWidth: 2)
            .foregroundStyle(.green)
        }
        
        VStack(spacing: 0) {
          // Compact time (MM:SS)
          let ms = stopwatch.currentElapsedMilliseconds(now: entry.date)
          let minutes = (ms % 3_600_000) / 60_000
          let seconds = (ms % 60_000) / 1_000
          
          Text(String(format: "%d:%02d", minutes, seconds))
            .font(.system(size: 16, weight: .semibold, design: .monospaced))
        }
      }
    } else {
      // No favorite
      Image(systemName: "stopwatch")
        .font(.title2)
    }
  }
}

// MARK: - Rectangular Accessory View (Lock Screen)

/// Widget view for accessoryRectangular family (Lock Screen).
///
/// Shows title and time with running indicator.
struct RectangularAccessoryView: View {
  let entry: StopwatchWidgetEntry
  
  var body: some View {
    if let stopwatch = entry.favoriteStopwatch {
      HStack(spacing: 8) {
        // Running indicator
        if stopwatch.isRunning {
          Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
        }
        
        VStack(alignment: .leading, spacing: 2) {
          Text(stopwatch.title.isEmpty ? "Stopwatch" : stopwatch.title)
            .font(.caption2)
            .foregroundStyle(.secondary)
          
          Text(formatTime(stopwatch.currentElapsedMilliseconds(now: entry.date)))
            .font(.system(size: 18, weight: .semibold, design: .monospaced))
        }
        
        Spacer()
      }
    } else {
      HStack {
        Image(systemName: "stopwatch")
        Text("No Recording")
          .font(.caption)
      }
      .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Helpers

/// Formats milliseconds as HH:MM:SS.mmm or MM:SS.mmm
private func formatTime(_ milliseconds: Int) -> String {
  let hours = milliseconds / 3_600_000
  let minutes = (milliseconds % 3_600_000) / 60_000
  let seconds = (milliseconds % 60_000) / 1_000
  let ms = (milliseconds % 1_000) / 10  // Show centiseconds
  
  if hours > 0 {
    return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, ms)
  } else {
    return String(format: "%02d:%02d.%02d", minutes, seconds, ms)
  }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
  StopwatchWidget()
} timeline: {
  StopwatchWidgetEntry.placeholder
  StopwatchWidgetEntry.empty()
}

#Preview("Medium", as: .systemMedium) {
  StopwatchWidget()
} timeline: {
  StopwatchWidgetEntry.placeholder
  StopwatchWidgetEntry.empty()
}

#Preview("Large", as: .systemLarge) {
  StopwatchWidget()
} timeline: {
  StopwatchWidgetEntry.placeholder
  StopwatchWidgetEntry.empty()
}

#Preview("Circular", as: .accessoryCircular) {
  StopwatchWidget()
} timeline: {
  StopwatchWidgetEntry.placeholder
}

#Preview("Rectangular", as: .accessoryRectangular) {
  StopwatchWidget()
} timeline: {
  StopwatchWidgetEntry.placeholder
}

