/// Prints IDENTITY, STATE, ACTIONS, and valid. `show` is not a Message.
public func renderShow(_ state: Counter.State) -> String {
  let actions = CounterToken.allCases.map { token in
    renderAction(Counter.Action(token: token), state: state)
  }
  return [
    "IDENTITY",
    identityField("title", CounterProgram.title),
    identityField("uri", CounterProgram.uri),
    "",
    "STATE",
    identityField("count", String(state.count)),
    "",
    "ACTIONS",
    actions.joined(separator: "\n"),
  ].joined(separator: "\n")
}

public func renderShow(_ state: Counters.State) -> String {
  let lines = state.rows.map { row in
    "  \(row.id)    \(row.counter.count)"
  }
  let actions = countersActions(for: state).map { action in
    let valid = isValid(action, state: state) ? "true" : "false"
    return "  \(token(of: action).padding(toLength: 22, withPad: " ", startingAt: 0))\(valid)"
  }
  return [
    "IDENTITY",
    identityField("title", CountersProgram.title),
    identityField("uri", CountersProgram.uri),
    "",
    "STATE",
    lines.joined(separator: "\n"),
    "",
    "VALID",
    actions.joined(separator: "\n"),
  ].joined(separator: "\n")
}

public func renderReceipt(token: String, verb: String = "sent") -> String {
  [
    "\(token) \(verb)",
    receiptField("from", "cli"),
    receiptField("via", "argv"),
    receiptField("command", token),
    receiptField("message", token),
    receiptField("event", eventName(token)),
    receiptField("mutate", mutateLine(token)),
    receiptField("side effects", "(none)"),
    receiptField("tape", "appended"),
    receiptField("link", "offline"),
  ].joined(separator: "\n")
}

public func invalidActionLog(token: String, state: Counter.State) -> String {
  "log  attempted to invoke invalid action \(token)\n     state  count \(state.count)"
}

public func invalidActionLog(token: String, state: Counters.State) -> String {
  let counts = state.rows.map { "\($0.id) \($0.counter.count)" }.joined(separator: " ")
  return "log  attempted to invoke invalid action \(token)\n     state  \(counts)"
}

public func renderScreen(_ state: Counter.State) -> String {
  let buttons: [String]
  if isValid(.reset, state: state) {
    buttons = ["[ - ]", "[ reset ]", "[ + ]"]
  } else {
    buttons = ["[ - ]", "[ + ]"]
  }
  return "\(state.count)\n\(buttons.joined(separator: " "))"
}

public func formatReplayFrame(
  frame: Int,
  state: Counter.State,
  message: Counter.Action?
) -> String {
  let messageLine = message.map { "  \($0.foldkitTag)" } ?? "  (none)"
  let valid = CounterToken.allCases.map { token in
    let action = Counter.Action(token: token)
    let flag = isValid(action, state: state) ? "true" : "false"
    return "  \(token.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0))\(flag)"
  }
  return [
    "FRAME \(frame)",
    "MESSAGE",
    messageLine,
    "STATE",
    "  count    \(state.count)",
    "VALID",
    valid.joined(separator: "\n"),
    "SCREEN",
    renderScreen(state),
  ].joined(separator: "\n")
}

public func formatReplayFrame(
  frame: Int,
  state: Counters.State,
  message: Counters.Action?
) -> String {
  let messageLine: String
  if let message {
    switch message {
    case let .gotCounterMessage(id, child):
      messageLine = "  GotCounterMessage \(id) \(child.foldkitTag)"
    }
  } else {
    messageLine = "  (none)"
  }
  let counts = state.rows.map { "  \($0.id)    \($0.counter.count)" }
  let valid = countersActions(for: state).map { action in
    let flag = isValid(action, state: state) ? "true" : "false"
    return "  \(token(of: action).padding(toLength: 22, withPad: " ", startingAt: 0))\(flag)"
  }
  return [
    "FRAME \(frame)",
    "MESSAGE",
    messageLine,
    "STATE",
    counts.joined(separator: "\n"),
    "VALID",
    valid.joined(separator: "\n"),
  ].joined(separator: "\n")
}

private func renderAction(_ action: Counter.Action, state: Counter.State) -> String {
  let token = action.token.rawValue
  let valid = isValid(action, state: state)
  var lines = [
    "  \(token)",
    actionField("tokens", "[\(token)]"),
    actionField("valid", valid ? "true" : "false"),
  ]
  if let reason = hiddenBecause(action, state: state) {
    lines.append(actionField("hidden", reason))
  }
  return lines.joined(separator: "\n")
}

private func identityField(_ name: String, _ value: String) -> String {
  "  \(name.padding(toLength: 9, withPad: " ", startingAt: 0))\(value)"
}

private func actionField(_ name: String, _ value: String) -> String {
  "    \(name.padding(toLength: 15, withPad: " ", startingAt: 0))\(value)"
}

private func receiptField(_ name: String, _ value: String) -> String {
  "  \(name.padding(toLength: 15, withPad: " ", startingAt: 0))\(value)"
}

private func eventName(_ token: String) -> String {
  switch token {
  case "increment":
    return "incremented"
  case "decrement":
    return "decremented"
  default:
    return token
  }
}

private func mutateLine(_ token: String) -> String {
  switch token {
  case "increment":
    return "count = count + 1"
  case "decrement":
    return "count = count - 1"
  case "reset":
    return "count = 0"
  default:
    return ""
  }
}
