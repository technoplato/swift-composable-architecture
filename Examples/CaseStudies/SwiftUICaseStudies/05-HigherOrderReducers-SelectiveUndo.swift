import ComposableArchitecture
import SwiftUI

// ============================================================================
// MARK: - UndoActionClassification Protocol
// ============================================================================
//
// This protocol is analogous to ViewAction - it allows actions to self-classify
// their undo behavior. A macro system (@UndoPoint, @UndoExcluded) would generate
// conformance to this protocol automatically.
//
// Usage with macros (conceptual):
// ```swift
// enum Action {
//   @UndoPoint case deleteItem(Item.ID)      // Always creates undo point
//   @UndoExcluded case timerTicked           // Never creates undo point
//   case regularAction                        // Debounced by default
// }
// ```
//
// Generated conformance:
// ```swift
// extension Action: UndoActionClassification {
//   var undoBehavior: UndoActionBehavior {
//     switch self {
//     case .deleteItem: return .createUndoPoint
//     case .timerTicked: return .exclude
//     default: return .debounce
//     }
//   }
// }
// ```
// ============================================================================

/// Protocol for actions that can classify their own undo behavior.
/// This is the foundation for the @UndoPoint and @UndoExcluded macro system.
protocol UndoActionClassification {
  /// Returns the undo behavior for this action.
  var undoBehavior: UndoActionBehavior { get }
}

/// Default implementation: all actions are debounced by default.
extension UndoActionClassification {
  var undoBehavior: UndoActionBehavior { .debounce }
}

private let readMe = """
  This screen demonstrates "Selective Undo" - a higher-order reducer that only tracks changes to \
  specific parts of state marked as "undoable", while leaving other state untouched.

  The key insight is that not all state should be undoable:
  
  • USER INTENT STATE (undoable): Decisions the user made - text they typed, items they added, \
  colors they selected. The user could have chosen differently, so undo lets them explore that \
  alternate timeline.

  • REALITY STATE (not undoable): Facts about the external world - elapsed time, network status, \
  server responses. Undoing these would be "lying about reality".

  • TRANSIENT STATE (not undoable): Momentary conditions - isLoading, isAnimating, cursor position. \
  These have no meaningful history.

  • DERIVED STATE (not undoable): Computed from other state - wordCount, isFormValid. You undo the \
  source, and derivation follows automatically.

  In this demo, the stopwatch timer keeps ticking even when you undo lap markers. Time is reality - \
  it cannot be undone. Laps are user decisions - they CAN be undone.
  """

// MARK: - SelectiveUndoReducer: Only Tracks Undoable State

/// A higher-order reducer that wraps any feature and adds selective undo/redo capabilities.
///
/// Unlike the basic `UndoReducer` which snapshots the entire state, this reducer only tracks
/// changes to specific "undoable" fields. Reality state, transient state, and derived state
/// are left untouched during undo/redo operations.
///
/// The wrapped feature must provide:
/// - An `UndoableState` type representing only the undoable portion of state
/// - A way to extract undoable state from full state
/// - A way to restore undoable state into full state
///
/// Usage:
/// ```swift
/// SelectiveUndoReducer(
///   feature: Stopwatch(),
///   historyLimit: 50,
///   extractUndoable: { $0.undoableState },
///   restoreUndoable: { state, undoable in state.undoableState = undoable }
/// )
/// ```
@Reducer
struct SelectiveUndoReducer<Feature: Reducer, UndoableState: Equatable> where Feature.State: Equatable {
  let feature: Feature
  let historyLimit: Int
  let extractUndoable: (Feature.State) -> UndoableState
  let restoreUndoable: (inout Feature.State, UndoableState) -> Void
  let actionFilter: (Feature.Action) -> UndoActionBehavior

  /// Initialize with explicit action filter closure.
  ///
  /// - Parameters:
  ///   - feature: The wrapped feature reducer
  ///   - historyLimit: Maximum number of undo states to keep (default: 50)
  ///   - extractUndoable: Closure to extract the undoable portion of state
  ///   - restoreUndoable: Closure to restore undoable state into full state
  ///   - actionFilter: Closure to determine undo behavior per action
  init(
    feature: Feature,
    historyLimit: Int = 50,
    extractUndoable: @escaping (Feature.State) -> UndoableState,
    restoreUndoable: @escaping (inout Feature.State, UndoableState) -> Void,
    actionFilter: @escaping (Feature.Action) -> UndoActionBehavior
  ) {
    self.feature = feature
    self.historyLimit = historyLimit
    self.extractUndoable = extractUndoable
    self.restoreUndoable = restoreUndoable
    self.actionFilter = actionFilter
  }

  /// Initialize without action filter - all actions create undo points.
  /// This is the legacy behavior for backwards compatibility.
  init(
    feature: Feature,
    historyLimit: Int = 50,
    extractUndoable: @escaping (Feature.State) -> UndoableState,
    restoreUndoable: @escaping (inout Feature.State, UndoableState) -> Void
  ) {
    self.feature = feature
    self.historyLimit = historyLimit
    self.extractUndoable = extractUndoable
    self.restoreUndoable = restoreUndoable
    // Default: all actions create undo points (legacy behavior)
    self.actionFilter = { _ in .createUndoPoint }
  }

  @ObservableState
  struct State: Equatable {
    var present: Feature.State
    var past: [UndoableState] = []
    var future: [UndoableState] = []

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    init(present: Feature.State) {
      self.present = present
    }
  }

  @CasePathable
  enum Action {
    case feature(Feature.Action)
    case undo
    case redo
    case clearHistory
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .feature(featureAction):
        let behavior = actionFilter(featureAction)

