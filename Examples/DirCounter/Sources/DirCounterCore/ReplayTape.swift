import ComposableArchitecture
import Foundation

public struct CommandRecord: Equatable, Sendable {
  public var name: String
  public var args: [String: String]

  public init(name: String, args: [String: String] = [:]) {
    self.name = name
    self.args = args
  }
}

public struct RuntimeEvent: Equatable, Sendable {
  public var name: String
  public var afterFrame: Int
  public var timestamp: Double

  public init(name: String, afterFrame: Int, timestamp: Double) {
    self.name = name
    self.afterFrame = afterFrame
    self.timestamp = timestamp
  }
}

public struct ReplayTransition<Message: Equatable & Sendable>: Equatable, Sendable {
  public var sequence: Int
  public var message: Message
  public var sourceTag: String
  public var isOperationSettled: Bool
  public var commands: [CommandRecord]
  public var timestamp: Double
  public var operationId: Int?

  public init(
    sequence: Int,
    message: Message,
    sourceTag: String,
    isOperationSettled: Bool,
    commands: [CommandRecord],
    timestamp: Double,
    operationId: Int? = nil
  ) {
    self.sequence = sequence
    self.message = message
    self.sourceTag = sourceTag
    self.isOperationSettled = isOperationSettled
    self.commands = commands
    self.timestamp = timestamp
    self.operationId = operationId
  }
}

/// FoldKit replay tape. formatVersion 1.
public struct ReplayTape<Message: Equatable & Sendable, Model: Equatable & Sendable>: Equatable,
  Sendable
{
  public var formatVersion: Int
  public var programId: String
  public var programVersion: Int
  public var initialModel: Model
  public var initialCommands: [CommandRecord]
  public var transitions: [ReplayTransition<Message>]
  public var runtimeEvents: [RuntimeEvent]

  public init(
    formatVersion: Int = 1,
    programId: String,
    programVersion: Int,
    initialModel: Model,
    initialCommands: [CommandRecord] = [],
    transitions: [ReplayTransition<Message>] = [],
    runtimeEvents: [RuntimeEvent] = []
  ) {
    self.formatVersion = formatVersion
    self.programId = programId
    self.programVersion = programVersion
    self.initialModel = initialModel
    self.initialCommands = initialCommands
    self.transitions = transitions
    self.runtimeEvents = runtimeEvents
  }
}

public enum ReplayTapeError: Error, Equatable, CustomStringConvertible, Sendable {
  case notJSON
  case invalidHeader
  case unsupportedFormat(Int)
  case incompatibleProgram(expected: String, actual: String)
  case incompatibleVersion(programId: String, expected: Int, actual: Int)
  case invalidModel(String)
  case invalidMessage(String)
  case unknownMessage(String)
  case unknownToken(String)
  case frameOutOfRange(frame: Int, maximum: Int)
  case cannotRead(String)

  public var description: String {
    switch self {
    case .notJSON:
      return "The replay tape is not valid JSON."
    case .invalidHeader:
      return "The replay tape header is invalid."
    case .unsupportedFormat(let version):
      return "Unsupported replay tape format \(version)."
    case .incompatibleProgram(let expected, let actual):
      return "Tape program is \(actual). Expected \(expected)."
    case .incompatibleVersion(let programId, let expected, let actual):
      return
        "Tape \(programId) version \(actual) does not match \(expected)."
    case .invalidModel(let detail):
      return "The initial Model is invalid. \(detail)"
    case .invalidMessage(let detail):
      return "A replay Message is invalid. \(detail)"
    case .unknownMessage(let tag):
      return "Unknown Message \"\(tag)\"."
    case .unknownToken(let token):
      return "Unknown action \"\(token)\". Use increment, decrement, or reset."
    case .frameOutOfRange(let frame, let maximum):
      return "Tape frame \(frame) is out of range. Maximum is \(maximum)."
    case .cannotRead(let path):
      return "Cannot read tape at \(path)."
    }
  }
}

public func decodeCounterTape(_ json: String) throws -> ReplayTape<Counter.Action, Counter.State> {
  let root = try parseTapeRoot(
    json,
    expectedProgramId: CounterProgram.id,
    expectedProgramVersion: CounterProgram.version
  )
  return ReplayTape(
    formatVersion: root.formatVersion,
    programId: root.programId,
    programVersion: root.programVersion,
    initialModel: try decodeCounterModel(root.initialModel),
    initialCommands: root.initialCommands,
    transitions: try root.transitions.map { encoded in
      ReplayTransition(
        sequence: encoded.sequence,
        message: try decodeCounterMessage(encoded.message),
        sourceTag: encoded.sourceTag,
        isOperationSettled: encoded.isOperationSettled,
        commands: encoded.commands,
        timestamp: encoded.timestamp,
        operationId: encoded.operationId
      )
    },
    runtimeEvents: root.runtimeEvents
  )
}

