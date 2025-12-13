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

// MARK: - Stopwatch Detail Reducer

@Reducer
struct StopwatchDetail {
  @ObservableState
  struct State: Equatable {
    @Shared var stopwatch: StopwatchItem
    var displayMilliseconds: Int = 0
  }

  enum Action {
    case deleteButtonTapped
    case onAppear
    case pauseButtonTapped
    case resetButtonTapped
    case startButtonTapped
    case timerTicked
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.date.now) var now
  @Dependency(\.dismiss) var dismiss

  private enum CancelID { case timer }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .deleteButtonTapped:
        let deletedID = state.stopwatch.id
        @Shared(.stopwatches) var stopwatches
        @Shared(.favoriteStopwatchID) var favoriteStopwatchID

        // If deleting the favorite, auto-select next
        if favoriteStopwatchID == deletedID {
          let currentIndex = stopwatches.firstIndex(where: { $0.id == deletedID })
          var nextID: StopwatchItem.ID? = nil

          if let index = currentIndex {
            if index + 1 < stopwatches.count {
              nextID = stopwatches[index + 1].id
            } else if index > 0 {
              nextID = stopwatches[index - 1].id
            }
          }
          $favoriteStopwatchID.withLock { $0 = nextID }
        }

        $stopwatches.withLock { _ = $0.remove(id: deletedID) }
        return .run { _ in await dismiss() }

      case .onAppear:
        state.displayMilliseconds = state.stopwatch.currentElapsedMilliseconds(now: now)
        guard state.stopwatch.isRunning else { return .none }
        return .run { send in
          for await _ in clock.timer(interval: .milliseconds(10)) {
            await send(.timerTicked)
          }
        }
        .cancellable(id: CancelID.timer, cancelInFlight: true)

      case .pauseButtonTapped:
        let currentTime = now
        state.$stopwatch.withLock { stopwatch in
          stopwatch.elapsedMilliseconds = stopwatch.currentElapsedMilliseconds(now: currentTime)
          stopwatch.lastStartTime = nil
          stopwatch.isRunning = false
        }
        state.displayMilliseconds = state.stopwatch.elapsedMilliseconds
        return .cancel(id: CancelID.timer)

      case .resetButtonTapped:
        state.$stopwatch.withLock { stopwatch in
          stopwatch.elapsedMilliseconds = 0
          stopwatch.lastStartTime = nil
          stopwatch.isRunning = false
        }
        state.displayMilliseconds = 0
        return .none

      case .startButtonTapped:
        let currentTime = now
        state.$stopwatch.withLock { stopwatch in
          stopwatch.lastStartTime = currentTime
          stopwatch.isRunning = true
        }
        return .run { send in
          for await _ in clock.timer(interval: .milliseconds(10)) {
            await send(.timerTicked)
          }
        }
        .cancellable(id: CancelID.timer, cancelInFlight: true)

      case .timerTicked:
        state.displayMilliseconds = state.stopwatch.currentElapsedMilliseconds(now: now)
        return .none
      }
    }
  }
}

// MARK: - Stopwatch Detail View

struct StopwatchDetailView: View {
  let store: StoreOf<StopwatchDetail>

  var body: some View {
    VStack(spacing: 48) {
      Spacer()

      StopwatchDisplay(milliseconds: store.displayMilliseconds)

      Spacer()

      HStack(spacing: 32) {
        // Reset button (only when paused and has time)
        if !store.stopwatch.isRunning && store.displayMilliseconds > 0 {
          Button {
            store.send(.resetButtonTapped)
          } label: {
            ZStack {
              Circle()
                .fill(Color(.systemGray5))
                .frame(width: 80, height: 80)
              Text("Reset")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.primary)
            }
          }
        } else {
          // Placeholder for layout
          Circle()
            .fill(Color.clear)
            .frame(width: 80, height: 80)
        }

        // Start/Pause button
        Button {
          if store.stopwatch.isRunning {
            store.send(.pauseButtonTapped)
          } else {
            store.send(.startButtonTapped)
          }
        } label: {
          ZStack {
            Circle()
              .fill(store.stopwatch.isRunning ? Color.orange : Color.green)
              .frame(width: 80, height: 80)
            Image(systemName: store.stopwatch.isRunning ? "pause.fill" : "play.fill")
              .font(.system(size: 32))
              .foregroundColor(.white)
          }
        }
      }

      Spacer()

      // Delete button
      Button(role: .destructive) {
        store.send(.deleteButtonTapped)
      } label: {
        Text("Delete Stopwatch")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .padding(.horizontal)
    }
    .padding()
    .navigationTitle(store.stopwatch.title.isEmpty ? "Stopwatch" : store.stopwatch.title)
    .navigationBarTitleDisplayMode(.inline)
    .task { await store.send(.onAppear).finish() }
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

// MARK: - Stopwatch Card (for list, uses @Shared directly with TimelineView)

struct StopwatchCard: View {
  @Shared var stopwatch: StopwatchItem
  @Shared(.favoriteStopwatchID) var favoriteStopwatchID

  private var isFavorite: Bool {
    favoriteStopwatchID == stopwatch.id
  }

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.01, paused: !stopwatch.isRunning)) { context in
      let currentMs = stopwatch.currentElapsedMilliseconds(now: context.date)

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(stopwatch.title.isEmpty ? "Stopwatch" : stopwatch.title)
            .font(.headline)
          Spacer()
          if stopwatch.isRunning {
            Circle()
              .fill(Color.green)
              .frame(width: 8, height: 8)
          }
        }

        HStack {
          StopwatchCardDisplay(milliseconds: currentMs)
          Spacer()

          // Favorite button
          Button {
            setAsFavorite()
          } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
              .font(.system(size: 24))
              .foregroundColor(isFavorite ? .yellow : .secondary)
          }
          .buttonStyle(.plain)

          Button {
            toggleStopwatch()
          } label: {
            Image(systemName: stopwatch.isRunning ? "pause.circle.fill" : "play.circle.fill")
              .font(.system(size: 32))
              .foregroundColor(stopwatch.isRunning ? .orange : .green)
          }
          .buttonStyle(.plain)
        }
      }
      .padding()
    }
  }

  private func setAsFavorite() {
    $favoriteStopwatchID.withLock { $0 = stopwatch.id }
  }

  private func toggleStopwatch() {
    @Dependency(\.date.now) var now
    $stopwatch.withLock { state in
      if state.isRunning {
        // Pause
        state.elapsedMilliseconds = state.currentElapsedMilliseconds(now: now)
        state.lastStartTime = nil
        state.isRunning = false
      } else {
        // Start
        state.lastStartTime = now
        state.isRunning = true
      }
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
    StopwatchCard(stopwatch: Shared(value: .mock))
    StopwatchCard(stopwatch: Shared(value: .runningMock))
  }
}