        switch behavior {
        case .exclude:
          // Run the action but don't create any undo point
          return feature.reduce(into: &state.present, action: featureAction)
            .map { .feature($0) }

        case .createUndoPoint, .debounce:
          // For now, treat debounce same as createUndoPoint
          // (Full debounce implementation would require async/clock)

          // 1. Snapshot ONLY the undoable state before mutation
          let undoableSnapshot = extractUndoable(state.present)
          state.past.append(undoableSnapshot)

          // 2. Prune history if it exceeds the limit
          if state.past.count > historyLimit {
            state.past.removeFirst()
          }

          // 3. Clear future (new action creates new timeline)
          state.future.removeAll()

          // 4. Run the wrapped feature's reducer (mutates ALL state including reality)
          return feature.reduce(into: &state.present, action: featureAction)
            .map { .feature($0) }
        }

      case .undo:
        guard let previousUndoable = state.past.popLast() else { return .none }

        // Push current undoable state to future
        let currentUndoable = extractUndoable(state.present)
        state.future.insert(currentUndoable, at: 0)

        // Restore ONLY the undoable portion - reality state is preserved!
        restoreUndoable(&state.present, previousUndoable)
        return .none

      case .redo:
        guard let nextUndoable = state.future.first else { return .none }
        state.future.removeFirst()

        // Push current undoable state to past
        let currentUndoable = extractUndoable(state.present)
        state.past.append(currentUndoable)

        // Restore ONLY the undoable portion
        restoreUndoable(&state.present, nextUndoable)
        return .none

      case .clearHistory:
        state.past.removeAll()
        state.future.removeAll()
        return .none
      }
    }
  }
}

// ============================================================================
// MARK: - Convenience Initializer for UndoActionClassification
// ============================================================================

extension SelectiveUndoReducer where Feature.Action: UndoActionClassification {
  /// Initialize using the action's built-in undo classification.
  ///
  /// This initializer is used when the Feature.Action conforms to
  /// UndoActionClassification (e.g., via @UndoPoint/@UndoExcluded macros).
  ///
  /// Usage:
  /// ```swift
  /// SelectiveUndoReducer(
  ///   feature: StopwatchFeature(),
  ///   extractUndoable: { $0.undoableState },
  ///   restoreUndoable: { state, undoable in ... }
  /// )
  /// // Automatically uses action.undoBehavior for filtering
  /// ```
  init(
    feature: Feature,
    historyLimit: Int = 50,
    extractUndoable: @escaping (Feature.State) -> UndoableState,
    restoreUndoable: @escaping (inout Feature.State, UndoableState) -> Void,
    useActionClassification: Bool
  ) {
    self.feature = feature
    self.historyLimit = historyLimit
    self.extractUndoable = extractUndoable
    self.restoreUndoable = restoreUndoable
    if useActionClassification {
      self.actionFilter = { $0.undoBehavior }
    } else {
      self.actionFilter = { _ in .createUndoPoint }
    }
  }
}

// MARK: - .undoable() Higher-Order Reducer Modifier

// ============================================================================
// CONFIGURATION TYPES
// ============================================================================

/// Configuration for how undo history is stored and operated.
enum UndoMode: Equatable {
  /// Default: Just store state snapshots (simpler, faster)
  /// History: [State₀, State₁, State₂, State₃]
  /// - Simpler, less storage
  /// - Fast undo/redo (just swap state)
  /// - No replay capability
  case snapshotOnly

  /// Store actions + snapshots (enables replay/verification)
  /// History: [(State₀, nil), (State₁, Action₁), (State₂, Action₂), ...]
  /// - Enables replay from any point
  /// - Can verify: "Do these actions produce this state?"
  /// - Enables time-travel debugging UI
  /// - More storage, but compressible
  case eventSourced
}

/// Specifies how an action should be treated for undo purposes.
enum UndoActionBehavior: Equatable {
  /// Create an undo point immediately (for significant actions like delete, import)
  case createUndoPoint

  /// Debounce with other actions (default for most actions)
  case debounce

  /// Exclude from undo history entirely (for timer ticks, network responses, etc.)
  case exclude
}

/// A single entry in the event-sourced timeline.
struct TimelineEntry: Identifiable, Equatable {
  let id: UUID

  /// String description of the action (for debugging UI)
  let actionDescription: String

  /// When this action was sent
  let timestamp: Date

  /// Whether this entry represents an undo point
  let isUndoPoint: Bool
}

/// State exposed by the .undoable() higher-order reducer.
/// Available for views to read and display undo/redo UI.
struct UndoInfo: Equatable {
  /// Whether there are any states to undo to
  var canUndo: Bool

  /// Whether there are any states to redo to
  var canRedo: Bool

  /// Number of undo steps available
  var undoCount: Int

  /// Number of redo steps available
  var redoCount: Int

  /// Configured maximum history size
  var historyLimit: Int

  /// When the last undo point was created
  var lastUndoPointDate: Date?

  // Event-sourced mode only:

  /// All recorded actions with timestamps (nil in snapshot-only mode)
  var timeline: [TimelineEntry]?

  /// Current position in the timeline (nil in snapshot-only mode)
  var currentTimelineIndex: Int?

  /// Whether we're currently replaying actions
  var isReplaying: Bool = false
}

// ============================================================================
// REDUCER EXTENSION
// ============================================================================

