import ComposableArchitecture
import IdentifiedCollections
import SwiftUI
import Tagged

// MARK: - Stopwatch Item Model

struct StopwatchItem: Equatable, Identifiable, Codable {
  let id: Tagged<Self, UUID>
  var title: String = ""
  var elapsedMilliseconds: Int = 0
  var isRunning: Bool = false
  var lastStartTime: Date?

  /// Calculates the current display time in milliseconds
  func currentElapsedMilliseconds(now: Date) -> Int {
    guard isRunning, let startTime = lastStartTime else {
      return elapsedMilliseconds
    }
    let additionalMs = Int(now.timeIntervalSince(startTime) * 1000)
    return elapsedMilliseconds + additionalMs
  }
}

// MARK: - StopwatchItem Mutation Methods
// These methods encapsulate state transitions for stopwatches.
// Reducers call these via `state.$stopwatch.withLock { $0.toggle(now:) }`.
// Pattern source: TCA case study SharedStateFileStorage (Stats.increment/decrement)

extension StopwatchItem {
  /// Toggles between running and paused states.
  mutating func toggle(now: Date) {
    if isRunning {
      elapsedMilliseconds = currentElapsedMilliseconds(now: now)
      lastStartTime = nil
      isRunning = false
    } else {
      lastStartTime = now
      isRunning = true
    }
  }

  /// Resets elapsed time to zero and stops the stopwatch.
  mutating func reset() {
    elapsedMilliseconds = 0
    lastStartTime = nil
    isRunning = false
  }

  /// Pauses the stopwatch if running. No-op if already paused.
  mutating func pause(now: Date) {
    guard isRunning else { return }
    elapsedMilliseconds = currentElapsedMilliseconds(now: now)
    lastStartTime = nil
    isRunning = false
  }
}

// MARK: - IdentifiedArrayOf<StopwatchItem> Helpers

extension IdentifiedArrayOf where Element == StopwatchItem {
  /// Pauses all running stopwatches except the favorite and an optional "keep running" ID.
  /// Used to enforce the single-playback constraint for non-favorites.
  mutating func pauseAllNonFavorites(
    except keepRunning: StopwatchItem.ID?,
    favoriteID: StopwatchItem.ID?,
    now: Date
  ) {
    for index in indices {
      let id = self[index].id
      guard id != favoriteID,         // Don't pause favorite
            id != keepRunning,        // Don't pause the one we're about to start
            self[index].isRunning     // Only pause if running
      else { continue }
      self[index].pause(now: now)
    }
  }
}

// MARK: - Shared Key for Stopwatches List

extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<StopwatchItem>>.Default {
  static var stopwatches: Self {
    Self[.fileStorage(.documentsDirectory.appending(component: "stopwatches.json")), default: []]
  }
}

// MARK: - Shared Key for Favorite Stopwatch ID

extension SharedKey where Self == FileStorageKey<StopwatchItem.ID?>.Default {
  static var favoriteStopwatchID: Self {
    Self[.fileStorage(.documentsDirectory.appending(component: "favorite-stopwatch-id.json")), default: nil]
  }
}

// MARK: - Shared Key for Last Played Local Stopwatch ID

extension SharedKey where Self == InMemoryKey<StopwatchItem.ID?>.Default {
  static var lastPlayedLocalStopwatchID: Self {
    Self[.inMemory("lastPlayedLocalStopwatchID"), default: nil]
  }
}

// MARK: - Stopwatch Detail Reducer
/// A display-only feature for showing stopwatch details.
///
/// This reducer is intentionally minimal - it only handles display updates via a timer.
/// All control actions (play/pause, delete, favorite) are handled by the floating controls,
/// which overlay every screen and provide a consistent control surface.
///
/// ## Architecture Decision
///
/// The detail view is **display-only** because:
/// 1. Floating controls provide consistent UX across all screens
/// 2. Controls adapt based on navigation context (handled by FloatingStopwatchControls)
/// 3. Avoids duplicate control logic between detail and floating controls
///
/// ## Example
///
/// ```swift
/// // Navigate to detail - controls appear via floating overlay
/// state.destination = .stopwatchDetail(
///   StopwatchDetail.State(stopwatch: sharedStopwatch)
/// )
/// ```

