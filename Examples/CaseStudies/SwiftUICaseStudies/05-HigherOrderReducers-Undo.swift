import ComposableArchitecture
import SwiftUI

private let readMe = """
  This screen demonstrates how to create a generic "undo/redo" higher-order reducer that can wrap \
  any feature to provide undo and redo capabilities.

  The `UndoReducer` maintains a history of state snapshots. Every time the wrapped feature's \
  reducer processes an action, the current state is pushed onto the "past" stack before the \
  mutation occurs. The "future" stack is cleared when a new action is taken, creating a new \
  timeline.

  Tapping "Undo" pops the most recent state from "past", pushes the current state onto "future", \
  and restores the previous state. "Redo" does the inverse operation.

  The history is limited to a configurable number of entries to prevent unbounded memory growth.
  """

// MARK: - UndoReducer: A Generic Higher-Order Reducer

/// A higher-order reducer that wraps any feature and adds undo/redo capabilities.
///
/// This reducer maintains three pieces of state:
/// - `present`: The current state of the wrapped feature
/// - `past`: A stack of previous states (for undo)
/// - `future`: A stack of undone states (for redo)
///
/// Usage:
/// ```swift
/// UndoReducer(feature: Counter(), historyLimit: 50)
/// ```
@Reducer
struct UndoReducer<Feature: Reducer> where Feature.State: Equatable {
  let feature: Feature
  let historyLimit: Int

  init(feature: Feature, historyLimit: Int = 50) {
    self.feature = feature
    self.historyLimit = historyLimit
  }

  @ObservableState
  struct State: Equatable {
    var present: Feature.State
    var past: [Feature.State] = []
    var future: [Feature.State] = []

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    init(present: Feature.State) {
      self.present = present
    }
  }

  @CasePathable
  enum Action {
    case feature(Feature.Action)
    case undo
    case redo
    case clearHistory
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .feature(featureAction):
        // 1. Snapshot current state to past before mutation
        state.past.append(state.present)

        // 2. Prune history if it exceeds the limit
        if state.past.count > historyLimit {
          state.past.removeFirst()
        }

        // 3. Clear future (new action creates new timeline)
        state.future.removeAll()

        // 4. Run the wrapped feature's reducer
        return feature.reduce(into: &state.present, action: featureAction)
          .map { .feature($0) }

      case .undo:
        guard let previous = state.past.popLast() else { return .none }

        // Push current state to future
        state.future.insert(state.present, at: 0)
        // Restore previous state
        state.present = previous
        return .none

      case .redo:
        guard let next = state.future.first else { return .none }
        state.future.removeFirst()

        // Push current state to past
        state.past.append(state.present)
        // Restore next state
        state.present = next
        return .none

      case .clearHistory:
        state.past.removeAll()
        state.future.removeAll()
        return .none
      }
    }
  }
}

// MARK: - Demo: Undo Counter

struct UndoCounterDemoView: View {
  @Bindable var store: StoreOf<UndoReducer<Counter>>

  var body: some View {
    Form {
      Section {
        AboutView(readMe: readMe)
      }

      Section {
        VStack(spacing: 16) {
          Text("\(store.present.count)")
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .monospacedDigit()

          HStack(spacing: 24) {
            Button {
              store.send(.feature(.decrementButtonTapped))
            } label: {
              Image(systemName: "minus.circle.fill")
                .font(.system(size: 44))
            }

            Button {
              store.send(.feature(.incrementButtonTapped))
            } label: {
              Image(systemName: "plus.circle.fill")
                .font(.system(size: 44))
            }
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      }

      Section {
        HStack(spacing: 32) {
          VStack {
            Button {
              store.send(.undo)
            } label: {
              Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 40))
            }
            .disabled(!store.canUndo)

            Text("Undo")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          VStack {
            Button {
              store.send(.redo)
            } label: {
              Image(systemName: "arrow.uturn.forward.circle.fill")
                .font(.system(size: 40))
            }
            .disabled(!store.canRedo)

            Text("Redo")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          VStack {
            Button(role: .destructive) {
              store.send(.clearHistory)
            } label: {
              Image(systemName: "trash.circle.fill")
                .font(.system(size: 40))
            }
            .disabled(!store.canUndo && !store.canRedo)

            Text("Clear")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      } header: {
        Text("History Controls")
      }

      Section {
        LabeledContent("Past states") {
          Text("\(store.past.count)")
            .monospacedDigit()
        }
        LabeledContent("Future states") {
          Text("\(store.future.count)")
            .monospacedDigit()
        }
      } header: {
        Text("History Info")
      }
    }
    .buttonStyle(.borderless)
    .navigationTitle("Undo/Redo")
  }
}

#Preview {
  NavigationStack {
    UndoCounterDemoView(
      store: Store(
        initialState: UndoReducer<Counter>.State(present: Counter.State())
      ) {
        UndoReducer(feature: Counter())
      }
    )
  }
}
