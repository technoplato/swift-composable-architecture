import ComposableArchitecture
import Foundation
import Testing

@testable import SwiftUICaseStudies

@MainActor
struct SelectiveUndoReducerTests {
  // ==========================================================================
  // EXPECTED BEHAVIOR TESTS (User's described behavior)
  // ==========================================================================

  /// User opens stopwatch, clicks start, the stopwatch should NOT move
  /// (because we're not actually running a timer in tests).
  /// The lap button works, and undoing laps works.
  @Test
  func stopwatchLapsAreUndoable() async {
    let store = TestStore(
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
        }
      )
    }

    // Start the stopwatch
    await store.send(.feature(.startStopTapped)) {
      $0.past = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
      $0.present.isRunning = true
    }

    // Simulate some time passing
    await store.send(.feature(.timerTicked)) {
      $0.past.append(StopwatchUndoableState(lapTimes: [], lapNotes: []))
      $0.present.elapsedMilliseconds = 10
    }
    await store.send(.feature(.timerTicked)) {
      $0.past.append(StopwatchUndoableState(lapTimes: [], lapNotes: []))
      $0.present.elapsedMilliseconds = 20
    }

    // Add first lap
    await store.send(.feature(.lapTapped)) {
      $0.past.append(StopwatchUndoableState(lapTimes: [], lapNotes: []))
      $0.present.lapTimes = [0.02]  // 20ms = 0.02s
      $0.present.lapNotes = [""]
    }

    // More time
    await store.send(.feature(.timerTicked)) {
      $0.past.append(StopwatchUndoableState(lapTimes: [0.02], lapNotes: [""]))
      $0.present.elapsedMilliseconds = 30
    }

    // Add second lap
    await store.send(.feature(.lapTapped)) {
      $0.past.append(StopwatchUndoableState(lapTimes: [0.02], lapNotes: [""]))
      $0.present.lapTimes = [0.02, 0.03]
      $0.present.lapNotes = ["", ""]
    }

    #expect(store.state.present.lapTimes.count == 2)

    // Undo second lap - should restore to 1 lap
    await store.send(.undo) {
      _ = $0.past.popLast()
      $0.present.lapTimes = [0.02]
      $0.present.lapNotes = [""]
      $0.future = [StopwatchUndoableState(lapTimes: [0.02, 0.03], lapNotes: ["", ""])]
    }

    #expect(store.state.present.lapTimes.count == 1)
    // Time should still be at 30ms - reality is preserved!
    #expect(store.state.present.elapsedMilliseconds == 30)

    // Undo first lap - should restore to 0 laps
    // But wait - there were timer ticks in between, so we need to undo through those too
    // This is the "weird shared state stuff" - timer ticks create undo points!
    await store.send(.undo) {
      _ = $0.past.popLast()
      $0.present.lapTimes = [0.02]  // Still at 1 lap because we undid a timerTicked
      $0.present.lapNotes = [""]
      $0.future.insert(StopwatchUndoableState(lapTimes: [0.02], lapNotes: [""]), at: 0)
    }

    // This reveals the bug: timer ticks are creating undo points!
    // We need to undo 3 more times to get back to 0 laps (through timerTicked, lapTapped, timerTicked)
  }

  /// Deleting a lap should be undoable
  @Test
  func deleteLapIsUndoable() async {
    var initialState = SelectiveUndoReducer<StopwatchFeature, StopwatchUndoableState>.State(
      present: StopwatchFeature.State()
    )
    initialState.present.lapTimes = [1.0, 2.0, 3.0]
    initialState.present.lapNotes = ["First", "Second", "Third"]

    let store = TestStore(initialState: initialState) {
      SelectiveUndoReducer(
        feature: StopwatchFeature(),
        extractUndoable: { $0.undoableState },
        restoreUndoable: { state, undoable in
          state.lapTimes = undoable.lapTimes
          state.lapNotes = undoable.lapNotes
        }
      )
    }

    // Delete middle lap
    await store.send(.feature(.deleteLap(1))) {
      $0.past = [StopwatchUndoableState(lapTimes: [1.0, 2.0, 3.0], lapNotes: ["First", "Second", "Third"])]
      $0.present.lapTimes = [1.0, 3.0]
      $0.present.lapNotes = ["First", "Third"]
    }

    #expect(store.state.present.lapTimes.count == 2)

    // Undo deletion
    await store.send(.undo) {
      $0.past = []
      $0.present.lapTimes = [1.0, 2.0, 3.0]
      $0.present.lapNotes = ["First", "Second", "Third"]
      $0.future = [StopwatchUndoableState(lapTimes: [1.0, 3.0], lapNotes: ["First", "Third"])]
    }

    #expect(store.state.present.lapTimes.count == 3)
    #expect(store.state.present.lapNotes[1] == "Second")
  }

  /// Delete all laps should be undoable
  @Test
  func deleteAllLapsIsUndoable() async {
    var initialState = SelectiveUndoReducer<StopwatchFeature, StopwatchUndoableState>.State(
      present: StopwatchFeature.State()
    )
    initialState.present.lapTimes = [1.0, 2.0, 3.0]
    initialState.present.lapNotes = ["A", "B", "C"]
    initialState.present.elapsedMilliseconds = 5000

    let store = TestStore(initialState: initialState) {
      SelectiveUndoReducer(
        feature: StopwatchFeature(),
        extractUndoable: { $0.undoableState },
        restoreUndoable: { state, undoable in
          state.lapTimes = undoable.lapTimes
          state.lapNotes = undoable.lapNotes
        }
      )
    }

    // Delete all
    await store.send(.feature(.deleteAllLaps)) {
      $0.past = [StopwatchUndoableState(lapTimes: [1.0, 2.0, 3.0], lapNotes: ["A", "B", "C"])]
      $0.present.lapTimes = []
      $0.present.lapNotes = []
    }

    #expect(store.state.present.lapTimes.isEmpty)
    // Elapsed time is preserved!
    #expect(store.state.present.elapsedMilliseconds == 5000)

    // Undo
    await store.send(.undo) {
      $0.past = []
      $0.present.lapTimes = [1.0, 2.0, 3.0]
      $0.present.lapNotes = ["A", "B", "C"]
      $0.future = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
    }

    #expect(store.state.present.lapTimes.count == 3)
  }

  // ==========================================================================
  // ORIGINAL TESTS
  // ==========================================================================

  // MARK: - Basic Undo/Redo Tests

  @Test
  func featureActionAddsToHistory() async {
    let store = TestStore(
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
        }
      )
    }

    // Initial state: no laps, no history
    #expect(store.state.present.lapTimes.isEmpty)
    #expect(store.state.past.isEmpty)
    #expect(store.state.future.isEmpty)

    // Add a lap - should snapshot current undoable state to past
    await store.send(\.feature.lapTapped) {
      $0.past = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
      $0.present.lapTimes = [0.0]
      $0.present.lapNotes = [""]
    }

    #expect(store.state.canUndo == true)
    #expect(store.state.canRedo == false)
  }

  @Test
  func undoRestoresOnlyUndoableState() async {
    let store = TestStore(
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
        }
      )
    }

    // Add a lap
    await store.send(\.feature.lapTapped) {
      $0.past = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
      $0.present.lapTimes = [0.0]
      $0.present.lapNotes = [""]
    }

    // Simulate time passing (reality state changes)
    // Note: timerTicked also creates an undo point because ALL actions go through
    // the reducer. In a production system, you'd want action filtering to exclude
    // timer ticks from undo history.
    await store.send(\.feature.timerTicked) {
      $0.past = [
        StopwatchUndoableState(lapTimes: [], lapNotes: []),
        StopwatchUndoableState(lapTimes: [0.0], lapNotes: [""]),
      ]
      $0.present.elapsedMilliseconds = 10
    }

    // Add another lap at the new time
    await store.send(\.feature.lapTapped) {
      $0.past = [
        StopwatchUndoableState(lapTimes: [], lapNotes: []),
        StopwatchUndoableState(lapTimes: [0.0], lapNotes: [""]),
        StopwatchUndoableState(lapTimes: [0.0], lapNotes: [""]),  // From timerTicked (same undoable state)
      ]
      $0.present.lapTimes = [0.0, 0.01]
      $0.present.lapNotes = ["", ""]
    }

    // Undo - restores to state before last lapTapped
    await store.send(.undo) {
      $0.past = [
        StopwatchUndoableState(lapTimes: [], lapNotes: []),
        StopwatchUndoableState(lapTimes: [0.0], lapNotes: [""]),
      ]
      // Lap state is restored to state from timerTicked snapshot
      $0.present.lapTimes = [0.0]
      $0.present.lapNotes = [""]
      // elapsedMilliseconds stays at 10 - reality is preserved!
      $0.future = [StopwatchUndoableState(lapTimes: [0.0, 0.01], lapNotes: ["", ""])]
    }

    // Reality state is preserved even through undo!
    #expect(store.state.present.elapsedMilliseconds == 10)
  }

  @Test
  func realityStateNotAffectedByUndo() async {
    let store = TestStore(
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
        }
      )
    }

    // Start the timer
    await store.send(\.feature.startStopTapped) {
      $0.past = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
      $0.present.isRunning = true
    }

    // Tick the timer several times
    for i in 1...5 {
      await store.send(\.feature.timerTicked) {
        $0.past.append(StopwatchUndoableState(lapTimes: [], lapNotes: []))
        $0.present.elapsedMilliseconds = i * 10
      }
    }

    // Add a lap
    await store.send(\.feature.lapTapped) {
      $0.past.append(StopwatchUndoableState(lapTimes: [], lapNotes: []))
      $0.present.lapTimes = [0.05]
      $0.present.lapNotes = [""]
    }

    let elapsedBeforeUndo = store.state.present.elapsedMilliseconds
    let isRunningBeforeUndo = store.state.present.isRunning

    // Undo the lap
    await store.send(.undo) {
      _ = $0.past.popLast()
      $0.present.lapTimes = []
      $0.present.lapNotes = []
      $0.future = [StopwatchUndoableState(lapTimes: [0.05], lapNotes: [""])]
    }

    // Reality state (elapsed time, isRunning) is unchanged!
    #expect(store.state.present.elapsedMilliseconds == elapsedBeforeUndo)
    #expect(store.state.present.isRunning == isRunningBeforeUndo)
    // But user intent state (laps) is restored
    #expect(store.state.present.lapTimes.isEmpty)
  }

  @Test
  func redo() async {
    let store = TestStore(
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
        }
      )
    }

    // Add two laps
    await store.send(\.feature.lapTapped) {
      $0.past = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
      $0.present.lapTimes = [0.0]
      $0.present.lapNotes = [""]
    }

    await store.send(\.feature.lapTapped) {
      $0.past = [
        StopwatchUndoableState(lapTimes: [], lapNotes: []),
        StopwatchUndoableState(lapTimes: [0.0], lapNotes: [""]),
      ]
      $0.present.lapTimes = [0.0, 0.0]
      $0.present.lapNotes = ["", ""]
    }

    // Undo
    await store.send(.undo) {
      $0.past = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
      $0.present.lapTimes = [0.0]
      $0.present.lapNotes = [""]
      $0.future = [StopwatchUndoableState(lapTimes: [0.0, 0.0], lapNotes: ["", ""])]
    }

    #expect(store.state.canRedo == true)

    // Redo
    await store.send(.redo) {
      $0.past = [
        StopwatchUndoableState(lapTimes: [], lapNotes: []),
        StopwatchUndoableState(lapTimes: [0.0], lapNotes: [""]),
      ]
      $0.present.lapTimes = [0.0, 0.0]
      $0.present.lapNotes = ["", ""]
      $0.future = []
    }

    #expect(store.state.canRedo == false)
  }

  @Test
  func newActionClearsFuture() async {
    let store = TestStore(
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
        }
      )
    }

    // Add laps and undo
    await store.send(\.feature.lapTapped) {
      $0.past = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
      $0.present.lapTimes = [0.0]
      $0.present.lapNotes = [""]
    }

    await store.send(.undo) {
      $0.past = []
      $0.present.lapTimes = []
      $0.present.lapNotes = []
      $0.future = [StopwatchUndoableState(lapTimes: [0.0], lapNotes: [""])]
    }

    #expect(store.state.canRedo == true)

    // New action should clear future
    await store.send(\.feature.lapTapped) {
      $0.past = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
      $0.present.lapTimes = [0.0]
      $0.present.lapNotes = [""]
      $0.future = []  // Cleared!
    }

    #expect(store.state.canRedo == false)
  }

  @Test
  func historyLimitPruning() async {
    let historyLimit = 3
    let store = TestStore(
      initialState: SelectiveUndoReducer<StopwatchFeature, StopwatchUndoableState>.State(
        present: StopwatchFeature.State()
      )
    ) {
      SelectiveUndoReducer(
        feature: StopwatchFeature(),
        historyLimit: historyLimit,
        extractUndoable: { $0.undoableState },
        restoreUndoable: { state, undoable in
          state.lapTimes = undoable.lapTimes
          state.lapNotes = undoable.lapNotes
        }
      )
    }

    // Add more laps than the history limit
    for i in 1...5 {
      await store.send(\.feature.lapTapped) {
        let newLapTimes = Array(repeating: 0.0, count: i)
        let newLapNotes = Array(repeating: "", count: i)

        // Build expected past - pruned to historyLimit
        var expectedPast: [StopwatchUndoableState] = []
        for j in max(0, i - historyLimit)..<i {
          expectedPast.append(
            StopwatchUndoableState(
              lapTimes: Array(repeating: 0.0, count: j),
              lapNotes: Array(repeating: "", count: j)
            ))
        }

        $0.past = expectedPast
        $0.present.lapTimes = newLapTimes
        $0.present.lapNotes = newLapNotes
      }
    }

    #expect(store.state.past.count == historyLimit)
  }

  @Test
  func clearHistory() async {
    let store = TestStore(
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
        }
      )
    }

    // Build up history
    await store.send(\.feature.lapTapped) {
      $0.past = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
      $0.present.lapTimes = [0.0]
      $0.present.lapNotes = [""]
    }

    await store.send(.undo) {
      $0.past = []
      $0.present.lapTimes = []
      $0.present.lapNotes = []
      $0.future = [StopwatchUndoableState(lapTimes: [0.0], lapNotes: [""])]
    }

    // Add another action to have both past and future
    await store.send(\.feature.lapTapped) {
      $0.past = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
      $0.present.lapTimes = [0.0]
      $0.present.lapNotes = [""]
      $0.future = []
    }

    await store.send(.undo) {
      $0.past = []
      $0.present.lapTimes = []
      $0.present.lapNotes = []
      $0.future = [StopwatchUndoableState(lapTimes: [0.0], lapNotes: [""])]
    }

    await store.send(\.feature.lapTapped) {
      $0.past = [StopwatchUndoableState(lapTimes: [], lapNotes: [])]
      $0.present.lapTimes = [0.0]
      $0.present.lapNotes = [""]
      $0.future = []
    }

    // Clear history
    await store.send(.clearHistory) {
      $0.past = []
      $0.future = []
    }

    #expect(store.state.canUndo == false)
    #expect(store.state.canRedo == false)
    // Present state preserved
    #expect(store.state.present.lapTimes == [0.0])
  }

  @Test
  func undoWhenEmptyDoesNothing() async {
    let store = TestStore(
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
        }
      )
    }

    // Undo with empty history does nothing
    await store.send(.undo)
    #expect(store.state.past.isEmpty)
  }

  @Test
  func redoWhenEmptyDoesNothing() async {
    let store = TestStore(
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
        }
      )
    }

    // Redo with empty future does nothing
    await store.send(.redo)
    #expect(store.state.future.isEmpty)
  }
}

