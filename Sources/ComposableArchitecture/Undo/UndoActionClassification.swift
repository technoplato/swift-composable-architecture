// ============================================================================
// MARK: - UndoActionClassification Protocol
// ============================================================================

/// A protocol for actions that can classify their own undo behavior.
///
/// Conform to this protocol to specify how each action should be treated
/// for undo purposes. This is typically done using the ``UndoActions()`` macro
/// along with ``UndoPoint()`` and ``UndoExcluded()`` annotations.
///
/// ## Manual Conformance
///
/// You can manually conform to this protocol:
///
/// ```swift
/// extension Feature.Action: UndoActionClassification {
///   var undoBehavior: UndoActionBehavior {
///     switch self {
///     case .timerTicked, .networkResponse:
///       return .exclude
///     case .deleteItem, .clearAll:
///       return .createUndoPoint
///     default:
///       return .debounce
///     }
///   }
/// }
/// ```
///
/// ## Macro-Based Conformance
///
/// Or use the macros for a more declarative approach:
///
/// ```swift
/// @UndoActions
/// enum Action {
///   @UndoPoint case deleteItem(Item.ID)
///   @UndoExcluded case timerTicked
///   case regularAction  // Debounced by default
/// }
/// ```
public protocol UndoActionClassification {
  /// Returns the undo behavior for this action.
  var undoBehavior: UndoActionBehavior { get }
}

/// Default implementation: all actions are debounced by default.
extension UndoActionClassification {
  public var undoBehavior: UndoActionBehavior { .debounce }
}

// ============================================================================
// MARK: - UndoActionBehavior
// ============================================================================

/// Specifies how an action should be treated for undo purposes.
///
/// Use this enum to classify actions into three categories:
///
/// - ``createUndoPoint``: Significant actions that should always create an
///   immediate undo point (e.g., delete, import, submit)
/// - ``debounce``: Actions that should be coalesced with other rapid actions
///   (e.g., keystrokes, slider adjustments) - this is the default
/// - ``exclude``: Actions that should never create an undo point
///   (e.g., timer ticks, network responses, animations)
public enum UndoActionBehavior: Equatable, Sendable {
  /// Create an undo point immediately.
  ///
  /// Use for significant user actions like delete, import, or submit.
  /// These actions represent clear decision points that users expect
  /// to be able to undo individually.
  case createUndoPoint

  /// Debounce with other actions (default behavior).
  ///
  /// Use for rapid, incremental actions like keystrokes or slider
  /// adjustments. Multiple debounced actions within a short time window
  /// will be coalesced into a single undo point.
  case debounce

  /// Exclude from undo history entirely.
  ///
  /// Use for actions that represent "reality" rather than user intent:
  /// - Timer ticks
  /// - Network responses
  /// - Animation frames
  /// - Transient UI state changes
  ///
  /// These actions should never create undo points because undoing them
  /// would be "lying about reality."
  case exclude
}