/// Extension to add the `.undoable()` modifier to any reducer.
/// This provides the ergonomic API described in the exploration document.
extension Reducer where State: Equatable {
  /// Wraps this reducer with selective undo/redo capabilities.
  ///
  /// Only the state extracted by `extractUndoable` will be tracked in undo history.
  /// Reality state, transient state, and derived state are preserved during undo/redo.
  ///
  /// Usage:
  /// ```swift
  /// var body: some ReducerOf<Self> {
  ///     Reduce { state, action in
  ///         // Your feature logic
  ///     }
  ///     .undoable(
  ///         mode: .snapshotOnly,
  ///         historyLimit: 50,
  ///         debounceInterval: .milliseconds(300),
  ///         extractUndoable: { $0.undoableState },
  ///         restoreUndoable: { state, undoable in state.restoreFrom(undoable) },
  ///         filter: { action in
  ///             switch action {
  ///             case .timerTicked: return .exclude
  ///             case .deleteItem: return .createUndoPoint
  ///             default: return .debounce
  ///             }
  ///         }
  ///     )
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - mode: Whether to use snapshot-only or event-sourced mode (default: .snapshotOnly)
  ///   - historyLimit: Maximum number of undo states to keep (default: 50)
  ///   - debounceInterval: Time window for coalescing rapid actions (default: 300ms)
  ///   - extractUndoable: Closure to extract the undoable portion of state
  ///   - restoreUndoable: Closure to restore undoable state into full state
  ///   - filter: Optional closure to specify undo behavior per action
  func undoable<UndoableState: Equatable>(
    mode: UndoMode = .snapshotOnly,
    historyLimit: Int = 50,
    debounceInterval: Duration = .milliseconds(300),
    extractUndoable: @escaping (State) -> UndoableState,
    restoreUndoable: @escaping (inout State, UndoableState) -> Void,
    filter: ((Action) -> UndoActionBehavior)? = nil
  ) -> UndoableModifier<Self, UndoableState> {
    UndoableModifier(
      base: self,
      mode: mode,
      historyLimit: historyLimit,
      debounceInterval: debounceInterval,
      extractUndoable: extractUndoable,
      restoreUndoable: restoreUndoable,
      filter: filter ?? { _ in .debounce }
    )
  }
}

// ============================================================================
// UNDOABLE MODIFIER REDUCER
// ============================================================================

/// The reducer produced by the `.undoable()` modifier.
/// This wraps the base reducer and adds undo/redo state management.
@Reducer
struct UndoableModifier<Base: Reducer, UndoableState: Equatable>: Reducer where Base.State: Equatable {
  let base: Base
  let mode: UndoMode
  let historyLimit: Int
  let debounceInterval: Duration
  let extractUndoable: (Base.State) -> UndoableState
  let restoreUndoable: (inout Base.State, UndoableState) -> Void
  let filter: (Base.Action) -> UndoActionBehavior

  // ============================================================================
  // STATE
  // ============================================================================

  @ObservableState
  struct State: Equatable {
    /// The current state of the wrapped feature
    var present: Base.State

    /// Past undoable states (most recent at the end)
    var past: [UndoableState] = []

    /// Future undoable states (for redo, most recent at the front)
    var future: [UndoableState] = []

    // Event-sourced mode properties
    /// Timeline of actions with timestamps (event-sourced mode only)
    var timeline: [TimelineEntry] = []

    /// Current position in the timeline (event-sourced mode only)
    var currentTimelineIndex: Int = 0

    /// Whether we're currently replaying actions
    var isReplaying: Bool = false

    /// When the last undo point was created
    var lastUndoPointDate: Date?

    /// Pending state for debouncing (not yet committed as undo point)
    var pendingUndoableState: UndoableState?

    /// ID for debounce cancellation
    var debounceID: UUID?

    // ========================================================================
    // COMPUTED PROPERTIES
    // ========================================================================

    /// Whether there are any states to undo to
    var canUndo: Bool { !past.isEmpty }

    /// Whether there are any states to redo to
    var canRedo: Bool { !future.isEmpty }

    /// Number of undo steps available
    var undoCount: Int { past.count }

    /// Number of redo steps available
    var redoCount: Int { future.count }

    /// Aggregated undo info for views
    func undoInfo(historyLimit: Int, mode: UndoMode) -> UndoInfo {
      UndoInfo(
        canUndo: canUndo,
        canRedo: canRedo,
        undoCount: undoCount,
        redoCount: redoCount,
        historyLimit: historyLimit,
        lastUndoPointDate: lastUndoPointDate,
        timeline: mode == .eventSourced ? timeline : nil,
        currentTimelineIndex: mode == .eventSourced ? currentTimelineIndex : nil,
        isReplaying: isReplaying
      )
    }

    init(present: Base.State) {
      self.present = present
    }
  }

  // ============================================================================
  // ACTIONS
  // ============================================================================

  @CasePathable
  enum Action {
    /// Forward action to the wrapped feature
    case base(Base.Action)

    /// Undo to the previous state
    case undo

    /// Redo to the next state
    case redo

    /// Clear all undo/redo history
    case clearHistory

    // Event-sourced mode actions
    /// Scrub to a specific index in the timeline
    case scrubToIndex(Int)

    /// Start replaying from current position
    case startReplay

    /// Pause replay
    case pauseReplay

    /// Advance replay by one step
    case replayTick

    // Internal actions
    /// Commit pending state as undo point (after debounce)
    case _commitPendingUndoPoint

    /// Cancel pending debounce
    case _cancelDebounce
  }

  // ============================================================================
  // DEPENDENCIES
  // ============================================================================

  @Dependency(\.date) var date
  @Dependency(\.uuid) var uuid
  @Dependency(\.continuousClock) var clock

  // ============================================================================
  // REDUCER BODY
  // ============================================================================

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .base(baseAction):
        let behavior = filter(baseAction)

        switch behavior {
        case .exclude:
          // Run the action but don't create any undo point
          return base.reduce(into: &state.present, action: baseAction)
            .map { .base($0) }

        case .createUndoPoint:
          // Commit any pending state first, then create immediate undo point
          if state.pendingUndoableState != nil {
            commitPendingState(&state)
          }

          // Create undo point BEFORE mutation
          let undoableSnapshot = extractUndoable(state.present)
          state.past.append(undoableSnapshot)
          pruneHistory(&state)
          state.future.removeAll()
          state.lastUndoPointDate = date.now

          // Record in timeline (event-sourced mode)
          if mode == .eventSourced {
            let entry = TimelineEntry(
              id: uuid(),
              actionDescription: String(describing: baseAction),
              timestamp: date.now,
              isUndoPoint: true
            )
            state.timeline.append(entry)
            state.currentTimelineIndex = state.timeline.count - 1
          }

          // Run the action
          return base.reduce(into: &state.present, action: baseAction)
            .map { .base($0) }

        case .debounce:
          // If no pending state, capture current state as potential undo point
          if state.pendingUndoableState == nil {
            state.pendingUndoableState = extractUndoable(state.present)
          }

          // Cancel existing debounce and start new one
          let debounceID = uuid()
          state.debounceID = debounceID

          // Record in timeline (event-sourced mode) - not as undo point yet
          if mode == .eventSourced {
            let entry = TimelineEntry(
              id: uuid(),
              actionDescription: String(describing: baseAction),
              timestamp: date.now,
              isUndoPoint: false
            )
            state.timeline.append(entry)
            state.currentTimelineIndex = state.timeline.count - 1
          }

          // Run the action
          let effect = base.reduce(into: &state.present, action: baseAction)
            .map { Action.base($0) }

          // Capture values for async closure
          let interval = debounceInterval

          // Schedule debounce commit
          return .merge(
            effect,
            .run { [clock] send in
              try await clock.sleep(for: interval)
              await send(._commitPendingUndoPoint)
            }
            .cancellable(id: debounceID)
          )
        }