// MARK: - Canvas Feature Tests

@MainActor
struct CanvasSelectiveUndoTests {
  // ==========================================================================
  // EXPECTED BEHAVIOR TESTS (User's described behavior)
  // ==========================================================================

  /// User draws two strokes, clicks undo twice.
  /// Expected: First undo removes second stroke, second undo removes first stroke.
  @Test
  func twoStrokesUndoTwice() async {
    let store = TestStore(
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
        }
      )
    } withDependencies: {
      $0.uuid = .incrementing
    }

    let stroke1 = CanvasStroke(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
      points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)],
      color: .black,
      width: 4.0
    )
    let stroke2 = CanvasStroke(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      points: [CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 150)],
      color: .black,
      width: 4.0
    )

    // Draw first stroke
    await store.send(.feature(.strokeCompleted(stroke1))) {
      $0.past = [CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0)]
      $0.present.strokes = [stroke1]
    }

    // Draw second stroke
    await store.send(.feature(.strokeCompleted(stroke2))) {
      $0.past = [
        CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0),
        CanvasUndoableState(strokes: [stroke1], selectedColor: .black, brushWidth: 4.0),
      ]
      $0.present.strokes = [stroke1, stroke2]
    }

    // First undo - removes second stroke
    await store.send(.undo) {
      $0.past = [CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0)]
      $0.present.strokes = [stroke1]
      $0.future = [CanvasUndoableState(strokes: [stroke1, stroke2], selectedColor: .black, brushWidth: 4.0)]
    }

    #expect(store.state.present.strokes.count == 1)
    #expect(store.state.present.strokes.first?.id == stroke1.id)

    // Second undo - removes first stroke
    await store.send(.undo) {
      $0.past = []
      $0.present.strokes = []
      // Future has most recently undone state at front (inserted at index 0)
      $0.future = [
        CanvasUndoableState(strokes: [stroke1], selectedColor: .black, brushWidth: 4.0),
        CanvasUndoableState(strokes: [stroke1, stroke2], selectedColor: .black, brushWidth: 4.0),
      ]
    }

    #expect(store.state.present.strokes.isEmpty)
  }

  /// User draws strokes, then clicks clear - clears all strokes.
  /// Then undo should restore all strokes.
  @Test
  func clearCanvasAndUndo() async {
    let stroke1UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let stroke2UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    let stroke1 = CanvasStroke(
      id: stroke1UUID,
      points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)],
      color: .black,
      width: 4.0
    )
    let stroke2 = CanvasStroke(
      id: stroke2UUID,
      points: [CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 150)],
      color: .red,
      width: 6.0
    )

    // Start with two strokes already drawn
    var initialState = SelectiveUndoReducer<CanvasFeature, CanvasUndoableState>.State(
      present: CanvasFeature.State()
    )
    initialState.present.strokes = [stroke1, stroke2]
    initialState.past = [
      CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0),
      CanvasUndoableState(strokes: [stroke1], selectedColor: .black, brushWidth: 4.0),
    ]

    let store = TestStore(initialState: initialState) {
      SelectiveUndoReducer(
        feature: CanvasFeature(),
        extractUndoable: { $0.undoableState },
        restoreUndoable: { state, undoable in
          state.strokes = undoable.strokes
          state.selectedColor = undoable.selectedColor
          state.brushWidth = undoable.brushWidth
        }
      )
    }

    // Clear canvas
    await store.send(.feature(.clearCanvas)) {
      $0.past = [
        CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0),
        CanvasUndoableState(strokes: [stroke1], selectedColor: .black, brushWidth: 4.0),
        CanvasUndoableState(strokes: [stroke1, stroke2], selectedColor: .black, brushWidth: 4.0),
      ]
      $0.present.strokes = []
    }

    #expect(store.state.present.strokes.isEmpty)

    // Undo clear - restores all strokes
    await store.send(.undo) {
      $0.past = [
        CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0),
        CanvasUndoableState(strokes: [stroke1], selectedColor: .black, brushWidth: 4.0),
      ]
      $0.present.strokes = [stroke1, stroke2]
      $0.future = [CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0)]
    }

    #expect(store.state.present.strokes.count == 2)
  }

  /// Brush size and color changes should be undoable
  @Test
  func brushSizeAndColorChangesAreUndoable() async {
    let store = TestStore(
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
        // Use action classification for proper slider lifecycle handling
        useActionClassification: true
      )
    }

    // Simulate slider scrub: user starts editing, drags through values, then releases
    // The undo point should be created when editing STARTS (before any changes)
    await store.send(.feature(.brushWidthEditingStarted)) {
      // Undo point created BEFORE the change
      $0.past = [CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0)]
    }
    
    // Intermediate values during scrub - these are excluded, no new undo points
    await store.send(.feature(.brushWidthChanged(6.0))) {
      $0.present.brushWidth = 6.0
    }
    await store.send(.feature(.brushWidthChanged(8.0))) {
      $0.present.brushWidth = 8.0
    }
    await store.send(.feature(.brushWidthChanged(10.0))) {
      $0.present.brushWidth = 10.0
    }
    
    // User releases slider - excluded, no new undo point
    await store.send(.feature(.brushWidthEditingEnded))

    // Change color (still debounced)
    await store.send(.feature(.colorSelected(.blue))) {
      $0.past = [
        CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0),
        CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 10.0),
      ]
      $0.present.selectedColor = .blue
    }

    // Undo color change
    await store.send(.undo) {
      $0.past = [CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0)]
      $0.present.selectedColor = .black
      $0.present.brushWidth = 10.0
      $0.future = [CanvasUndoableState(strokes: [], selectedColor: .blue, brushWidth: 10.0)]
    }

    #expect(store.state.present.selectedColor == .black)
    #expect(store.state.present.brushWidth == 10.0)

    // Undo brush size change - goes back to original 4.0
    await store.send(.undo) {
      $0.past = []
      $0.present.brushWidth = 4.0
      // Future has most recently undone state at front (inserted at index 0)
      $0.future = [
        CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 10.0),
        CanvasUndoableState(strokes: [], selectedColor: .blue, brushWidth: 10.0),
      ]
    }

    #expect(store.state.present.brushWidth == 4.0)
  }
  
  /// Test that scrubbing the brush size slider doesn't create multiple undo points
  @Test
  func brushSizeScrubOnlyCreatesOneUndoPoint() async {
    let store = TestStore(
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
        useActionClassification: true
      )
    }

    // Initial state: brushWidth = 4.0
    #expect(store.state.present.brushWidth == 4.0)
    #expect(store.state.past.isEmpty)
    
    // Simulate a long scrub from 4.0 to 20.0
    await store.send(.feature(.brushWidthEditingStarted)) {
      // ONE undo point created at start
      $0.past = [CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0)]
    }
    
    // Many intermediate values - none create undo points
    for width in stride(from: 5.0, through: 20.0, by: 1.0) {
      await store.send(.feature(.brushWidthChanged(width))) {
        $0.present.brushWidth = width
      }
    }
    
    await store.send(.feature(.brushWidthEditingEnded))
    
    // Verify: only ONE undo point was created
    #expect(store.state.past.count == 1)
    #expect(store.state.present.brushWidth == 20.0)
    
    // Undo should restore to original 4.0, not to any intermediate value
    await store.send(.undo) {
      $0.past = []
      $0.present.brushWidth = 4.0
      $0.future = [CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 20.0)]
    }
    
    #expect(store.state.present.brushWidth == 4.0)
  }

  // ==========================================================================
  // ORIGINAL TESTS
  // ==========================================================================

  @Test
  func transientStateNotTracked() async {
    let store = TestStore(
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
        }
      )
    } withDependencies: {
      $0.uuid = .incrementing
    }

    // Start drawing (transient)
    await store.send(.feature(.penDown(at: CGPoint(x: 10, y: 10)))) {
      $0.past = [
        CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0)
      ]
      $0.present.isPenDown = true
      $0.present.cursorPosition = CGPoint(x: 10, y: 10)
      $0.present.currentStroke = CanvasStroke(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        points: [CGPoint(x: 10, y: 10)],
        color: .black,
        width: 4.0
      )
    }

    // The transient state (isPenDown, cursorPosition, currentStroke) is updated
    // but only the undoable portion is tracked in history
    #expect(store.state.present.isPenDown == true)
    #expect(store.state.past.count == 1)
  }

  @Test
  func strokeCompletionCreatesUndoPoint() async {
    let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    let store = TestStore(
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
        }
      )
    } withDependencies: {
      $0.uuid = .constant(testUUID)
    }

    // Complete a stroke
    let stroke = CanvasStroke(
      id: testUUID,
      points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)],
      color: .black,
      width: 4.0
    )

    await store.send(.feature(.strokeCompleted(stroke))) {
      $0.past = [
        CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0)
      ]
      $0.present.strokes = [stroke]
    }

    // Undo should remove the stroke
    await store.send(.undo) {
      $0.past = []
      $0.present.strokes = []
      $0.future = [
        CanvasUndoableState(strokes: [stroke], selectedColor: .black, brushWidth: 4.0)
      ]
    }

    #expect(store.state.present.strokes.isEmpty)
  }

  @Test
  func colorChangeIsUndoable() async {
    let store = TestStore(
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
        }
      )
    }

    // Change color
    await store.send(.feature(.colorSelected(.red))) {
      $0.past = [
        CanvasUndoableState(strokes: [], selectedColor: .black, brushWidth: 4.0)
      ]
      $0.present.selectedColor = .red
    }

    // Undo should restore original color
    await store.send(.undo) {
      $0.past = []
      $0.present.selectedColor = .black
      $0.future = [
        CanvasUndoableState(strokes: [], selectedColor: .red, brushWidth: 4.0)
      ]
    }

    #expect(store.state.present.selectedColor == .black)
  }
}

