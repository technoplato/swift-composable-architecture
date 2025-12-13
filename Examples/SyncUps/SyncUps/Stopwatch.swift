import ComposableArchitecture
import SwiftUI

// MARK: - Stopwatch State Model

struct StopwatchState: Equatable, Codable {
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

// MARK: - Shared Key

extension SharedKey where Self == FileStorageKey<StopwatchState>.Default {
  static var stopwatch: Self {
    Self[.fileStorage(.documentsDirectory.appending(component: "stopwatch.json")), default: StopwatchState()]
  }
}

// MARK: - Stopwatch Reducer

@Reducer
struct Stopwatch {
  @ObservableState
  struct State: Equatable {
    @Shared(.stopwatch) var stopwatch
    var displayMilliseconds: Int = 0
  }

  enum Action {
    case onAppear
    case pauseButtonTapped
    case resetButtonTapped
    case startButtonTapped
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
        // Start timer for this reducer instance
        // Using .task in the view ensures this effect is cancelled when view disappears
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

// MARK: - Stopwatch View

struct StopwatchView: View {
  let store: StoreOf<Stopwatch>

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
    }
    .padding()
    .navigationTitle("Stopwatch")
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

// MARK: - Stopwatch List Card (for home screen, uses @Shared directly)

struct StopwatchListCard: View {
  @Shared var stopwatch: StopwatchState

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.01, paused: !stopwatch.isRunning)) { context in
      let currentMs = stopwatch.currentElapsedMilliseconds(now: context.date)

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label("Stopwatch", systemImage: "stopwatch")
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
          Button {
            toggleStopwatch()
          } label: {
            Image(systemName: stopwatch.isRunning ? "pause.circle.fill" : "play.circle.fill")
              .font(.system(size: 36))
              .foregroundColor(stopwatch.isRunning ? .orange : .green)
          }
          .buttonStyle(.plain)
        }
      }
      .padding()
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color(.systemBackground))
          .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
      )
    }
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
          .font(.system(size: 32, weight: .medium, design: .monospaced))
      }

      Text(String(format: "%02d:%02d", minutes, seconds))
        .font(.system(size: 32, weight: .medium, design: .monospaced))

      Text(String(format: ".%03d", ms))
        .font(.system(size: 20, weight: .medium, design: .monospaced))
        .foregroundColor(.secondary)
    }
    .monospacedDigit()
  }
}

// MARK: - Previews

#Preview("Stopwatch Screen") {
  NavigationStack {
    StopwatchView(
      store: Store(initialState: Stopwatch.State()) {
        Stopwatch()
      }
    )
  }
}

#Preview("Stopwatch Card") {
  @Shared(.stopwatch) var stopwatch
  return StopwatchListCard(stopwatch: $stopwatch)
    .padding()
    .background(Color(.systemGroupedBackground))
}