public func decodeCountersTape(_ json: String) throws -> ReplayTape<
  Counters.Action, Counters.State
> {
  let root = try parseTapeRoot(
    json,
    expectedProgramId: CountersProgram.id,
    expectedProgramVersion: CountersProgram.version
  )
  return ReplayTape(
    formatVersion: root.formatVersion,
    programId: root.programId,
    programVersion: root.programVersion,
    initialModel: try decodeCountersModel(root.initialModel),
    initialCommands: root.initialCommands,
    transitions: try root.transitions.map { encoded in
      ReplayTransition(
        sequence: encoded.sequence,
        message: try decodeCountersMessage(encoded.message),
        sourceTag: encoded.sourceTag,
        isOperationSettled: encoded.isOperationSettled,
        commands: encoded.commands,
        timestamp: encoded.timestamp,
        operationId: encoded.operationId
      )
    },
    runtimeEvents: root.runtimeEvents
  )
}

/// Reconstructs Model at a frame. It does not run historical effects.
public func replayToFrame(
  _ tape: ReplayTape<Counter.Action, Counter.State>,
  frame: Int
) throws -> Counter.State {
  try replay(tape, frame: frame, apply: apply)
}

/// Reconstructs Model at a frame. It does not run historical effects.
public func replayToFrame(
  _ tape: ReplayTape<Counters.Action, Counters.State>,
  frame: Int
) throws -> Counters.State {
  try replay(tape, frame: frame, apply: apply)
}

private func replay<Message: Equatable & Sendable, Model: Equatable & Sendable>(
  _ tape: ReplayTape<Message, Model>,
  frame: Int,
  apply: (inout Model, Message) -> Void
) throws -> Model {
  guard frame >= 0, frame <= tape.transitions.count else {
    throw ReplayTapeError.frameOutOfRange(
      frame: frame,
      maximum: tape.transitions.count
    )
  }
  var model = tape.initialModel
  for transition in tape.transitions.prefix(frame) {
    apply(&model, transition.message)
  }
  return model
}

func decodeCounterMessage(_ json: Any) throws -> Counter.Action {
  guard let object = json as? [String: Any], let tag = object["_tag"] as? String else {
    throw ReplayTapeError.invalidMessage("Expected { \"_tag\": \"Increment\" }.")
  }
  return try Counter.Action(foldkitTag: tag)
}

func decodeCountersMessage(_ json: Any) throws -> Counters.Action {
  guard let object = json as? [String: Any], let tag = object["_tag"] as? String else {
    throw ReplayTapeError.invalidMessage("Expected a tagged Message.")
  }
  switch tag {
  case "GotCounterMessage":
    guard let id = object["counterId"] as? String else {
      throw ReplayTapeError.invalidMessage("GotCounterMessage is missing counterId.")
    }
    guard let childJSON = object["message"] else {
      throw ReplayTapeError.invalidMessage("GotCounterMessage is missing message.")
    }
    return .gotCounterMessage(id: id, try decodeCounterMessage(childJSON))
  default:
    throw ReplayTapeError.unknownMessage(tag)
  }
}

func decodeCounterModel(_ json: Any) throws -> Counter.State {
  guard let object = json as? [String: Any] else {
    throw ReplayTapeError.invalidModel("Expected { \"count\": number }.")
  }
  return Counter.State(count: try intValue(object["count"], field: "count"))
}

func decodeCountersModel(_ json: Any) throws -> Counters.State {
  guard let object = json as? [String: Any] else {
    throw ReplayTapeError.invalidModel("Expected a Multiple Counters Model.")
  }
  let retired = (object["retiredCounterIds"] as? [Any] ?? []).compactMap { $0 as? String }
  guard let rowJSON = object["rows"] as? [Any] else {
    throw ReplayTapeError.invalidModel("Expected rows.")
  }
  let rows = try IdentifiedArrayOf(
    uniqueElements: rowJSON.map { item -> CounterRow in
      guard let row = item as? [String: Any], let id = row["id"] as? String else {
        throw ReplayTapeError.invalidModel("Each row needs id.")
      }
      let counter = try decodeCounterModel(row["counter"] ?? ["count": 0])
      return CounterRow(id: id, counter: counter)
    }
  )
  let navigationTag =
    ((object["navigation"] as? [String: Any])?["_tag"] as? String) ?? "CounterList"
  return Counters.State(
    retiredCounterIds: retired,
    rows: rows,
    navigationTag: navigationTag
  )
}

