import Foundation

public struct CliExecution<Model: Equatable, Message: Equatable>: Equatable {
  public var initialModel: Model
  public var message: Message?
  public var finalModel: Model
  public var stdout: String

  public init(
    initialModel: Model,
    message: Message?,
    finalModel: Model,
    stdout: String
  ) {
    self.initialModel = initialModel
    self.message = message
    self.finalModel = finalModel
    self.stdout = stdout
  }
}

public struct ReplayExecution<Model: Equatable>: Equatable {
  public var models: [Model]
  public var stdout: String

  public init(models: [Model], stdout: String) {
    self.models = models
    self.stdout = stdout
  }
}

public func executeShow(
  state: Counter.State = Counter.State()
) -> CliExecution<Counter.State, Counter.Action> {
  CliExecution(
    initialModel: state,
    message: nil,
    finalModel: state,
    stdout: renderShow(state)
  )
}

public func executeDo(
  token raw: String,
  state: Counter.State = Counter.State()
) throws -> CliExecution<Counter.State, Counter.Action> {
  guard let token = CounterToken(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
  else {
    throw ReplayTapeError.unknownToken(raw)
  }
  let action = Counter.Action(token: token)
  if !isValid(action, state: state) {
    let stdout = [invalidActionLog(token: token.rawValue, state: state), "", renderShow(state)]
      .joined(separator: "\n")
    return CliExecution(
      initialModel: state,
      message: nil,
      finalModel: state,
      stdout: stdout
    )
  }
  var next = state
  apply(&next, action)
  let stdout = [
    renderReceipt(token: token.rawValue),
    "",
    renderShow(next),
  ].joined(separator: "\n")
  return CliExecution(
    initialModel: state,
    message: action,
    finalModel: next,
    stdout: stdout
  )
}

public func executeReplay(json: String) throws -> ReplayExecution<Counter.State> {
  let tape = try decodeCounterTape(json)
  let frames = (0...tape.transitions.count).map { $0 }
  var models: [Counter.State] = []
  var blocks: [String] = []
  for frame in frames {
    let model = try replayToFrame(tape, frame: frame)
    let message = frame == 0 ? nil : tape.transitions[frame - 1].message
    models.append(model)
    blocks.append(formatReplayFrame(frame: frame, state: model, message: message))
  }
  return ReplayExecution(models: models, stdout: blocks.joined(separator: "\n\n"))
}

public func executeCountersShow(
  state: Counters.State = Counters.State()
) -> CliExecution<Counters.State, Counters.Action> {
  CliExecution(
    initialModel: state,
    message: nil,
    finalModel: state,
    stdout: renderShow(state)
  )
}

public func executeCountersDo(
  token raw: String,
  state: Counters.State = Counters.State()
) throws -> CliExecution<Counters.State, Counters.Action> {
  let action = try parseCountersToken(raw.trimmingCharacters(in: .whitespacesAndNewlines))
  if !isValid(action, state: state) {
    let stdout = [invalidActionLog(token: raw, state: state), "", renderShow(state)]
      .joined(separator: "\n")
    return CliExecution(
      initialModel: state,
      message: nil,
      finalModel: state,
      stdout: stdout
    )
  }
  var next = state
  apply(&next, action)
  let stdout = [
    renderReceipt(token: token(of: action)),
    "",
    renderShow(next),
  ].joined(separator: "\n")
  return CliExecution(
    initialModel: state,
    message: action,
    finalModel: next,
    stdout: stdout
  )
}

public func executeCountersReplay(json: String) throws -> ReplayExecution<Counters.State> {
  let tape = try decodeCountersTape(json)
  let frames = (0...tape.transitions.count).map { $0 }
  var models: [Counters.State] = []
  var blocks: [String] = []
  for frame in frames {
    let model = try replayToFrame(tape, frame: frame)
    let message = frame == 0 ? nil : tape.transitions[frame - 1].message
    models.append(model)
    blocks.append(formatReplayFrame(frame: frame, state: model, message: message))
  }
  return ReplayExecution(models: models, stdout: blocks.joined(separator: "\n\n"))
}

public func readTapeFile(_ path: String) throws -> String {
  do {
    return try String(contentsOfFile: path, encoding: .utf8)
  } catch {
    throw ReplayTapeError.cannotRead(path)
  }
}