@Reducer
struct StopwatchDetail {
  @ObservableState
  struct State: Equatable {
    /// The stopwatch being displayed.
    @Shared var stopwatch: StopwatchItem
    
    /// Current display value in milliseconds (updated by timer).
    var displayMilliseconds: Int = 0
  }

  enum Action {
    /// Called when the view appears.
    case onAppear
    /// Timer tick to update display.
    case timerTicked
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.date.now) var now

  private enum CancelID { case timer }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        state.displayMilliseconds = state.stopwatch.currentElapsedMilliseconds(now: now)
        guard state.stopwatch.isRunning else { return .none }
        return timerEffect()

      case .timerTicked:
        state.displayMilliseconds = state.stopwatch.currentElapsedMilliseconds(now: now)
        // If stopwatch stopped (externally via floating controls), cancel timer
        if !state.stopwatch.isRunning {
          return .cancel(id: CancelID.timer)
        }
        return .none
      }
    }
  }

  private func timerEffect() -> Effect<Action> {
    .run { send in
      for await _ in clock.timer(interval: .milliseconds(10)) {
        await send(.timerTicked)
      }
    }
    .cancellable(id: CancelID.timer, cancelInFlight: true)
  }
}

// MARK: - Stopwatch Detail View
/// A display-only view showing stopwatch details.
///
/// This view intentionally has **no control buttons**. All controls are provided
/// by the floating controls overlay, which adapts based on whether this is a
/// favorite or non-favorite stopwatch.
///
/// ## What's Shown
///
/// - Large elapsed time display (hours:minutes:seconds.milliseconds)
/// - Running indicator (green dot when running)
/// - Title in navigation bar
///
/// ## Controls
///
/// The floating controls (FloatingStopwatchControlsView) provide:
/// - Play/pause for this stopwatch
/// - Delete (if favorite)
/// - Unfavorite (if favorite)
/// - Jump to favorite (if viewing non-favorite and favorite exists)
/// - Create new favorite (if viewing non-favorite and no favorite exists)

struct StopwatchDetailView: View {
  let store: StoreOf<StopwatchDetail>

  var body: some View {
    VStack(spacing: 48) {
      Spacer()

      // Large time display
      StopwatchDisplay(milliseconds: store.displayMilliseconds)
      
      // Running indicator
      if store.stopwatch.isRunning {
        HStack(spacing: 8) {
          Circle()
            .fill(Color.green)
            .frame(width: 10, height: 10)
          Text("Running")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      }

      Spacer()
      
      // Note about controls
      Text("Use floating controls below")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.bottom, 80)  // Space for floating controls
    }
    .padding()
    .navigationTitle(store.stopwatch.title.isEmpty ? "Stopwatch" : store.stopwatch.title)
    .navigationBarTitleDisplayMode(.inline)
    .task { await store.send(.onAppear).finish() }
  }
}

// MARK: - Stopwatch Detail View (TimelineView Version)
/// An alternative detail view that uses TimelineView instead of a reducer-managed timer.
///
/// This approach is simpler and fixes the bug where navigating via the floating bar
/// shows 0 seconds because `.onAppear` doesn't fire on destination replacement.
///
/// ## Why TimelineView is Better Here
///
/// 1. **No reducer state needed** - The view computes display time on demand
/// 2. **No timer effects** - SwiftUI handles the animation loop efficiently
/// 3. **Automatically pauses** - When stopwatch.isRunning is false, no updates
/// 4. **Works with navigation** - No dependency on onAppear/onDisappear lifecycle
///
/// The stopwatch model already stores `elapsedMilliseconds` + `lastStartTime`,
/// so we just call `currentElapsedMilliseconds(now:)` each frame.

struct StopwatchDetailViewV2: View {
  @Shared var stopwatch: StopwatchItem
  @Shared(.favoriteStopwatchID) var favoriteStopwatchID
  