struct EncodedTapeRoot {
  var formatVersion: Int
  var programId: String
  var programVersion: Int
  var initialModel: Any
  var initialCommands: [CommandRecord]
  var transitions: [EncodedTransition]
  var runtimeEvents: [RuntimeEvent]
}

struct EncodedTransition {
  var sequence: Int
  var message: Any
  var sourceTag: String
  var isOperationSettled: Bool
  var commands: [CommandRecord]
  var timestamp: Double
  var operationId: Int?
}

func parseTapeRoot(
  _ json: String,
  expectedProgramId: String,
  expectedProgramVersion: Int
) throws -> EncodedTapeRoot {
  guard let data = json.data(using: .utf8) else {
    throw ReplayTapeError.notJSON
  }
  let parsed: Any
  do {
    parsed = try JSONSerialization.jsonObject(with: data)
  } catch {
    throw ReplayTapeError.notJSON
  }
  guard let object = parsed as? [String: Any] else {
    throw ReplayTapeError.invalidHeader
  }
  guard let formatVersion = object["formatVersion"] as? Int else {
    throw ReplayTapeError.invalidHeader
  }
  guard formatVersion == 1 else {
    throw ReplayTapeError.unsupportedFormat(formatVersion)
  }
  guard let programId = object["programId"] as? String,
    let programVersion = object["programVersion"] as? Int
  else {
    throw ReplayTapeError.invalidHeader
  }
  if programId != expectedProgramId {
    throw ReplayTapeError.incompatibleProgram(
      expected: expectedProgramId,
      actual: programId
    )
  }
  if programVersion != expectedProgramVersion {
    throw ReplayTapeError.incompatibleVersion(
      programId: programId,
      expected: expectedProgramVersion,
      actual: programVersion
    )
  }
  guard let initialModel = object["initialModel"] else {
    throw ReplayTapeError.invalidModel("initialModel is missing.")
  }
  let commandJSON = object["initialCommands"] as? [Any] ?? []
  let transitionJSON = object["transitions"] as? [Any] ?? []
  let eventJSON = object["runtimeEvents"] as? [Any] ?? []
  return EncodedTapeRoot(
    formatVersion: formatVersion,
    programId: programId,
    programVersion: programVersion,
    initialModel: initialModel,
    initialCommands: try commandJSON.map(decodeCommandRecord),
    transitions: try transitionJSON.map(decodeEncodedTransition),
    runtimeEvents: try eventJSON.map(decodeRuntimeEvent)
  )
}

private func decodeCommandRecord(_ json: Any) throws -> CommandRecord {
  guard let object = json as? [String: Any], let name = object["name"] as? String else {
    throw ReplayTapeError.invalidMessage("Command record needs name.")
  }
  return CommandRecord(name: name)
}

private func decodeEncodedTransition(_ json: Any) throws -> EncodedTransition {
  guard let object = json as? [String: Any],
    let sequence = object["sequence"] as? Int,
    let message = object["message"],
    let settled = object["isOperationSettled"] as? Bool
  else {
    throw ReplayTapeError.invalidMessage("A transition is missing required fields.")
  }
  let sourceTag = ((object["source"] as? [String: Any])?["_tag"] as? String) ?? "Host"
  let commands = try (object["commands"] as? [Any] ?? []).map(decodeCommandRecord)
  return EncodedTransition(
    sequence: sequence,
    message: message,
    sourceTag: sourceTag,
    isOperationSettled: settled,
    commands: commands,
    timestamp: numberValue(object["timestamp"]),
    operationId: object["operationId"] as? Int
  )
}

private func decodeRuntimeEvent(_ json: Any) throws -> RuntimeEvent {
  guard let object = json as? [String: Any],
    let name = object["name"] as? String,
    let afterFrame = object["afterFrame"] as? Int
  else {
    throw ReplayTapeError.invalidMessage("A runtime event is invalid.")
  }
  return RuntimeEvent(
    name: name,
    afterFrame: afterFrame,
    timestamp: numberValue(object["timestamp"])
  )
}

private func intValue(_ json: Any?, field: String) throws -> Int {
  if let value = json as? Int {
    return value
  }
  if let value = json as? Double {
    return Int(value)
  }
  if let value = json as? NSNumber {
    return value.intValue
  }
  throw ReplayTapeError.invalidModel("\(field) must be a number.")
}

private func numberValue(_ json: Any?) -> Double {
  if let value = json as? Double {
    return value
  }
  if let value = json as? Int {
    return Double(value)
  }
  if let value = json as? NSNumber {
    return value.doubleValue
  }
  return 0
}