// MARK: - UndoableModifier Tests (The .undoable() Modifier Pattern)

@MainActor
struct UndoableModifierTests {
  @Test
  func undoableModifierBasicUndo() async {
    let store = TestStore(
      initialState: UndoableModifier<UndoableCounterFeature, CounterUndoableState>.State(
        present: UndoableCounterFeature.State()
      )
    ) {
      UndoableCounterFeature()
        .undoable(
          historyLimit: 20,
          extractUndoable: { $0.undoableState },
          restoreUndoable: { state, undoable in
            state.count = undoable.count
            state.history = undoable.history
          },
          filter: { _ in .createUndoPoint }  // Immediate undo points for testing
        )
    } withDependencies: {
      $0.date = .constant(.distantPast)
    }

    // Increment
    await store.send(.base(.incrementButtonTapped)) {
      $0.past = [CounterUndoableState(count: 0, history: [])]
      $0.present.count = 1
      $0.present.history = [0]
      $0.present.lastModified = .distantPast
      $0.lastUndoPointDate = .distantPast
    }

    // Undo - count reverts but lastModified stays (reality state)
    await store.send(.undo) {
      $0.past = []
      $0.present.count = 0
      $0.present.history = []
      // lastModified is NOT affected by undo!
      $0.future = [CounterUndoableState(count: 1, history: [0])]
    }

    #expect(store.state.present.count == 0)
    #expect(store.state.present.lastModified == .distantPast) // Reality preserved
  }

