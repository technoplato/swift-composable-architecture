import Foundation
import Testing

@testable import DirCounterCore

struct ReplayTapeTests {
  @Test
  func replaysFoldKitCounterTape() throws {
    let json = try String(contentsOfFile: fixture("counter-increment-decrement-reset.json"))
    let execution = try executeReplay(json: json)

    #expect(execution.models.map(\.count) == [0, 1, 2, 1, 0])
    #expect(execution.stdout.contains("FRAME 0"))
    #expect(execution.stdout.contains("FRAME 4"))
    #expect(execution.stdout.contains("Increment"))
    #expect(execution.stdout.contains("Decrement"))
    #expect(execution.stdout.contains("Reset"))
    #expect(execution.stdout.contains("count    0"))
    #expect(execution.stdout.contains("count    2"))
    #expect(execution.stdout.contains("increment   true"))
    #expect(execution.stdout.contains("reset       false"))
    #expect(execution.stdout.contains("reset       true"))
    #expect(execution.stdout.contains("[ reset ]"))
  }

  @Test
  func rejectsWrongProgramId() {
    let json = """
      {"formatVersion":1,"programId":"other","programVersion":2,"initialModel":{"count":0},"initialCommands":[],"transitions":[],"runtimeEvents":[]}
      """
    #expect(throws: ReplayTapeError.incompatibleProgram(expected: "counter", actual: "other")) {
      try decodeCounterTape(json)
    }
  }

  @Test
  func replayDoesNotExecuteCommands() throws {
    let json = """
      {"formatVersion":1,"programId":"counter","programVersion":2,"initialModel":{"count":4},"initialCommands":[{"name":"FetchFact"}],"transitions":[{"sequence":1,"message":{"_tag":"Decrement"},"source":{"_tag":"Host"},"isOperationSettled":true,"commands":[{"name":"FetchFact"}],"timestamp":0}],"runtimeEvents":[]}
      """
    let model = try replayToFrame(decodeCounterTape(json), frame: 1)
    #expect(model.count == 3)
  }
}

struct CountersReplayTests {
  @Test
  func replaysFoldKitCountersTape() throws {
    let json = try String(contentsOfFile: fixture("counters-increment-decrement-reset.json"))
    let execution = try executeCountersReplay(json: json)

    #expect(execution.models.first?.rows[id: "counter-1"]?.counter.count == 0)
    #expect(execution.models[1].rows[id: "counter-1"]?.counter.count == 1)
    #expect(execution.models[2].rows[id: "counter-1"]?.counter.count == 2)
    #expect(execution.models[3].rows[id: "counter-2"]?.counter.count == -1)
    #expect(execution.models[4].rows[id: "counter-1"]?.counter.count == 0)
    #expect(execution.stdout.contains("GotCounterMessage"))
    #expect(execution.stdout.contains("increment:counter-1   true"))
    #expect(execution.stdout.contains("reset:counter-1       false"))
  }

  @Test
  func countersTokenDoIncrement() throws {
    let result = try executeCountersDo(token: "increment:counter-1")
    #expect(result.finalModel.rows[id: "counter-1"]?.counter.count == 1)
    #expect(result.finalModel.rows[id: "counter-2"]?.counter.count == 0)
    #expect(result.stdout.contains("increment:counter-1 sent"))
  }

  @Test
  func countersResetAtZeroIsInvalid() throws {
    let result = try executeCountersDo(token: "reset:counter-1")
    #expect(result.message == nil)
    #expect(result.stdout.contains("invalid action reset:counter-1"))
  }
}

private func fixture(_ name: String) -> String {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")
    .appendingPathComponent(name)
    .path
}