  private var isFavorite: Bool {
    favoriteStopwatchID == stopwatch.id
  }

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.01, paused: !stopwatch.isRunning)) { context in
      let currentMs = stopwatch.currentElapsedMilliseconds(now: context.date)
      
      VStack(spacing: 48) {
        Spacer()

        // Large time display
        StopwatchDisplay(milliseconds: currentMs)
        
        // Running indicator
        HStack(spacing: 8) {
          if stopwatch.isRunning {
            Circle()
              .fill(Color.green)
              .frame(width: 10, height: 10)
            Text("Running")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
          
          // Favorite indicator
          if isFavorite {
            Image(systemName: "star.fill")
              .foregroundColor(.yellow)
            Text("Favorite")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
        }

        Spacer()
        
        // Note about controls
        Text("Use floating controls below")
          .font(.caption)
          .foregroundColor(.secondary)
          .padding(.bottom, 80)  // Space for floating controls
      }
      .padding()
    }
    .navigationTitle(stopwatch.title.isEmpty ? "Stopwatch" : stopwatch.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - Stopwatch Display Component

struct StopwatchDisplay: View {
  let milliseconds: Int

  private var hours: Int { milliseconds / 3_600_000 }
  private var minutes: Int { (milliseconds % 3_600_000) / 60_000 }
  private var seconds: Int { (milliseconds % 60_000) / 1_000 }
  private var ms: Int { milliseconds % 1_000 }

  var body: some View {
    HStack(alignment: .lastTextBaseline, spacing: 0) {
      if hours > 0 {
        Text("\(hours)")
          .font(.system(size: 72, weight: .thin, design: .monospaced))
        Text(":")
          .font(.system(size: 72, weight: .thin, design: .monospaced))
      }

      Text(String(format: "%02d", minutes))
        .font(.system(size: 72, weight: .thin, design: .monospaced))

      Text(":")
        .font(.system(size: 72, weight: .thin, design: .monospaced))

      Text(String(format: "%02d", seconds))
        .font(.system(size: 72, weight: .thin, design: .monospaced))

      Text(".")
        .font(.system(size: 48, weight: .thin, design: .monospaced))
        .foregroundColor(.secondary)

      Text(String(format: "%03d", ms))
        .font(.system(size: 48, weight: .thin, design: .monospaced))
        .foregroundColor(.secondary)
    }
    .monospacedDigit()
  }
}

// MARK: - Stopwatch Card (Pure View with Closures)
// This is a pure view component that reads @Shared state for display
// and calls closures for interactions. The parent (SyncUpsList) handles
// the actual business logic via reducer actions.

/// A card view displaying a stopwatch's title, elapsed time, and action buttons.
///
/// This is a pure view component that reads `@Shared` state for display and calls
/// closures for interactions. The parent view handles the actual business logic.
///
/// ## Tap Areas
///
/// The card has two types of tap targets:
/// 1. **Action buttons** (favorite, play/pause): Small circular buttons on the right
/// 2. **Card body**: The entire card area (for navigation to detail)
///
/// The parent view should use `.onTapGesture` on the card for navigation, while
/// the buttons handle their specific actions via the closures.
///
/// ## Example
///
/// ```swift
/// StopwatchCard(
///   stopwatch: $stopwatch,
///   onToggle: { store.send(.toggleTapped(id)) },
///   onFavorite: { store.send(.favoriteTapped(id)) }
/// )
/// .onTapGesture { store.send(.stopwatchTapped(id)) }
/// ```
struct StopwatchCard: View {
  @Shared var stopwatch: StopwatchItem
  @Shared(.favoriteStopwatchID) var favoriteStopwatchID
  let onToggle: () -> Void
  let onFavorite: () -> Void

  private var isFavorite: Bool {
    favoriteStopwatchID == stopwatch.id
  }

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.01, paused: !stopwatch.isRunning)) { context in
      let currentMs = stopwatch.currentElapsedMilliseconds(now: context.date)

      HStack(spacing: 12) {
        // Left side: Title and time (tappable for navigation via parent)
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(stopwatch.title.isEmpty ? "Stopwatch" : stopwatch.title)
              .font(.headline)
            if stopwatch.isRunning {
              Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            }
          }
          
          StopwatchCardDisplay(milliseconds: currentMs)
        }
        
        Spacer(minLength: 0)

        // Right side: Action buttons (these have their own tap handlers)
        HStack(spacing: 8) {
          // Favorite button
          Button(action: onFavorite) {
            Image(systemName: isFavorite ? "star.fill" : "star")
              .font(.system(size: 24))
              .foregroundColor(isFavorite ? .yellow : .secondary)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)

          // Toggle button
          Button(action: onToggle) {
            Image(systemName: stopwatch.isRunning ? "pause.circle.fill" : "play.circle.fill")
              .font(.system(size: 32))
              .foregroundColor(stopwatch.isRunning ? .orange : .green)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 4)
      // Ensure the entire card area registers taps (for parent's onTapGesture)
      .contentShape(Rectangle())
    }
  }
}