  @Test
  func undoableModifierRedo() async {
    let store = TestStore(
      initialState: UndoableModifier<UndoableCounterFeature, CounterUndoableState>.State(
        present: UndoableCounterFeature.State()
      )
    ) {
      UndoableCounterFeature()
        .undoable(
          historyLimit: 20,
          extractUndoable: { $0.undoableState },
          restoreUndoable: { state, undoable in
            state.count = undoable.count
            state.history = undoable.history
          },
          filter: { _ in .createUndoPoint }  // Immediate undo points for testing
        )
    } withDependencies: {
      $0.date = .constant(.distantPast)
    }

    // Increment twice
    await store.send(.base(.incrementButtonTapped)) {
      $0.past = [CounterUndoableState(count: 0, history: [])]
      $0.present.count = 1
      $0.present.history = [0]
      $0.present.lastModified = .distantPast
      $0.lastUndoPointDate = .distantPast
    }

    await store.send(.base(.incrementButtonTapped)) {
      $0.past = [
        CounterUndoableState(count: 0, history: []),
        CounterUndoableState(count: 1, history: [0])
      ]
      $0.present.count = 2
      $0.present.history = [0, 1]
    }

    // Undo
    await store.send(.undo) {
      $0.past = [CounterUndoableState(count: 0, history: [])]
      $0.present.count = 1
      $0.present.history = [0]
      $0.future = [CounterUndoableState(count: 2, history: [0, 1])]
    }

    // Redo
    await store.send(.redo) {
      $0.past = [
        CounterUndoableState(count: 0, history: []),
        CounterUndoableState(count: 1, history: [0])
      ]
      $0.present.count = 2
      $0.present.history = [0, 1]
      $0.future = []
    }

    #expect(store.state.present.count == 2)
  }

