#if canImport(ComposableArchitectureMacros)
  import ComposableArchitectureMacros
  import MacroTesting
  import XCTest

  final class UndoActionMacrosTests: XCTestCase {
    override func invokeTest() {
      withMacroTesting(
        // isRecording: true,
        macros: [
          UndoPointMacro.self,
          UndoExcludedMacro.self,
          UndoActionsMacro.self,
        ]
      ) {
        super.invokeTest()
      }
    }

    // ========================================================================
    // MARK: - @UndoPoint Tests
    // ========================================================================

    func testUndoPointOnEnumCase() {
      assertMacro {
        """
        enum Action {
          @UndoPoint case deleteItem(Item.ID)
        }
        """
      } expansion: {
        """
        enum Action {
          case deleteItem(Item.ID)
        }
        """
      }
    }

    func testUndoPointOnMultipleCases() {
      assertMacro {
        """
        enum Action {
          @UndoPoint case deleteItem(Item.ID)
          @UndoPoint case clearAll
        }
        """
      } expansion: {
        """
        enum Action {
          case deleteItem(Item.ID)
          case clearAll
        }
        """
      }
    }

    // ========================================================================
    // MARK: - @UndoExcluded Tests
    // ========================================================================

    func testUndoExcludedOnEnumCase() {
      assertMacro {
        """
        enum Action {
          @UndoExcluded case timerTicked
        }
        """
      } expansion: {
        """
        enum Action {
          case timerTicked
        }
        """
      }
    }

    func testUndoExcludedOnMultipleCases() {
      assertMacro {
        """
        enum Action {
          @UndoExcluded case timerTicked
          @UndoExcluded case networkResponse(Response)
        }
        """
      } expansion: {
        """
        enum Action {
          case timerTicked
          case networkResponse(Response)
        }
        """
      }
    }

    // ========================================================================
    // MARK: - @UndoActions Tests
    // ========================================================================

    func testUndoActionsGeneratesConformance() {
      assertMacro {
        """
        @UndoActions
        enum Action {
          @UndoPoint case deleteItem(Item.ID)
          @UndoExcluded case timerTicked
          case regularAction
        }
        """
      } expansion: {
        """
        enum Action {
          case deleteItem(Item.ID)
          case timerTicked
          case regularAction
        }

        extension Action: ComposableArchitecture.UndoActionClassification {
          var undoBehavior: ComposableArchitecture.UndoActionBehavior {
            switch self {
            case .deleteItem:
              return .createUndoPoint
            case .timerTicked:
              return .exclude
            default:
              return .debounce
            }
          }
        }
        """
      }
    }

    func testUndoActionsWithOnlyUndoPointCases() {
      assertMacro {
        """
        @UndoActions
        enum Action {
          @UndoPoint case deleteItem(Item.ID)
          @UndoPoint case clearAll
        }
        """
      } expansion: {
        """
        enum Action {
          case deleteItem(Item.ID)
          case clearAll
        }

        extension Action: ComposableArchitecture.UndoActionClassification {
          var undoBehavior: ComposableArchitecture.UndoActionBehavior {
            switch self {
            case .deleteItem, .clearAll:
              return .createUndoPoint
            default:
              return .debounce
            }
          }
        }
        """
      }
    }

    func testUndoActionsWithOnlyExcludedCases() {
      assertMacro {
        """
        @UndoActions
        enum Action {
          @UndoExcluded case timerTicked
          @UndoExcluded case animationFrame
        }
        """
      } expansion: {
        """
        enum Action {
          case timerTicked
          case animationFrame
        }

        extension Action: ComposableArchitecture.UndoActionClassification {
          var undoBehavior: ComposableArchitecture.UndoActionBehavior {
            switch self {
            case .timerTicked, .animationFrame:
              return .exclude
            default:
              return .debounce
            }
          }
        }
        """
      }
    }

    func testUndoActionsWithNoAnnotations() {
      assertMacro {
        """
        @UndoActions
        enum Action {
          case actionA
          case actionB
        }
        """
      } expansion: {
        """
        enum Action {
          case actionA
          case actionB
        }

        extension Action: ComposableArchitecture.UndoActionClassification {
          var undoBehavior: ComposableArchitecture.UndoActionBehavior {
            switch self {
            default:
              return .debounce
            }
          }
        }
        """
      }
    }

    func testUndoActionsWithMixedAnnotations() {
      assertMacro {
        """
        @UndoActions
        enum Action {
          @UndoPoint case deleteItem(Item.ID)
          @UndoPoint case clearAll
          @UndoExcluded case timerTicked
          @UndoExcluded case networkResponse(Response)
          case regularAction
          case anotherAction
        }
        """
      } expansion: {
        """
        enum Action {
          case deleteItem(Item.ID)
          case clearAll
          case timerTicked
          case networkResponse(Response)
          case regularAction
          case anotherAction
        }

        extension Action: ComposableArchitecture.UndoActionClassification {
          var undoBehavior: ComposableArchitecture.UndoActionBehavior {
            switch self {
            case .deleteItem, .clearAll:
              return .createUndoPoint
            case .timerTicked, .networkResponse:
              return .exclude
            default:
              return .debounce
            }
          }
        }
        """
      }
    }

    func testUndoActionsWithAvailability() {
      assertMacro {
        """
        @available(iOS 17, *)
        @UndoActions
        enum Action {
          @UndoPoint case deleteItem
          @UndoExcluded case timerTicked
        }
        """
      } expansion: {
        """
        @available(iOS 17, *)
        enum Action {
          case deleteItem
          case timerTicked
        }

        @available(iOS 17, *) extension Action: ComposableArchitecture.UndoActionClassification {
          var undoBehavior: ComposableArchitecture.UndoActionBehavior {
            switch self {
            case .deleteItem:
              return .createUndoPoint
            case .timerTicked:
              return .exclude
            default:
              return .debounce
            }
          }
        }
        """
      }
    }

    // ========================================================================
    // MARK: - Stopwatch Example (Real-World Test)
    // ========================================================================

    func testStopwatchActionExample() {
      assertMacro {
        """
        @UndoActions
        enum Action {
          // Reality state - excluded from undo
          @UndoExcluded case timerTicked
          @UndoExcluded case startStopTapped

          // User intent - creates undo points
          @UndoPoint case lapTapped
          @UndoPoint case deleteLap(Int)
          @UndoPoint case deleteAllLaps

          // Text editing - debounced by default
          case lapNoteChanged(index: Int, note: String)
        }
        """
      } expansion: {
        """
        enum Action {
          // Reality state - excluded from undo
          case timerTicked
          case startStopTapped

          // User intent - creates undo points
          case lapTapped
          case deleteLap(Int)
          case deleteAllLaps

          // Text editing - debounced by default
          case lapNoteChanged(index: Int, note: String)
        }

        extension Action: ComposableArchitecture.UndoActionClassification {
          var undoBehavior: ComposableArchitecture.UndoActionBehavior {
            switch self {
            case .lapTapped, .deleteLap, .deleteAllLaps:
              return .createUndoPoint
            case .timerTicked, .startStopTapped:
              return .exclude
            default:
              return .debounce
            }
          }
        }
        """
      }
    }

    // ========================================================================
    // MARK: - Canvas Example (Real-World Test)
    // ========================================================================

    func testCanvasActionExample() {
      assertMacro {
        """
        @UndoActions
        enum Action {
          // Transient drawing - excluded from undo
          @UndoExcluded case penDown(at: CGPoint)
          @UndoExcluded case penMoved(to: CGPoint)
          @UndoExcluded case penUp

          // Committed strokes - creates undo points
          @UndoPoint case strokeCompleted(Stroke)
          @UndoPoint case strokeDeleted(Stroke.ID)
          @UndoPoint case clearCanvas

          // Tool changes - debounced
          case colorSelected(Color)
          case brushWidthChanged(CGFloat)
        }
        """
      } expansion: {
        """
        enum Action {
          // Transient drawing - excluded from undo
          case penDown(at: CGPoint)
          case penMoved(to: CGPoint)
          case penUp

          // Committed strokes - creates undo points
          case strokeCompleted(Stroke)
          case strokeDeleted(Stroke.ID)
          case clearCanvas

          // Tool changes - debounced
          case colorSelected(Color)
          case brushWidthChanged(CGFloat)
        }

        extension Action: ComposableArchitecture.UndoActionClassification {
          var undoBehavior: ComposableArchitecture.UndoActionBehavior {
            switch self {
            case .strokeCompleted, .strokeDeleted, .clearCanvas:
              return .createUndoPoint
            case .penDown, .penMoved, .penUp:
              return .exclude
            default:
              return .debounce
            }
          }
        }
        """
      }
    }
  }
#endif








