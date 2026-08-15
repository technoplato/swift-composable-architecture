import ComposableArchitecture
import Testing

@testable import DirCounterCore

@MainActor
struct CounterTests {
  @Test
  func incrementAddsOne() async {
    let store = TestStore(initialState: Counter.State()) {
      Counter()
    }
    await store.send(.increment) {
      $0.count = 1
    }
  }

  @Test
  func decrementPastZeroIsNegative() async {
    let store = TestStore(initialState: Counter.State()) {
      Counter()
    }
    await store.send(.decrement) {
      $0.count = -1
    }
  }

  @Test
  func resetFromNonZeroSetsZero() async {
    let store = TestStore(initialState: Counter.State(count: 99)) {
      Counter()
    }
    await store.send(.reset) {
      $0.count = 0
    }
  }

  @Test
  func resetAtZeroDoesNotChangeCount() {
    var state = Counter.State()
    apply(&state, .reset)
    #expect(state.count == 0)
    #expect(isValid(.reset, state: state) == false)
  }

  @Test
  func tokensMatchFoldKit() throws {
    #expect(Counter.Action.increment.token == .increment)
    #expect(Counter.Action.decrement.token == .decrement)
    #expect(Counter.Action.reset.token == .reset)
    #expect(Counter.Action.increment.foldkitTag == "Increment")
    #expect(try Counter.Action(foldkitTag: "Decrement") == .decrement)
  }

  @Test
  func showThenDoIncrement() throws {
    let shown = executeShow()
    #expect(shown.stdout.contains("uri      /counter"))
    #expect(shown.stdout.contains("count    0"))
    #expect(shown.stdout.contains("valid          false"))

    let incremented = try executeDo(token: "INCREMENT")
    #expect(incremented.message == .increment)
    #expect(incremented.finalModel.count == 1)
    #expect(incremented.stdout.contains("increment sent"))
    #expect(incremented.stdout.contains("count    1"))
  }

  @Test
  func invalidResetAtZero() throws {
    let result = try executeDo(token: "reset")
    #expect(result.message == nil)
    #expect(result.finalModel.count == 0)
    #expect(result.stdout.contains("log  attempted to invoke invalid action reset"))
    #expect(result.stdout.contains("state  count 0"))
  }

  @Test
  func unknownTokenFails() {
    #expect(throws: ReplayTapeError.unknownToken("ClickedIncrement")) {
      try executeDo(token: "ClickedIncrement")
    }
  }
}
