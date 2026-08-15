import ComposableArchitecture
import Foundation

/// FoldKit Counter program identity.
public enum CounterProgram {
  public static let id = "counter"
  public static let version = 2
  public static let uri = "/counter"
  public static let title = "counter"
}

/// CLI token shared with FoldKit: increment, decrement, reset.
public enum CounterToken: String, CaseIterable, Sendable {
  case increment
  case decrement
  case reset
}

/// Portable Counter. Same Messages as FoldKit. update stays pure.
@Reducer
public struct Counter {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var count: Int

    public init(count: Int = 0) {
      self.count = count
    }
  }

  public enum Action: Equatable, Sendable {
    case increment
    case decrement
    case reset
  }

  public init() {}

  public var body: some Reducer<State, Action> {
    Reduce { state, action in
      apply(&state, action)
      return .none
    }
  }
}

extension Counter.Action {
  /// FoldKit Message `_tag`.
  public var foldkitTag: String {
    switch self {
    case .increment:
      return "Increment"
    case .decrement:
      return "Decrement"
    case .reset:
      return "Reset"
    }
  }

  /// CLI token.
  public var token: CounterToken {
    switch self {
    case .increment:
      return .increment
    case .decrement:
      return .decrement
    case .reset:
      return .reset
    }
  }

  public init(token: CounterToken) {
    switch token {
    case .increment:
      self = .increment
    case .decrement:
      self = .decrement
    case .reset:
      self = .reset
    }
  }

  public init(foldkitTag: String) throws {
    switch foldkitTag {
    case "Increment":
      self = .increment
    case "Decrement":
      self = .decrement
    case "Reset":
      self = .reset
    default:
      throw ReplayTapeError.unknownMessage(foldkitTag)
    }
  }
}

/// Pure Counter update. Replay uses this. It does not run effects.
public func apply(_ state: inout Counter.State, _ action: Counter.Action) {
  switch action {
  case .increment:
    state.count += 1
  case .decrement:
    state.count -= 1
  case .reset:
    if state.count != 0 {
      state.count = 0
    }
  }
}

/// FoldKit `valid`. Reset is invalid when count is 0.
public func isValid(_ action: Counter.Action, state: Counter.State) -> Bool {
  switch action {
  case .increment, .decrement:
    return true
  case .reset:
    return state.count != 0
  }
}

/// FoldKit `hiddenBecause` for reset.
public func hiddenBecause(_ action: Counter.Action, state: Counter.State) -> String? {
  switch action {
  case .reset where state.count == 0:
    return "count is already 0"
  case .increment, .decrement, .reset:
    return nil
  }
}