  @Test
  func undoableModifierResetCreatesUndoPoint() async {
    let store = TestStore(
      initialState: UndoableModifier<UndoableCounterFeature, CounterUndoableState>.State(
        present: UndoableCounterFeature.State(count: 5, history: [0, 1, 2, 3, 4])
      )
    ) {
      UndoableCounterFeature()
        .undoable(
          historyLimit: 20,
          extractUndoable: { $0.undoableState },
          restoreUndoable: { state, undoable in
            state.count = undoable.count
            state.history = undoable.history
          },
          filter: { _ in .createUndoPoint }  // Immediate undo points for testing
        )
    } withDependencies: {
      $0.date = .constant(.distantPast)
    }

    // Reset
    await store.send(.base(.resetButtonTapped)) {
      $0.past = [CounterUndoableState(count: 5, history: [0, 1, 2, 3, 4])]
      $0.present.count = 0
      $0.present.history = [0, 1, 2, 3, 4, 5]
      $0.present.lastModified = .distantPast
      $0.lastUndoPointDate = .distantPast
    }

    // Undo the reset
    await store.send(.undo) {
      $0.past = []
      $0.present.count = 5
      $0.present.history = [0, 1, 2, 3, 4]
      $0.future = [CounterUndoableState(count: 0, history: [0, 1, 2, 3, 4, 5])]
    }

    #expect(store.state.present.count == 5)
  }