      case .undo:
        guard let previousUndoable = state.past.popLast() else { return .none }

        // Commit any pending state first
        if state.pendingUndoableState != nil {
          commitPendingState(&state)
        }

        // Push current undoable state to future
        let currentUndoable = extractUndoable(state.present)
        state.future.insert(currentUndoable, at: 0)

        // Restore the undoable portion
        restoreUndoable(&state.present, previousUndoable)

        // Update timeline index (event-sourced mode)
        if mode == .eventSourced && state.currentTimelineIndex > 0 {
          state.currentTimelineIndex -= 1
        }

        return .none

      case .redo:
        guard let nextUndoable = state.future.first else { return .none }
        state.future.removeFirst()

        // Push current undoable state to past
        let currentUndoable = extractUndoable(state.present)
        state.past.append(currentUndoable)

        // Restore the undoable portion
        restoreUndoable(&state.present, nextUndoable)

        // Update timeline index (event-sourced mode)
        if mode == .eventSourced {
          state.currentTimelineIndex += 1
        }

        return .none

      case .clearHistory:
        state.past.removeAll()
        state.future.removeAll()
        state.timeline.removeAll()
        state.currentTimelineIndex = 0
        state.pendingUndoableState = nil
        state.lastUndoPointDate = nil
        return .none

      // Event-sourced mode actions
      case let .scrubToIndex(index):
        guard mode == .eventSourced else { return .none }
        guard index >= 0 && index < state.timeline.count else { return .none }

        // Calculate how many steps to undo or redo
        let currentIndex = state.currentTimelineIndex
        if index < currentIndex {
          // Need to undo
          for _ in 0..<(currentIndex - index) {
            guard let previousUndoable = state.past.popLast() else { break }
            let currentUndoable = extractUndoable(state.present)
            state.future.insert(currentUndoable, at: 0)
            restoreUndoable(&state.present, previousUndoable)
          }
        } else if index > currentIndex {
          // Need to redo
          for _ in 0..<(index - currentIndex) {
            guard let nextUndoable = state.future.first else { break }
            state.future.removeFirst()
            let currentUndoable = extractUndoable(state.present)
            state.past.append(currentUndoable)
            restoreUndoable(&state.present, nextUndoable)
          }
        }

        state.currentTimelineIndex = index
        return .none

      case .startReplay:
        guard mode == .eventSourced else { return .none }
        state.isReplaying = true
        return .run { [clock] send in
          while true {
            try await clock.sleep(for: .seconds(1))
            await send(.replayTick)
          }
        }
        .cancellable(id: "replay")

      case .pauseReplay:
        state.isReplaying = false
        return .cancel(id: "replay")

      case .replayTick:
        guard state.isReplaying else { return .none }
        guard state.currentTimelineIndex < state.timeline.count - 1 else {
          state.isReplaying = false
          return .cancel(id: "replay")
        }

        // Advance by one step
        return .send(.scrubToIndex(state.currentTimelineIndex + 1))

      case ._commitPendingUndoPoint:
        commitPendingState(&state)
        return .none

      case ._cancelDebounce:
        if let debounceID = state.debounceID {
          state.debounceID = nil
          return .cancel(id: debounceID)
        }
        return .none
      }
    }
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  private func commitPendingState(_ state: inout State) {
    guard let pendingState = state.pendingUndoableState else { return }

    state.past.append(pendingState)
    pruneHistory(&state)
    state.future.removeAll()
    state.lastUndoPointDate = date.now
    state.pendingUndoableState = nil

    // Mark the last timeline entry as an undo point (event-sourced mode)
    if mode == .eventSourced, !state.timeline.isEmpty {
      let lastIndex = state.timeline.count - 1
      let lastEntry = state.timeline[lastIndex]
      state.timeline[lastIndex] = TimelineEntry(
        id: lastEntry.id,
        actionDescription: lastEntry.actionDescription,
        timestamp: lastEntry.timestamp,
        isUndoPoint: true
      )
    }
  }

  private func pruneHistory(_ state: inout State) {
    while state.past.count > historyLimit {
      state.past.removeFirst()
    }
  }
}

// MARK: - Demo 1: Stopwatch with Selective Undo (Reality vs User Intent)

/// The undoable portion of stopwatch state - only user decisions
struct StopwatchUndoableState: Equatable {
  var lapTimes: [TimeInterval]
  var lapNotes: [String]
}

/// A stopwatch reducer that demonstrates reality state (timer) vs user intent (laps)
@Reducer
struct StopwatchFeature {
  @ObservableState
  struct State: Equatable {
    // ========================================================================
    // REALITY STATE - NOT UNDOABLE
    // ========================================================================
    // Time marches forward regardless of undo.
    // Undoing elapsed time would be lying about reality.
    var elapsedMilliseconds: Int = 0
    var isRunning: Bool = false

    // ========================================================================
    // USER INTENT STATE - UNDOABLE
    // ========================================================================
    // These are decisions the user made that they might want to reverse.
    var lapTimes: [TimeInterval] = []
    var lapNotes: [String] = []

