import ComposableArchitecture
import Foundation

/// FoldKit Multiple Counters program identity.
public enum CountersProgram {
  public static let id = "multiple-counters"
  public static let version = 2
  public static let uri = "/counters"
  public static let title = "counters"
}

/// One identified Counter row. Same id shape as FoldKit (`counter-1`).
public struct CounterRow: Equatable, Identifiable, Sendable {
  public var id: String
  public var counter: Counter.State

  public init(id: String, counter: Counter.State = Counter.State()) {
    self.id = id
    self.counter = counter
  }
}

/// forEach of Counter. Replay applies `GotCounterMessage`.
@Reducer
public struct Counters {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var retiredCounterIds: [String]
    public var rows: IdentifiedArrayOf<CounterRow>
    public var navigationTag: String

    public init(
      retiredCounterIds: [String] = [],
      rows: IdentifiedArrayOf<CounterRow> = [
        CounterRow(id: "counter-1"),
        CounterRow(id: "counter-2"),
      ],
      navigationTag: String = "CounterList"
    ) {
      self.retiredCounterIds = retiredCounterIds
      self.rows = rows
      self.navigationTag = navigationTag
    }
  }

  /// FoldKit `GotCounterMessage { counterId, message }`.
  public enum Action: Equatable, Sendable {
    case gotCounterMessage(id: String, Counter.Action)
  }

  public init() {}

  public var body: some Reducer<State, Action> {
    Reduce { state, action in
      apply(&state, action)
      return .none
    }
  }
}

/// Pure Counters update. Replay uses this. It does not run effects.
public func apply(_ state: inout Counters.State, _ action: Counters.Action) {
  switch action {
  case let .gotCounterMessage(id, child):
    guard var row = state.rows[id: id] else { return }
    apply(&row.counter, child)
    state.rows[id: id] = row
  }
}

/// Token `increment:counter-1`.
public func parseCountersToken(_ raw: String) throws -> Counters.Action {
  let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
  guard parts.count == 2,
    let token = CounterToken(rawValue: parts[0].lowercased())
  else {
    throw ReplayTapeError.unknownToken(raw)
  }
  let id = String(parts[1])
  return .gotCounterMessage(id: id, Counter.Action(token: token))
}

public func token(of action: Counters.Action) -> String {
  switch action {
  case let .gotCounterMessage(id, child):
    return "\(child.token.rawValue):\(id)"
  }
}

public func isValid(_ action: Counters.Action, state: Counters.State) -> Bool {
  switch action {
  case let .gotCounterMessage(id, child):
    guard let row = state.rows[id: id] else { return false }
    return isValid(child, state: row.counter)
  }
}

public func countersActions(for state: Counters.State) -> [Counters.Action] {
  state.rows.flatMap { row in
    CounterToken.allCases.map { token in
      Counters.Action.gotCounterMessage(id: row.id, Counter.Action(token: token))
    }
  }
}
