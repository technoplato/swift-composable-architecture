import ComposableArchitecture
import Sharing
import SwiftUI

// MARK: - Route Definition

/// All navigable case studies in the app.
/// Persisted to disk via `@Shared(.caseStudyPath)` so navigation state survives app restarts.
private enum CaseStudyRoute: Codable, Hashable {
  // Getting started
  case basics
  case combiningReducers
  case bindings
  case formBindings
  case optionalState
  case alertsAndDialogs
  case focusState
  case animations

  // Shared state
  case sharedStateInMemory
  case sharedStateUserDefaults
  case sharedStateFileStorage

  // Effects
  case effectsBasics
  case effectsCancellation
  case longLivingEffects
  case refreshable
  case timers
  case webSocket

  // Navigation
  case navigateAndLoad
  case navigateAndLoadList
  case presentAndLoad
  case loadThenPresent
  case multipleDestinations

  // Higher-order reducers
  case episodes
  case mapApp
  case nested
  case undoRedo
  case undoRedoStorage
  case selectiveUndoStopwatch
  case selectiveUndoCanvas
  case undoableModifier
}

// MARK: - Shared Key Extension

extension SharedReaderKey where Self == FileStorageKey<[CaseStudyRoute]>.Default {
  fileprivate static var caseStudyPath: Self {
    Self[
      .fileStorage(.documentsDirectory.appending(path: "case-study-path.json")),
      default: []
    ]
  }
}

// MARK: - Root View

struct RootView: View {
  @Shared(.caseStudyPath) private var path
  @State var isNavigationStackCaseStudyPresented = false
  @State var isSignUpCaseStudyPresented = false

  var body: some View {
    NavigationStack(path: Binding($path)) {
      Form {
        Section {
          NavigationLink("Basics", value: CaseStudyRoute.basics)
          NavigationLink("Combining reducers", value: CaseStudyRoute.combiningReducers)
          NavigationLink("Bindings", value: CaseStudyRoute.bindings)
          NavigationLink("Form bindings", value: CaseStudyRoute.formBindings)
          NavigationLink("Optional state", value: CaseStudyRoute.optionalState)
          NavigationLink("Alerts and Confirmation Dialogs", value: CaseStudyRoute.alertsAndDialogs)
          NavigationLink("Focus State", value: CaseStudyRoute.focusState)
          NavigationLink("Animations", value: CaseStudyRoute.animations)
        } header: {
          Text("Getting started")
        }

        Section {
          NavigationLink("In memory", value: CaseStudyRoute.sharedStateInMemory)
          NavigationLink("User defaults", value: CaseStudyRoute.sharedStateUserDefaults)
          NavigationLink("File storage", value: CaseStudyRoute.sharedStateFileStorage)
          Button("Sign up flow") {
            isSignUpCaseStudyPresented = true
          }
          .sheet(isPresented: $isSignUpCaseStudyPresented) {
            SignUpFlow()
          }
        } header: {
          Text("Shared state")
        }

        Section {
          NavigationLink("Basics", value: CaseStudyRoute.effectsBasics)
          NavigationLink("Cancellation", value: CaseStudyRoute.effectsCancellation)
          NavigationLink("Long-living effects", value: CaseStudyRoute.longLivingEffects)
          NavigationLink("Refreshable", value: CaseStudyRoute.refreshable)
          NavigationLink("Timers", value: CaseStudyRoute.timers)
          NavigationLink("Web socket", value: CaseStudyRoute.webSocket)
        } header: {
          Text("Effects")
        }

        Section {
          Button("Stack") {
            isNavigationStackCaseStudyPresented = true
          }
          .buttonStyle(.plain)

          NavigationLink("Navigate and load data", value: CaseStudyRoute.navigateAndLoad)
          NavigationLink("Lists: Navigate and load data", value: CaseStudyRoute.navigateAndLoadList)
          NavigationLink("Sheets: Present and load data", value: CaseStudyRoute.presentAndLoad)
          NavigationLink("Sheets: Load data then present", value: CaseStudyRoute.loadThenPresent)
          NavigationLink("Multiple destinations", value: CaseStudyRoute.multipleDestinations)
        } header: {
          Text("Navigation")
        }

        Section {
          NavigationLink("Reusable favoriting component", value: CaseStudyRoute.episodes)
          NavigationLink("Reusable offline download component", value: CaseStudyRoute.mapApp)
          NavigationLink("Recursive state and actions", value: CaseStudyRoute.nested)
          NavigationLink("Undo/Redo", value: CaseStudyRoute.undoRedo)
          NavigationLink("Undo/Redo + Storage", value: CaseStudyRoute.undoRedoStorage)
          NavigationLink("Selective Undo (Stopwatch)", value: CaseStudyRoute.selectiveUndoStopwatch)
          NavigationLink("Selective Undo (Canvas)", value: CaseStudyRoute.selectiveUndoCanvas)
          NavigationLink(".undoable() Modifier", value: CaseStudyRoute.undoableModifier)
        } header: {
          Text("Higher-order reducers")
        }
      }
      .navigationTitle("Case Studies")
      .navigationDestination(for: CaseStudyRoute.self) { route in
        destinationView(for: route)
      }
      .sheet(isPresented: $isNavigationStackCaseStudyPresented) {
        Demo(store: Store(initialState: NavigationDemo.State()) { NavigationDemo() }) { store in
          NavigationDemoView(store: store)
        }
      }
    }
  }