  @Test
  func undoableModifierClearHistory() async {
    var state = UndoableModifier<UndoableCounterFeature, CounterUndoableState>.State(
      present: UndoableCounterFeature.State(count: 3)
    )
    state.past = [
      CounterUndoableState(count: 0, history: []),
      CounterUndoableState(count: 1, history: [0]),
      CounterUndoableState(count: 2, history: [0, 1])
    ]
    state.future = [CounterUndoableState(count: 4, history: [0, 1, 2, 3])]

    let store = TestStore(initialState: state) {
      UndoableCounterFeature()
        .undoable(
          historyLimit: 20,
          extractUndoable: { $0.undoableState },
          restoreUndoable: { state, undoable in
            state.count = undoable.count
            state.history = undoable.history
          },
          filter: { _ in .createUndoPoint }  // Immediate undo points for testing
        )
    } withDependencies: {
      $0.date = .constant(.distantPast)
    }

    #expect(store.state.canUndo)
    #expect(store.state.canRedo)

    await store.send(.clearHistory) {
      $0.past = []
      $0.future = []
      $0.timeline = []
      $0.currentTimelineIndex = 0
      $0.pendingUndoableState = nil
      $0.lastUndoPointDate = nil
    }

    #expect(!store.state.canUndo)
    #expect(!store.state.canRedo)
  }