    // ========================================================================
    // DERIVED STATE - NOT UNDOABLE (computed)
    // ========================================================================
    var lapCount: Int { lapTimes.count }
    var formattedTime: String {
      let totalSeconds = elapsedMilliseconds / 1000
      let minutes = totalSeconds / 60
      let seconds = totalSeconds % 60
      let ms = (elapsedMilliseconds % 1000) / 10
      return String(format: "%02d:%02d.%02d", minutes, seconds, ms)
    }

    // Helper to extract undoable state
    var undoableState: StopwatchUndoableState {
      StopwatchUndoableState(lapTimes: lapTimes, lapNotes: lapNotes)
    }
  }

  enum Action {
    // Timer actions (reality - excluded from undo)
    case timerTicked
    case startStopTapped

    // Lap actions (user intent - creates undo points)
    case lapTapped
    case deleteLap(Int)
    case deleteAllLaps
    case lapNoteChanged(index: Int, note: String)
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .timerTicked:
        // Reality: time advances, no undo point created
        state.elapsedMilliseconds += 10
        return .none

      case .startStopTapped:
        // Reality: starting/stopping is about the current moment
        state.isRunning.toggle()
        return .none

      case .lapTapped:
        // User Intent: user decided to mark this moment
        let lapTime = TimeInterval(state.elapsedMilliseconds) / 1000.0
        state.lapTimes.append(lapTime)
        state.lapNotes.append("")
        return .none

      case let .deleteLap(index):
        // User Intent: user decided to remove a lap
        guard state.lapTimes.indices.contains(index) else { return .none }
        state.lapTimes.remove(at: index)
        state.lapNotes.remove(at: index)
        return .none

      case .deleteAllLaps:
        // User Intent: user decided to clear all laps
        state.lapTimes.removeAll()
        state.lapNotes.removeAll()
        return .none

      case let .lapNoteChanged(index, note):
        // User Intent: editing notes
        guard state.lapNotes.indices.contains(index) else { return .none }
        state.lapNotes[index] = note
        return .none
      }
    }
  }
}

// ============================================================================
// MARK: - StopwatchFeature.Action + UndoActionClassification
// ============================================================================
//
// This extension is what the @UndoPoint/@UndoExcluded macros would generate.
// It classifies each action case by its undo behavior.
//
// Conceptual macro usage:
// ```swift
// enum Action {
//   @UndoExcluded case timerTicked
//   @UndoExcluded case startStopTapped
//   @UndoPoint case lapTapped
//   @UndoPoint case deleteLap(Int)
//   @UndoPoint case deleteAllLaps
//   case lapNoteChanged(index: Int, note: String)  // Debounced by default
// }
// ```
// ============================================================================

extension StopwatchFeature.Action: UndoActionClassification {
  var undoBehavior: UndoActionBehavior {
    switch self {
    // Reality state actions - EXCLUDED from undo
    case .timerTicked, .startStopTapped:
      return .exclude

    // User intent actions - CREATE UNDO POINTS
    case .lapTapped, .deleteLap, .deleteAllLaps:
      return .createUndoPoint

    // Text editing - DEBOUNCED (coalesce rapid edits)
    case .lapNoteChanged:
      return .debounce
    }
  }
}

// MARK: - Stopwatch Demo View

struct SelectiveUndoStopwatchDemoView: View {
  @Bindable var store: StoreOf<SelectiveUndoReducer<StopwatchFeature, StopwatchUndoableState>>

