import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// ============================================================================
// MARK: - UndoPointMacro
// ============================================================================

/// A peer macro that marks an enum case as always creating an undo point.
///
/// This macro is used to annotate action cases that represent significant user
/// decisions that should always create an immediate undo point.
///
/// Usage:
/// ```swift
/// enum Action {
///   @UndoPoint case deleteItem(Item.ID)
///   @UndoPoint case clearAll
/// }
/// ```
///
/// The macro itself doesn't generate any code - it just marks the case for
/// the `@UndoActions` macro to read when generating the `UndoActionClassification`
/// conformance.
public enum UndoPointMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // Validate that this is applied to an enum case
    guard declaration.is(EnumCaseDeclSyntax.self) else {
      context.diagnose(
        Diagnostic(
          node: node,
          message: MacroExpansionErrorMessage(
            "'@UndoPoint' can only be applied to enum cases"
          )
        )
      )
      return []
    }
    // No code generation - this is a marker macro
    return []
  }
}

// ============================================================================
// MARK: - UndoExcludedMacro
// ============================================================================

/// A peer macro that marks an enum case as excluded from undo history.
///
/// This macro is used to annotate action cases that should never create an
/// undo point, such as timer ticks, network responses, or transient UI state.
///
/// Usage:
/// ```swift
/// enum Action {
///   @UndoExcluded case timerTicked
///   @UndoExcluded case networkResponse(Response)
/// }
/// ```
///
/// The macro itself doesn't generate any code - it just marks the case for
/// the `@UndoActions` macro to read when generating the `UndoActionClassification`
/// conformance.
public enum UndoExcludedMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // Validate that this is applied to an enum case
    guard declaration.is(EnumCaseDeclSyntax.self) else {
      context.diagnose(
        Diagnostic(
          node: node,
          message: MacroExpansionErrorMessage(
            "'@UndoExcluded' can only be applied to enum cases"
          )
        )
      )
      return []
    }
    // No code generation - this is a marker macro
    return []
  }
}

// ============================================================================
// MARK: - UndoActionsMacro
// ============================================================================

/// An extension macro that generates `UndoActionClassification` conformance for an enum.
///
/// This macro reads `@UndoPoint` and `@UndoExcluded` annotations on enum cases
/// and generates a switch statement that returns the appropriate `UndoActionBehavior`.
///
/// Usage:
/// ```swift
/// @UndoActions
/// enum Action {
///   @UndoPoint case deleteItem(Item.ID)
///   @UndoExcluded case timerTicked
///   case regularAction  // Debounced by default
/// }
/// ```
///
/// Generates:
/// ```swift
/// extension Action: UndoActionClassification {
///   var undoBehavior: UndoActionBehavior {
///     switch self {
///     case .deleteItem:
///       return .createUndoPoint
///     case .timerTicked:
///       return .exclude
///     default:
///       return .debounce
///     }
///   }
/// }
/// ```
public struct UndoActionsMacro: ExtensionMacro {
  public static func expansion<D: DeclGroupSyntax, T: TypeSyntaxProtocol, C: MacroExpansionContext>(
    of node: AttributeSyntax,
    attachedTo declaration: D,
    providingExtensionsOf type: T,
    conformingTo protocols: [TypeSyntax],
    in context: C
  ) throws -> [ExtensionDeclSyntax] {
    // Ensure we're attached to an enum
    guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
      context.diagnose(
        Diagnostic(
          node: node,
          message: MacroExpansionErrorMessage(
            "'@UndoActions' can only be applied to enums"
          )
        )
      )
      return []
    }

    // Collect cases with their annotations
    var undoPointCases: [String] = []
    var excludedCases: [String] = []
    var hasDefaultCases = false

    for member in enumDecl.memberBlock.members {
      guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else {
        continue
      }

      let hasUndoPoint = caseDecl.attributes.contains { attr in
        if case let .attribute(attribute) = attr {
          return attribute.attributeName.trimmedDescription == "UndoPoint"
        }
        return false
      }

      let hasUndoExcluded = caseDecl.attributes.contains { attr in
        if case let .attribute(attribute) = attr {
          return attribute.attributeName.trimmedDescription == "UndoExcluded"
        }
        return false
      }

      for element in caseDecl.elements {
        let caseName = element.name.text
        if hasUndoPoint {
          undoPointCases.append(caseName)
        } else if hasUndoExcluded {
          excludedCases.append(caseName)
        } else {
          hasDefaultCases = true
        }
      }
    }

    // Build the switch cases
    var switchCases: [String] = []

    if !undoPointCases.isEmpty {
      let casePattern = undoPointCases.map { ".\($0)" }.joined(separator: ", ")
      switchCases.append(
        """
            case \(casePattern):
              return .createUndoPoint
        """
      )
    }

    if !excludedCases.isEmpty {
      let casePattern = excludedCases.map { ".\($0)" }.joined(separator: ", ")
      switchCases.append(
        """
            case \(casePattern):
              return .exclude
        """
      )
    }

    if hasDefaultCases || (undoPointCases.isEmpty && excludedCases.isEmpty) {
      switchCases.append(
        """
            default:
              return .debounce
        """
      )
    }

    let switchBody = switchCases.joined(separator: "\n")

    let ext: DeclSyntax =
      """
      \(declaration.attributes.availability)extension \(type.trimmed): \
      ComposableArchitecture.UndoActionClassification {
        var undoBehavior: ComposableArchitecture.UndoActionBehavior {
          switch self {
      \(raw: switchBody)
          }
        }
      }
      """
    return [ext.cast(ExtensionDeclSyntax.self)]
  }
}








