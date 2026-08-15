import DirCounterCore
import Foundation

enum Exit: Int32 {
  case ok = 0
  case usage = 2
}

func fail(_ message: String, status: Exit = .usage) -> Never {
  fputs(message + "\n", stderr)
  exit(status.rawValue)
}

func printStdout(_ text: String) {
  print(text)
}

let args = Array(CommandLine.arguments.dropFirst())

func tapePath(from args: [String]) -> String {
  if let index = args.firstIndex(of: "--tape"), args.indices.contains(index + 1) {
    return args[index + 1]
  }
  fail("replay needs --tape <path>.")
}

do {
  switch args.first {
  case nil, "--help", "-h":
    printStdout(
      """
      dir-counter show
      dir-counter do increment|decrement|reset
      dir-counter replay --tape <path>
      dir-counter counters show
      dir-counter counters do increment:counter-1
      dir-counter counters replay --tape <path>
      """
    )
  case "show":
    printStdout(executeShow().stdout)
  case "do":
    guard args.count == 2 else {
      fail("Send one token. Use increment, decrement, or reset.")
    }
    printStdout(try executeDo(token: args[1]).stdout)
  case "replay":
    let json = try readTapeFile(tapePath(from: args))
    printStdout(try executeReplay(json: json).stdout)
  case "counters":
    let rest = Array(args.dropFirst())
    switch rest.first {
    case "show":
      printStdout(executeCountersShow().stdout)
    case "do", "run":
      guard rest.count == 2 else {
        fail("Send one token. Use increment:counter-1.")
      }
      printStdout(try executeCountersDo(token: rest[1]).stdout)
    case "replay":
      let json = try readTapeFile(tapePath(from: rest))
      printStdout(try executeCountersReplay(json: json).stdout)
    default:
      fail("Unknown counters command. Use show, do, or replay.")
    }
  default:
    fail("Unknown command. Use show, do, replay, or counters.")
  }
} catch {
  fail(String(describing: error))
}