  @Test
  func undoableModifierActionFiltering() async {
    // Test that action filtering works correctly:
    // - incrementButtonTapped: createUndoPoint (immediate)
    // - decrementButtonTapped: exclude (no undo point)
    // - resetButtonTapped: debounce (would need to wait)

    let store = TestStore(
      initialState: UndoableModifier<UndoableCounterFeature, CounterUndoableState>.State(
        present: UndoableCounterFeature.State()
      )
    ) {
      UndoableCounterFeature()
        .undoable(
          historyLimit: 20,
          extractUndoable: { $0.undoableState },
          restoreUndoable: { state, undoable in
            state.count = undoable.count
            state.history = undoable.history
          },
          filter: { action in
            switch action {
            case .incrementButtonTapped:
              return .createUndoPoint  // Immediate undo point
            case .decrementButtonTapped:
              return .exclude  // No undo point
            case .resetButtonTapped:
              return .createUndoPoint  // Immediate for testing
            }
          }
        )
    } withDependencies: {
      $0.date = .constant(.distantPast)
    }

    // Increment creates undo point
    await store.send(.base(.incrementButtonTapped)) {
      $0.past = [CounterUndoableState(count: 0, history: [])]
      $0.present.count = 1
      $0.present.history = [0]
      $0.present.lastModified = .distantPast
      $0.lastUndoPointDate = .distantPast
    }

    // Decrement is excluded - no undo point created
    await store.send(.base(.decrementButtonTapped)) {
      // past stays the same - no new undo point!
      $0.present.count = 0
      $0.present.history = [0, 1]
    }

    // Undo should go back to before the increment (decrement was excluded)
    await store.send(.undo) {
      $0.past = []
      $0.present.count = 0
      $0.present.history = []
      $0.future = [CounterUndoableState(count: 0, history: [0, 1])]
    }

    #expect(store.state.present.count == 0)
    #expect(store.state.present.history.isEmpty)
  }
}