// MARK: - Compact Stopwatch Display (for card)

struct StopwatchCardDisplay: View {
  let milliseconds: Int

  private var hours: Int { milliseconds / 3_600_000 }
  private var minutes: Int { (milliseconds % 3_600_000) / 60_000 }
  private var seconds: Int { (milliseconds % 60_000) / 1_000 }
  private var ms: Int { milliseconds % 1_000 }

  var body: some View {
    HStack(alignment: .lastTextBaseline, spacing: 0) {
      if hours > 0 {
        Text("\(hours):")
          .font(.system(size: 28, weight: .medium, design: .monospaced))
      }

      Text(String(format: "%02d:%02d", minutes, seconds))
        .font(.system(size: 28, weight: .medium, design: .monospaced))

      Text(String(format: ".%03d", ms))
        .font(.system(size: 18, weight: .medium, design: .monospaced))
        .foregroundColor(.secondary)
    }
    .monospacedDigit()
  }
}

// MARK: - Compact Widget Display

struct StopwatchWidgetDisplay: View {
  let milliseconds: Int

  private var hours: Int { milliseconds / 3_600_000 }
  private var minutes: Int { (milliseconds % 3_600_000) / 60_000 }
  private var seconds: Int { (milliseconds % 60_000) / 1_000 }
  private var ms: Int { milliseconds % 1_000 }

  var body: some View {
    HStack(alignment: .lastTextBaseline, spacing: 0) {
      if hours > 0 {
        Text("\(hours):")
          .font(.system(size: 20, weight: .semibold, design: .monospaced))
      }

      Text(String(format: "%02d:%02d", minutes, seconds))
        .font(.system(size: 20, weight: .semibold, design: .monospaced))

      Text(String(format: ".%02d", ms / 10))
        .font(.system(size: 14, weight: .medium, design: .monospaced))
        .foregroundColor(.secondary)
    }
    .monospacedDigit()
  }
}

// MARK: - Mock Data

extension StopwatchItem {
  static let mock = Self(
    id: StopwatchItem.ID(UUID()),
    title: "Workout",
    elapsedMilliseconds: 65_432,
    isRunning: false
  )

  static let runningMock = Self(
    id: StopwatchItem.ID(UUID()),
    title: "Meeting",
    elapsedMilliseconds: 120_000,
    isRunning: false,
    lastStartTime: Date()
  )
}

// MARK: - Previews

#Preview("Stopwatch Detail") {
  NavigationStack {
    StopwatchDetailView(
      store: Store(initialState: StopwatchDetail.State(stopwatch: Shared(value: .mock))) {
        StopwatchDetail()
      }
    )
  }
}

#Preview("Stopwatch Card") {
  List {
    StopwatchCard(
      stopwatch: Shared(value: .mock),
      onToggle: {},
      onFavorite: {}
    )
    StopwatchCard(
      stopwatch: Shared(value: .runningMock),
      onToggle: {},
      onFavorite: {}
    )
  }
}