  @ViewBuilder
  private func destinationView(for route: CaseStudyRoute) -> some View {
    switch route {
    // Getting started
    case .basics:
      Demo(store: Store(initialState: Counter.State()) { Counter() }) { store in
        CounterDemoView(store: store)
      }
    case .combiningReducers:
      Demo(store: Store(initialState: TwoCounters.State()) { TwoCounters() }) { store in
        TwoCountersView(store: store)
      }
    case .bindings:
      Demo(store: Store(initialState: BindingBasics.State()) { BindingBasics() }) { store in
        BindingBasicsView(store: store)
      }
    case .formBindings:
      Demo(store: Store(initialState: BindingForm.State()) { BindingForm() }) { store in
        BindingFormView(store: store)
      }
    case .optionalState:
      Demo(store: Store(initialState: OptionalBasics.State()) { OptionalBasics() }) { store in
        OptionalBasicsView(store: store)
      }
    case .alertsAndDialogs:
      Demo(
        store: Store(initialState: AlertAndConfirmationDialog.State()) {
          AlertAndConfirmationDialog()
        }
      ) { store in
        AlertAndConfirmationDialogView(store: store)
      }
    case .focusState:
      Demo(store: Store(initialState: FocusDemo.State()) { FocusDemo() }) { store in
        FocusDemoView(store: store)
      }
    case .animations:
      Demo(store: Store(initialState: Animations.State()) { Animations() }) { store in
        AnimationsView(store: store)
      }

    // Shared state
    case .sharedStateInMemory:
      Demo(
        store: Store(initialState: SharedStateInMemory.State()) { SharedStateInMemory() }
      ) { store in
        SharedStateInMemoryView(store: store)
      }
    case .sharedStateUserDefaults:
      Demo(
        store: Store(initialState: SharedStateUserDefaults.State()) {
          SharedStateUserDefaults()
        }
      ) { store in
        SharedStateUserDefaultsView(store: store)
      }
    case .sharedStateFileStorage:
      Demo(
        store: Store(initialState: SharedStateFileStorage.State()) {
          SharedStateFileStorage()
        }
      ) { store in
        SharedStateFileStorageView(store: store)
      }

    // Effects
    case .effectsBasics:
      Demo(store: Store(initialState: EffectsBasics.State()) { EffectsBasics() }) { store in
        EffectsBasicsView(store: store)
      }
    case .effectsCancellation:
      Demo(
        store: Store(initialState: EffectsCancellation.State()) { EffectsCancellation() }
      ) { store in
        EffectsCancellationView(store: store)
      }
    case .longLivingEffects:
      Demo(
        store: Store(initialState: LongLivingEffects.State()) { LongLivingEffects() }
      ) { store in
        LongLivingEffectsView(store: store)
      }
    case .refreshable:
      Demo(store: Store(initialState: Refreshable.State()) { Refreshable() }) { store in
        RefreshableView(store: store)
      }
    case .timers:
      Demo(store: Store(initialState: Timers.State()) { Timers() }) { store in
        TimersView(store: store)
      }
    case .webSocket:
      Demo(store: Store(initialState: WebSocket.State()) { WebSocket() }) { store in
        WebSocketView(store: store)
      }

    // Navigation
    case .navigateAndLoad:
      Demo(
        store: Store(initialState: NavigateAndLoad.State()) { NavigateAndLoad() }
      ) { store in
        NavigateAndLoadView(store: store)
      }
    case .navigateAndLoadList:
      Demo(
        store: Store(initialState: NavigateAndLoadList.State()) { NavigateAndLoadList() }
      ) { store in
        NavigateAndLoadListView(store: store)
      }
    case .presentAndLoad:
      Demo(store: Store(initialState: PresentAndLoad.State()) { PresentAndLoad() }) { store in
        PresentAndLoadView(store: store)
      }
    case .loadThenPresent:
      Demo(
        store: Store(initialState: LoadThenPresent.State()) { LoadThenPresent() }
      ) { store in
        LoadThenPresentView(store: store)
      }
    case .multipleDestinations:
      Demo(
        store: Store(initialState: MultipleDestinations.State()) { MultipleDestinations() }
      ) { store in
        MultipleDestinationsView(store: store)
      }

    // Higher-order reducers
    case .episodes:
      Demo(
        store: Store(
          initialState: Episodes.State(episodes: .mocks)
        ) {
          Episodes()
        }
      ) { store in
        EpisodesView(store: store)
      }
    case .mapApp:
      Demo(store: Store(initialState: MapApp.State()) { MapApp() }) { store in
        CitiesView(store: store)
      }
    case .nested:
      Demo(store: Store(initialState: Nested.State()) { Nested() }) { store in
        NestedView(store: store)
      }
    case .undoRedo:
      Demo(
        store: Store(
          initialState: UndoReducer<Counter>.State(present: Counter.State())
        ) {
          UndoReducer(feature: Counter())
        }
      ) { store in
        UndoCounterDemoView(store: store)
      }
    case .undoRedoStorage:
      Demo(
        store: Store(
          initialState: PersistableUndoReducer<PersistableCounterFeature>.State(
            present: PersistableCounterFeature.State(),
            persistTo: .documentsDirectory.appending(component: "undo-counter-history.json")
          )
        ) {
          PersistableUndoReducer(feature: PersistableCounterFeature())
        }
      ) { store in
        UndoWithStorageDemoView(store: store)
      }
    case .selectiveUndoStopwatch:
      Demo(
        store: Store(
          initialState: SelectiveUndoReducer<StopwatchFeature, StopwatchUndoableState>.State(
            present: StopwatchFeature.State()
          )
        ) {
          SelectiveUndoReducer(
            feature: StopwatchFeature(),
            extractUndoable: { $0.undoableState },
            restoreUndoable: { state, undoable in
              state.lapTimes = undoable.lapTimes
              state.lapNotes = undoable.lapNotes
            },
            // Uses StopwatchFeature.Action.undoBehavior to filter actions!
            // Timer ticks are excluded, lap actions create undo points.
            useActionClassification: true
          )
        }
      ) { store in
        SelectiveUndoStopwatchDemoView(store: store)
      }
    case .selectiveUndoCanvas:
      Demo(
        store: Store(
          initialState: SelectiveUndoReducer<CanvasFeature, CanvasUndoableState>.State(
            present: CanvasFeature.State()
          )
        ) {
          SelectiveUndoReducer(
            feature: CanvasFeature(),
            extractUndoable: { $0.undoableState },
            restoreUndoable: { state, undoable in
              state.strokes = undoable.strokes
              state.selectedColor = undoable.selectedColor
              state.brushWidth = undoable.brushWidth
            },
            // Uses CanvasFeature.Action.undoBehavior to filter actions!
            // Pen movements are excluded, stroke completion creates undo points.
            useActionClassification: true
          )
        }
      ) { store in
        SelectiveUndoCanvasDemoView(store: store)
      }
    case .undoableModifier:
      Demo(
        store: Store(
          initialState: UndoableModifier<UndoableCounterFeature, CounterUndoableState>.State(
            present: UndoableCounterFeature.State()
          )
        ) {
          UndoableCounterFeature()
            .undoable(
              mode: .snapshotOnly,
              historyLimit: 20,
              debounceInterval: .milliseconds(300),
              extractUndoable: { $0.undoableState },
              restoreUndoable: { state, undoable in
                state.count = undoable.count
                state.history = undoable.history
              },
              filter: { action in
                switch action {
                case .incrementButtonTapped, .decrementButtonTapped, .resetButtonTapped:
                  return .createUndoPoint
                }
              }
            )
        }
      ) { store in
        UndoableCounterDemoView(store: store)
      }
    }
  }
}

/// This wrapper provides an "entry" point into an individual demo that can own a store.
struct Demo<State, Action, Content: View>: View {
  @SwiftUI.State var store: Store<State, Action>
  let content: (Store<State, Action>) -> Content

  init(
    store: Store<State, Action>,
    @ViewBuilder content: @escaping (Store<State, Action>) -> Content
  ) {
    self.store = store
    self.content = content
  }

  var body: some View {
    content(store)
  }
}

#Preview {
  RootView()
}
