import ComposableArchitecture
import Foundation
import Testing

@testable import SwiftUICaseStudies

@MainActor
struct UndoReducerTests {
  @Test
  func featureActionAddsToHistory() async {
    let store = TestStore(
      initialState: UndoReducer<Counter>.State(present: Counter.State())
    ) {
      UndoReducer(feature: Counter())
    }

    // Initial state: count = 0, no history
    #expect(store.state.present.count == 0)
    #expect(store.state.past.isEmpty)
    #expect(store.state.future.isEmpty)

    // Increment should snapshot current state to past
    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0)]
      $0.present.count = 1
    }

    #expect(store.state.canUndo == true)
    #expect(store.state.canRedo == false)

    // Another increment
    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0), Counter.State(count: 1)]
      $0.present.count = 2
    }

    #expect(store.state.past.count == 2)
  }

  @Test
  func undo() async {
    let store = TestStore(
      initialState: UndoReducer<Counter>.State(present: Counter.State())
    ) {
      UndoReducer(feature: Counter())
    }

    // Build up some history
    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0)]
      $0.present.count = 1
    }

    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0), Counter.State(count: 1)]
      $0.present.count = 2
    }

    // Now undo - should restore previous state and move current to future
    await store.send(.undo) {
      $0.past = [Counter.State(count: 0)]
      $0.present.count = 1
      $0.future = [Counter.State(count: 2)]
    }

    #expect(store.state.canUndo == true)
    #expect(store.state.canRedo == true)

    // Undo again
    await store.send(.undo) {
      $0.past = []
      $0.present.count = 0
      $0.future = [Counter.State(count: 1), Counter.State(count: 2)]
    }

    #expect(store.state.canUndo == false)
    #expect(store.state.canRedo == true)

    // Undo when past is empty should do nothing
    await store.send(.undo)
  }

  @Test
  func redo() async {
    let store = TestStore(
      initialState: UndoReducer<Counter>.State(present: Counter.State())
    ) {
      UndoReducer(feature: Counter())
    }

    // Build history and undo
    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0)]
      $0.present.count = 1
    }

    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0), Counter.State(count: 1)]
      $0.present.count = 2
    }

    await store.send(.undo) {
      $0.past = [Counter.State(count: 0)]
      $0.present.count = 1
      $0.future = [Counter.State(count: 2)]
    }

    // Redo - should restore future state and move current to past
    await store.send(.redo) {
      $0.past = [Counter.State(count: 0), Counter.State(count: 1)]
      $0.present.count = 2
      $0.future = []
    }

    #expect(store.state.canUndo == true)
    #expect(store.state.canRedo == false)

    // Redo when future is empty should do nothing
    await store.send(.redo)
  }

  @Test
  func undoRedoSequence() async {
    let store = TestStore(
      initialState: UndoReducer<Counter>.State(present: Counter.State())
    ) {
      UndoReducer(feature: Counter())
    }

    // Increment 3 times: 0 -> 1 -> 2 -> 3
    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0)]
      $0.present.count = 1
    }

    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0), Counter.State(count: 1)]
      $0.present.count = 2
    }

    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0), Counter.State(count: 1), Counter.State(count: 2)]
      $0.present.count = 3
    }

    // Undo twice: 3 -> 2 -> 1
    await store.send(.undo) {
      $0.past = [Counter.State(count: 0), Counter.State(count: 1)]
      $0.present.count = 2
      $0.future = [Counter.State(count: 3)]
    }

    await store.send(.undo) {
      $0.past = [Counter.State(count: 0)]
      $0.present.count = 1
      $0.future = [Counter.State(count: 2), Counter.State(count: 3)]
    }

    // Redo once: 1 -> 2
    await store.send(.redo) {
      $0.past = [Counter.State(count: 0), Counter.State(count: 1)]
      $0.present.count = 2
      $0.future = [Counter.State(count: 3)]
    }

    // New action should clear future and create new timeline
    await store.send(\.feature.decrementButtonTapped) {
      $0.past = [Counter.State(count: 0), Counter.State(count: 1), Counter.State(count: 2)]
      $0.present.count = 1
      $0.future = []  // Future cleared!
    }

    #expect(store.state.canRedo == false)
    #expect(store.state.past.count == 3)
  }

  @Test
  func historyLimitPruning() async {
    // Create reducer with small history limit for testing
    let historyLimit = 3
    let store = TestStore(
      initialState: UndoReducer<Counter>.State(present: Counter.State())
    ) {
      UndoReducer(feature: Counter(), historyLimit: historyLimit)
    }

    // Increment 5 times - should only keep last 3 in history
    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0)]
      $0.present.count = 1
    }

    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0), Counter.State(count: 1)]
      $0.present.count = 2
    }

    await store.send(\.feature.incrementButtonTapped) {
      $0.past = [Counter.State(count: 0), Counter.State(count: 1), Counter.State(count: 2)]
      $0.present.count = 3
    }

    // 4th increment - should prune oldest entry
    await store.send(\.feature.incrementButtonTapped) {
      // count=0 is pruned, keeping count=1, count=2, count=3
      $0.past = [Counter.State(count: 1), Counter.State(count: 2), Counter.State(count: 3)]
      $0.present.count = 4
    }

    #expect(store.state.past.count == historyLimit)

    // 5th increment - continues pruning
    await store.send(\.feature.incrementButtonTapped) {
      // count=1 is pruned, keeping count=2, count=3, count=4
      $0.past = [Counter.State(count: 2), Counter.State(count: 3), Counter.State(count: 4)]
      $0.present.count = 5
    }

    #expect(store.state.past.count == historyLimit)
    #expect(store.state.past.first?.count == 2)  // Oldest is count=2
    #expect(store.state.past.last?.count == 4)   // Newest is count=4
  }
}