  var body: some View {
    Form {
      Section {
        AboutView(readMe: readMe)
      }

      // Timer display (REALITY - keeps ticking during undo!)
      Section {
        VStack(spacing: 16) {
          Text(store.present.formattedTime)
            .font(.system(size: 56, weight: .bold, design: .monospaced))
            .monospacedDigit()

          HStack(spacing: 24) {
            Button {
              store.send(.feature(.startStopTapped))
            } label: {
              Text(store.present.isRunning ? "Stop" : "Start")
                .font(.title2)
                .frame(width: 80)
            }
            .buttonStyle(.borderedProminent)
            .tint(store.present.isRunning ? .red : .green)

            Button("Lap") {
              store.send(.feature(.lapTapped))
            }
            .font(.title2)
            .disabled(!store.present.isRunning)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      } header: {
        HStack {
          Text("Timer")
          Spacer()
          Text("(Reality - not undoable)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      // Lap list (USER INTENT - undoable!)
      Section {
        if store.present.lapTimes.isEmpty {
          Text("No laps recorded")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
        } else {
          ForEach(Array(store.present.lapTimes.enumerated()), id: \.offset) { index, lapTime in
            HStack {
              Text("Lap \(index + 1)")
                .font(.headline)
              Spacer()
              Text(String(format: "%.2fs", lapTime))
                .monospacedDigit()
            }
          }
          .onDelete { indexSet in
            for index in indexSet {
              store.send(.feature(.deleteLap(index)))
            }
          }

          Button(role: .destructive) {
            store.send(.feature(.deleteAllLaps))
          } label: {
            Label("Delete All Laps", systemImage: "trash")
          }
        }
      } header: {
        HStack {
          Text("Laps (\(store.present.lapCount))")
          Spacer()
          Text("(User Intent - undoable!)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      // Undo/Redo controls
      Section {
        HStack(spacing: 32) {
          VStack {
            Button {
              store.send(.undo)
            } label: {
              Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 40))
            }
            .disabled(!store.canUndo)

            Text("Undo")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          VStack {
            Button {
              store.send(.redo)
            } label: {
              Image(systemName: "arrow.uturn.forward.circle.fill")
                .font(.system(size: 40))
            }
            .disabled(!store.canRedo)

            Text("Redo")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          VStack {
            Button(role: .destructive) {
              store.send(.clearHistory)
            } label: {
              Image(systemName: "trash.circle.fill")
                .font(.system(size: 40))
            }
            .disabled(!store.canUndo && !store.canRedo)

            Text("Clear")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      } header: {
        Text("History Controls")
      } footer: {
        Text("Try this: Start timer, add laps, then undo. Notice the timer keeps running!")
      }

      // History info
      Section {
        LabeledContent("Past states (undo)") {
          Text("\(store.past.count)")
            .monospacedDigit()
        }
        LabeledContent("Future states (redo)") {
          Text("\(store.future.count)")
            .monospacedDigit()
        }
        LabeledContent("Current elapsed time") {
          Text(store.present.formattedTime)
            .monospacedDigit()
        }
      } header: {
        Text("Debug Info")
      }
    }
    .buttonStyle(.borderless)
    .navigationTitle("Selective Undo")
  }
}

// MARK: - Demo 2: Drawing Canvas (Transient vs Committed State)

/// The undoable portion of canvas state - only committed strokes
struct CanvasUndoableState: Equatable {
  var strokes: [CanvasStroke]
  var selectedColor: CanvasColor
  var brushWidth: CGFloat
}

struct CanvasStroke: Equatable, Identifiable, Hashable {
  let id: UUID
  var points: [CGPoint]
  var color: CanvasColor
  var width: CGFloat

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

struct CanvasColor: Equatable, Hashable {
  var red: Double
  var green: Double
  var blue: Double

  static let black = CanvasColor(red: 0, green: 0, blue: 0)
  static let red = CanvasColor(red: 1, green: 0, blue: 0)
  static let blue = CanvasColor(red: 0, green: 0, blue: 1)
  static let green = CanvasColor(red: 0, green: 0.7, blue: 0)

  var swiftUIColor: Color {
    Color(red: red, green: green, blue: blue)
  }
}

/// A canvas reducer demonstrating transient (drawing) vs committed (strokes) state
@Reducer
struct CanvasFeature {
  @ObservableState
  struct State: Equatable {
    // ========================================================================
    // USER INTENT STATE - UNDOABLE
    // ========================================================================
    // Completed strokes are decisions - the user drew them
    var strokes: [CanvasStroke] = []
    var selectedColor: CanvasColor = .black
    var brushWidth: CGFloat = 4.0

    // ========================================================================
    // TRANSIENT STATE - NOT UNDOABLE
    // ========================================================================
    // Current drawing state - always about NOW
    var isPenDown: Bool = false
    var cursorPosition: CGPoint = .zero
    var currentStroke: CanvasStroke?

    // ========================================================================
    // DERIVED STATE - NOT UNDOABLE (computed)
    // ========================================================================
    var strokeCount: Int { strokes.count }
    var hasStrokes: Bool { !strokes.isEmpty }

    // Helper to extract undoable state
    var undoableState: CanvasUndoableState {
      CanvasUndoableState(
        strokes: strokes,
        selectedColor: selectedColor,
        brushWidth: brushWidth
      )
    }
  }

  enum Action {
    // Drawing actions (transient - excluded from undo)
    case penDown(at: CGPoint)
    case penMoved(to: CGPoint)
    case penUp

    // Committed actions (user intent - creates undo points)
    case strokeCompleted(CanvasStroke)
    case strokeDeleted(CanvasStroke.ID)
    case clearCanvas

    // Tool changes (user intent)
    case colorSelected(CanvasColor)
    case brushWidthChanged(CGFloat)
    
    // Slider editing lifecycle (for proper undo point creation)
    case brushWidthEditingStarted
    case brushWidthEditingEnded
  }

  @Dependency(\.uuid) var uuid

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .penDown(point):
        // Transient: start tracking, no undo point
        state.isPenDown = true
        state.cursorPosition = point
        state.currentStroke = CanvasStroke(
          id: uuid(),
          points: [point],
          color: state.selectedColor,
          width: state.brushWidth
        )
        return .none

      case let .penMoved(point):
        // Transient: update tracking, no undo point
        guard state.isPenDown else { return .none }
        state.cursorPosition = point
        state.currentStroke?.points.append(point)
        return .none

      case .penUp:
        // Transient -> Committed: now it becomes undoable
        state.isPenDown = false
        if let stroke = state.currentStroke, stroke.points.count > 1 {
          state.currentStroke = nil
          // This will trigger strokeCompleted which IS an undo point
          return .send(.strokeCompleted(stroke))
        }
        state.currentStroke = nil
        return .none

      case let .strokeCompleted(stroke):
        // User Intent: completed stroke, creates undo point
        state.strokes.append(stroke)
        return .none

      case let .strokeDeleted(id):
        // User Intent: deletion, creates undo point
        state.strokes.removeAll { $0.id == id }
        return .none

      case .clearCanvas:
        // User Intent: clear all, creates undo point
        state.strokes.removeAll()
        return .none

      case let .colorSelected(color):
        // User Intent: tool change
        state.selectedColor = color
        return .none

      case let .brushWidthChanged(width):
        // Transient during editing - just update the value
        state.brushWidth = width
        return .none
        
      case .brushWidthEditingStarted:
        // Mark that we're editing (undo point will be created)
        return .none
        
      case .brushWidthEditingEnded:
        // Editing finished - this is where we want the undo point
        return .none
      }
    }
  }
}

// ============================================================================
// MARK: - CanvasFeature.Action + UndoActionClassification
// ============================================================================
//
// This extension is what the @UndoPoint/@UndoExcluded macros would generate.
//
// IMPORTANT: For continuous controls like Sliders, use the "editing lifecycle" pattern:
// 1. brushWidthEditingStarted - Creates undo point BEFORE any changes (when user starts dragging)
// 2. brushWidthChanged - Excluded (intermediate values during drag shouldn't create undo points)
// 3. brushWidthEditingEnded - Excluded (undo point was already created at start)
//
// This ensures that scrubbing a slider from 4px to 20px creates only ONE undo point
// that restores to 4px, not 16 separate undo points for each intermediate value.
//
// Conceptual macro usage:
// ```swift
// @UndoActions
// enum Action {
//   @UndoExcluded case penDown(at: CGPoint)
//   @UndoExcluded case penMoved(to: CGPoint)
//   @UndoExcluded case penUp
//   @UndoPoint case strokeCompleted(CanvasStroke)
//   @UndoPoint case strokeDeleted(CanvasStroke.ID)
//   @UndoPoint case clearCanvas
//   @UndoPoint case brushWidthEditingStarted     // Undo point when drag starts
//   @UndoExcluded case brushWidthChanged(CGFloat) // Intermediate values excluded
//   @UndoExcluded case brushWidthEditingEnded    // Drag end excluded
//   case colorSelected(CanvasColor)              // Debounced (tap-based)
// }
// ```
// ============================================================================

extension CanvasFeature.Action: UndoActionClassification {
  var undoBehavior: UndoActionBehavior {
    switch self {
    // Transient drawing actions - EXCLUDED from undo
    case .penDown, .penMoved, .penUp:
      return .exclude

    // Committed stroke actions - CREATE UNDO POINTS
    case .strokeCompleted, .strokeDeleted, .clearCanvas:
      return .createUndoPoint

    // Tool changes with slider lifecycle:
    // - brushWidthEditingStarted: Creates undo point BEFORE changes start
    // - brushWidthChanged: Excluded (just intermediate values during drag)
    // - brushWidthEditingEnded: Excluded (the undo point was already created at start)
    case .brushWidthEditingStarted:
      return .createUndoPoint
    case .brushWidthChanged, .brushWidthEditingEnded:
      return .exclude
      
    // Color selection - still debounced (tap-based, not continuous)
    case .colorSelected:
      return .debounce
    }
  }
}

// MARK: - Canvas Demo View

struct SelectiveUndoCanvasDemoView: View {
  @Bindable var store: StoreOf<SelectiveUndoReducer<CanvasFeature, CanvasUndoableState>>

  private let colors: [CanvasColor] = [.black, .red, .blue, .green]

  var body: some View {
    VStack(spacing: 0) {
      // Canvas area
      GeometryReader { geometry in
        Canvas { context, size in
          // Draw completed strokes
          for stroke in store.present.strokes {
            var path = Path()
            if let firstPoint = stroke.points.first {
              path.move(to: firstPoint)
              for point in stroke.points.dropFirst() {
                path.addLine(to: point)
              }
            }
            context.stroke(
              path,
              with: .color(stroke.color.swiftUIColor),
              lineWidth: stroke.width
            )
          }

          // Draw current stroke (transient)
          if let currentStroke = store.present.currentStroke {
            var path = Path()
            if let firstPoint = currentStroke.points.first {
              path.move(to: firstPoint)
              for point in currentStroke.points.dropFirst() {
                path.addLine(to: point)
              }
            }
            context.stroke(
              path,
              with: .color(currentStroke.color.swiftUIColor.opacity(0.5)),
              lineWidth: currentStroke.width
            )
          }
        }
        .background(Color.white)
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              if !store.present.isPenDown {
                store.send(.feature(.penDown(at: value.location)))
              } else {
                store.send(.feature(.penMoved(to: value.location)))
              }
            }
            .onEnded { _ in
              store.send(.feature(.penUp))
            }
        )
      }
      .frame(height: 300)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
      )
      .padding()

      // Toolbar
      VStack(spacing: 16) {
        // Color picker
        HStack(spacing: 16) {
          Text("Color:")
            .foregroundStyle(.secondary)
          ForEach(colors, id: \.self) { color in
            Circle()
              .fill(color.swiftUIColor)
              .frame(width: 32, height: 32)
              .overlay(
                Circle()
                  .stroke(
                    store.present.selectedColor == color ? Color.primary : Color.clear,
                    lineWidth: 3
                  )
              )
              .onTapGesture {
                store.send(.feature(.colorSelected(color)))
              }
          }
          Spacer()
        }

        // Brush width
        HStack {
          Text("Brush:")
            .foregroundStyle(.secondary)
          Slider(
            value: Binding(
              get: { store.present.brushWidth },
              set: { store.send(.feature(.brushWidthChanged($0))) }
            ),
            in: 1...20,
            onEditingChanged: { isEditing in
              if isEditing {
                // User started dragging - create undo point BEFORE any changes
                store.send(.feature(.brushWidthEditingStarted))
              } else {
                // User stopped dragging - signal editing complete
                store.send(.feature(.brushWidthEditingEnded))
              }
            }
          )
          Text("\(Int(store.present.brushWidth))px")
            .monospacedDigit()
            .frame(width: 50)
        }

        Divider()

        // Undo/Redo controls
        HStack(spacing: 24) {
          Button {
            store.send(.undo)
          } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
          }
          .disabled(!store.canUndo)

          Button {
            store.send(.redo)
          } label: {
            Label("Redo", systemImage: "arrow.uturn.forward")
          }
          .disabled(!store.canRedo)

          Spacer()

          Button(role: .destructive) {
            store.send(.feature(.clearCanvas))
          } label: {
            Label("Clear", systemImage: "trash")
          }
          .disabled(!store.present.hasStrokes)

          Text("\(store.present.strokeCount) strokes")
            .foregroundStyle(.secondary)
            .font(.caption)
        }
      }
      .padding()
      .background(Color(uiColor: .systemGroupedBackground))
    }
    .navigationTitle("Canvas Undo")
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - Demo 3: Counter with .undoable() Modifier Pattern

/// Simple undoable state for the counter
struct CounterUndoableState: Equatable {
  var count: Int
  var history: [Int]
}

/// A simple counter that demonstrates the `.undoable()` modifier pattern.
/// This is the most ergonomic API described in the exploration document.
@Reducer
struct UndoableCounterFeature {
  @ObservableState
  struct State: Equatable {
    // USER INTENT - UNDOABLE
    var count: Int = 0
    var history: [Int] = []

    // REALITY - NOT UNDOABLE
    var lastModified: Date = .now

    // DERIVED
    var isPositive: Bool { count > 0 }
    var isNegative: Bool { count < 0 }

    // Helper to extract undoable state
    var undoableState: CounterUndoableState {
      CounterUndoableState(count: count, history: history)
    }
  }

  enum Action {
    case incrementButtonTapped
    case decrementButtonTapped
    case resetButtonTapped
  }

  @Dependency(\.date) var date

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .incrementButtonTapped:
        state.history.append(state.count)
        state.count += 1
        state.lastModified = date.now
        return .none

      case .decrementButtonTapped:
        state.history.append(state.count)
        state.count -= 1
        state.lastModified = date.now
        return .none

      case .resetButtonTapped:
        state.history.append(state.count)
        state.count = 0
        state.lastModified = date.now
        return .none
      }
    }
  }
}

/// Demo view showing the .undoable() modifier pattern
struct UndoableCounterDemoView: View {
  @Bindable var store: StoreOf<UndoableModifier<UndoableCounterFeature, CounterUndoableState>>

  var body: some View {
    Form {
      Section {
        AboutView(readMe: """
          This demo shows the `.undoable()` modifier pattern - the most ergonomic API \
          described in the exploration document.

          You call `.undoable()` on your reducer body with closures to extract and \
          restore the undoable portion of state:

          ```
          .undoable(
            historyLimit: 20,
            extractUndoable: { $0.undoableState },
            restoreUndoable: { state, undoable in ... }
          )
          ```

          Notice how `lastModified` (reality state) is NOT affected by undo/redo.
          """)
      }

      Section {
        HStack {
          Text("Count: \(store.present.count)")
            .font(.title)
            .fontWeight(.bold)
          Spacer()
          if store.present.isPositive {
            Image(systemName: "arrow.up.circle.fill")
              .foregroundStyle(.green)
          } else if store.present.isNegative {
            Image(systemName: "arrow.down.circle.fill")
              .foregroundStyle(.red)
          }
        }

        HStack(spacing: 20) {
          Button {
            store.send(.base(.decrementButtonTapped))
          } label: {
            Image(systemName: "minus.circle.fill")
              .font(.system(size: 44))
          }

          Button {
            store.send(.base(.incrementButtonTapped))
          } label: {
            Image(systemName: "plus.circle.fill")
              .font(.system(size: 44))
          }

          Spacer()

          Button(role: .destructive) {
            store.send(.base(.resetButtonTapped))
          } label: {
            Text("Reset")
          }
        }
        .buttonStyle(.borderless)
      } header: {
        Text("Counter")
      }

      Section {
        HStack(spacing: 32) {
          VStack {
            Button {
              store.send(.undo)
            } label: {
              Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 40))
            }
            .disabled(!store.canUndo)

            Text("Undo (\(store.undoCount))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          VStack {
            Button {
              store.send(.redo)
            } label: {
              Image(systemName: "arrow.uturn.forward.circle.fill")
                .font(.system(size: 40))
            }
            .disabled(!store.canRedo)

            Text("Redo (\(store.redoCount))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          VStack {
            Button(role: .destructive) {
              store.send(.clearHistory)
            } label: {
              Image(systemName: "trash.circle.fill")
                .font(.system(size: 40))
            }
            .disabled(!store.canUndo && !store.canRedo)

            Text("Clear")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      } header: {
        Text("Undo/Redo Controls")
      } footer: {
        Text("Try incrementing, then undo - the count reverts but lastModified stays!")
      }

      Section {
        LabeledContent("Last Modified") {
          Text(store.present.lastModified, style: .time)
            .monospacedDigit()
        }
        LabeledContent("History") {
          Text(store.present.history.map(String.init).joined(separator: " → "))
            .font(.caption)
            .monospacedDigit()
        }
      } header: {
        Text("Reality State (Not Undoable)")
      } footer: {
        Text("Notice: lastModified is NOT affected by undo/redo because it's reality state.")
      }
    }
    .buttonStyle(.borderless)
    .navigationTitle(".undoable() Modifier")
  }
}

// MARK: - Previews

#Preview("Stopwatch - Reality vs User Intent") {
  NavigationStack {
    SelectiveUndoStopwatchDemoView(
      store: Store(
        initialState: SelectiveUndoReducer<StopwatchFeature, StopwatchUndoableState>.State(
          present: StopwatchFeature.State()
        )
      ) {
        SelectiveUndoReducer(
          feature: StopwatchFeature(),
          extractUndoable: { $0.undoableState },
          restoreUndoable: { state, undoable in
            state.lapTimes = undoable.lapTimes
            state.lapNotes = undoable.lapNotes
          },
          // Uses StopwatchFeature.Action.undoBehavior automatically!
          useActionClassification: true
        )
      }
    )
  }
}

#Preview("Canvas - Transient vs Committed") {
  NavigationStack {
    SelectiveUndoCanvasDemoView(
      store: Store(
        initialState: SelectiveUndoReducer<CanvasFeature, CanvasUndoableState>.State(
          present: CanvasFeature.State()
        )
      ) {
        SelectiveUndoReducer(
          feature: CanvasFeature(),
          extractUndoable: { $0.undoableState },
          restoreUndoable: { state, undoable in
            state.strokes = undoable.strokes
            state.selectedColor = undoable.selectedColor
            state.brushWidth = undoable.brushWidth
          },
          // Uses CanvasFeature.Action.undoBehavior automatically!
          useActionClassification: true
        )
      }
    )
  }
}

#Preview(".undoable() Modifier Pattern") {
  NavigationStack {
    UndoableCounterDemoView(
      store: Store(
        initialState: UndoableModifier<UndoableCounterFeature, CounterUndoableState>.State(
          present: UndoableCounterFeature.State()
        )
      ) {
        UndoableCounterFeature()
          .undoable(
            mode: .snapshotOnly,
            historyLimit: 20,
            debounceInterval: .milliseconds(300),
            extractUndoable: { $0.undoableState },
            restoreUndoable: { state, undoable in
              state.count = undoable.count
              state.history = undoable.history
            },
            filter: { action in
              // Demonstrate action filtering:
              // - increment/decrement: immediate undo points
              // - reset: immediate undo point (significant action)
              switch action {
              case .incrementButtonTapped, .decrementButtonTapped:
                return .createUndoPoint
              case .resetButtonTapped:
                return .createUndoPoint
              }
            }
          )
      }
    )
  }
}

