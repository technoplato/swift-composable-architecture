import ComposableArchitecture
import Sharing
import SwiftUI

private let readMe = """
  This screen demonstrates how to create a generic "undo/redo" higher-order reducer that can wrap \
  any feature to provide undo and redo capabilities, with optional persistence to disk using \
  Swift Sharing's `fileStorage` strategy.

  The `PersistableUndoReducer` maintains a history of state snapshots. Every time the wrapped \
  feature's reducer processes an action, the current state is pushed onto the "past" stack before \
  the mutation occurs. The "future" stack is cleared when a new action is taken, creating a new \
  timeline.

  Tapping "Undo" pops the most recent state from "past", pushes the current state onto "future", \
  and restores the previous state. "Redo" does the inverse operation.

  The history is limited to a configurable number of entries to prevent unbounded memory growth.

  Unlike the basic `UndoReducer`, this version can persist the entire undo history (including \
  present, past, and future states) to disk. Pass a URL to the `persistTo:` initializer parameter \
  to enable persistence. Close and reopen the app to see your history preserved!
  """

// MARK: - UndoHistory: A Generic Codable History Container

/// A container that holds the present state along with past and future states for undo/redo.
///
/// This type is `Codable` so it can be persisted to disk using Swift Sharing's `fileStorage`
/// strategy. It is generic over any `FeatureState` that is `Codable`, `Equatable`, and `Sendable`.
struct UndoHistory<FeatureState: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
  var present: FeatureState
  var past: [FeatureState] = []
  var future: [FeatureState] = []

  var canUndo: Bool { !past.isEmpty }
  var canRedo: Bool { !future.isEmpty }

  init(present: FeatureState) {
    self.present = present
  }
}

// MARK: - PersistableUndoReducer: A Generic Higher-Order Reducer with Optional Persistence

/// A higher-order reducer that wraps any feature and adds undo/redo capabilities with optional
/// persistence to disk.
///
/// This reducer maintains three pieces of state via `@Shared`:
/// - `present`: The current state of the wrapped feature
/// - `past`: A stack of previous states (for undo)
/// - `future`: A stack of undone states (for redo)
///
/// The state can optionally be persisted to disk using Swift Sharing's `fileStorage` strategy
/// by using the `init(present:persistTo:)` initializer.
///
/// Usage:
/// ```swift
/// // In-memory only (no persistence)
/// PersistableUndoReducer<MyFeature>.State(present: MyFeature.State())
///
/// // With file persistence
/// PersistableUndoReducer<MyFeature>.State(
///   present: MyFeature.State(),
///   persistTo: .documentsDirectory.appending(component: "my-feature-history.json")
/// )
/// ```
@Reducer
struct PersistableUndoReducer<Feature: Reducer> where Feature.State: Codable & Equatable & Sendable {
  let feature: Feature
  let historyLimit: Int

  init(feature: Feature, historyLimit: Int = 50) {
    self.feature = feature
    self.historyLimit = historyLimit
  }

  @ObservableState
  struct State: Equatable {
    /// The shared undo history. Can be in-memory only or persisted to disk.
    @Shared var history: UndoHistory<Feature.State>

    /// Convenience accessor for the current state of the wrapped feature.
    var present: Feature.State { history.present }

    /// Convenience accessor for the past states stack.
    var past: [Feature.State] { history.past }

    /// Convenience accessor for the future states stack.
    var future: [Feature.State] { history.future }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// Creates an in-memory undo state (no persistence).
    ///
    /// - Parameter present: The initial state of the wrapped feature.
    init(present: Feature.State) {
      self._history = Shared(value: UndoHistory(present: present))
    }

    /// Creates a persisted undo state that saves to disk.
    ///
    /// The undo history (including present, past, and future states) will be automatically
    /// persisted to the specified URL using JSON serialization. Changes are throttled to
    /// avoid excessive disk writes.
    ///
    /// - Parameters:
    ///   - present: The initial state of the wrapped feature. Only used if no persisted
    ///     state exists at the URL.
    ///   - url: The file URL where the undo history will be persisted.
    init(present: Feature.State, persistTo url: URL) {
      self._history = Shared(
        wrappedValue: UndoHistory(present: present),
        .fileStorage(url)
      )
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
        state.$history.withLock { history in
          history.past.append(history.present)

          // 2. Prune history if it exceeds the limit
          if history.past.count > historyLimit {
            history.past.removeFirst()
          }

          // 3. Clear future (new action creates new timeline)
          history.future.removeAll()
        }

        // 4. Run the wrapped feature's reducer
        var presentState = state.present
        let effect = feature.reduce(into: &presentState, action: featureAction)
        state.$history.withLock { $0.present = presentState }
        return effect.map { .feature($0) }

      case .undo:
        state.$history.withLock { history in
          guard let previous = history.past.popLast() else { return }

          // Push current state to future
          history.future.insert(history.present, at: 0)
          // Restore previous state
          history.present = previous
        }
        return .none

      case .redo:
        state.$history.withLock { history in
          guard let next = history.future.first else { return }
          history.future.removeFirst()

          // Push current state to past
          history.past.append(history.present)
          // Restore next state
          history.present = next
        }
        return .none

      case .clearHistory:
        state.$history.withLock { history in
          history.past.removeAll()
          history.future.removeAll()
        }
        return .none
      }
    }
  }
}

// MARK: - Demo: Persistable Undo Counter

/// A simple counter reducer used to demonstrate the PersistableUndoReducer.
/// Note: The State must conform to Codable & Sendable for persistence to work.
@Reducer
struct PersistableCounterFeature {
  @ObservableState
  struct State: Codable, Equatable, Sendable {
    var count = 0
  }

  enum Action {
    case decrementButtonTapped
    case incrementButtonTapped
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .decrementButtonTapped:
        state.count -= 1
        return .none
      case .incrementButtonTapped:
        state.count += 1
        return .none
      }
    }
  }
}

struct UndoWithStorageDemoView: View {
  @Bindable var store: StoreOf<PersistableUndoReducer<PersistableCounterFeature>>

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
        Text("History Info (Persisted to Disk)")
      }
    }
    .buttonStyle(.borderless)
    .navigationTitle("Undo/Redo + Storage")
  }
}

#Preview("With Persistence") {
  NavigationStack {
    UndoWithStorageDemoView(
      store: Store(
        initialState: PersistableUndoReducer<PersistableCounterFeature>.State(
          present: PersistableCounterFeature.State(),
          persistTo: .documentsDirectory.appending(component: "undo-counter-history.json")
        )
      ) {
        PersistableUndoReducer(feature: PersistableCounterFeature())
      }
    )
  }
}

#Preview("In-Memory Only") {
  NavigationStack {
    UndoWithStorageDemoView(
      store: Store(
        initialState: PersistableUndoReducer<PersistableCounterFeature>.State(
          present: PersistableCounterFeature.State()
        )
      ) {
        PersistableUndoReducer(feature: PersistableCounterFeature())
      }
    )
  }
}

