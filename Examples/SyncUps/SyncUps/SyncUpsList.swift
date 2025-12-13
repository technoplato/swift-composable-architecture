import ComposableArchitecture
import SwiftUI

@Reducer
struct SyncUpsList {
  @Reducer
  enum Destination {
    case add(SyncUpForm)
    case alert(AlertState<Alert>)

    @CasePathable
    enum Alert {
      case confirmLoadMockData
    }
  }

  @ObservableState
  struct State: Equatable {
    @Presents var destination: Destination.State?
    @Shared(.stopwatches) var stopwatches
    @Shared(.syncUps) var syncUps
  }

  enum Action {
    case addStopwatchButtonTapped
    case addSyncUpButtonTapped
    case destination(PresentationAction<Destination.Action>)
    case dismissAddSyncUpButtonTapped
    case onDeleteStopwatch(IndexSet)
    case onDeleteSyncUp(IndexSet)
    case saveSyncUpButtonTapped
  }

  @Dependency(\.uuid) var uuid

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .addStopwatchButtonTapped:
        let newStopwatch = StopwatchItem(
          id: StopwatchItem.ID(uuid()),
          title: "Stopwatch \(state.stopwatches.count + 1)"
        )
        state.$stopwatches.withLock { _ = $0.append(newStopwatch) }
        return .none

      case .addSyncUpButtonTapped:
        let newSyncUp = SyncUp(
          id: SyncUp.ID(uuid()),
          attendees: [Attendee(id: Attendee.ID(uuid()))]
        )
        state.$syncUps.withLock { _ = $0.append(newSyncUp) }
        state.destination = .add(
          SyncUpForm.State(syncUp: newSyncUp)
        )
        return .none

      case .destination:
        return .none

      case .dismissAddSyncUpButtonTapped:
        state.destination = nil
        return .none

      case let .onDeleteStopwatch(indexSet):
        state.$stopwatches.withLock { $0.remove(atOffsets: indexSet) }
        return .none

      case let .onDeleteSyncUp(indexSet):
        state.$syncUps.withLock { $0.remove(atOffsets: indexSet) }
        return .none

      case .saveSyncUpButtonTapped:
        guard case let .some(.add(editState)) = state.destination
        else { return .none }
        var syncUp = editState.syncUp
        syncUp.attendees.removeAll { attendee in
          attendee.name.allSatisfy(\.isWhitespace)
        }
        if syncUp.attendees.isEmpty {
          syncUp.attendees.append(
            editState.syncUp.attendees.first
              ?? Attendee(id: Attendee.ID(uuid()))
          )
        }
        syncUp.status = .active
        state.$syncUps.withLock { $0[id: syncUp.id] = syncUp }
        state.destination = nil
        return .none
      }
    }
    .ifLet(\.$destination, action: \.destination)
  }
}
extension SyncUpsList.Destination.State: Equatable {}

struct SyncUpsListView: View {
  @Bindable var store: StoreOf<SyncUpsList>

  var body: some View {
    List {
      Section {
        ForEach(Array(store.$stopwatches)) { $stopwatch in
          NavigationLink(
            state: AppFeature.Path.State.stopwatchDetail(StopwatchDetail.State(stopwatch: $stopwatch))
          ) {
            StopwatchCard(stopwatch: $stopwatch)
          }
          .listRowBackground(Color(.systemBackground))
        }
        .onDelete { indexSet in
          store.send(.onDeleteStopwatch(indexSet))
        }

        Button {
          store.send(.addStopwatchButtonTapped)
        } label: {
          Label("New Stopwatch", systemImage: "plus")
        }
      } header: {
        HStack {
          Text("Stopwatches")
          Spacer()
          Text("\(store.stopwatches.count)")
            .foregroundColor(.secondary)
        }
      }

      Section {
        ForEach(Array(store.$syncUps)) { $syncUp in
          NavigationLink(state: AppFeature.Path.State.detail(SyncUpDetail.State(syncUp: $syncUp))) {
            CardView(syncUp: syncUp)
          }
          .listRowBackground(syncUp.theme.mainColor)
        }
        .onDelete { indexSet in
          store.send(.onDeleteSyncUp(indexSet))
        }
      } header: {
        Text("Sync-ups")
      }
    }
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          store.send(.addSyncUpButtonTapped)
        } label: {
          Image(systemName: "plus")
        }
      }
    }
    .navigationTitle("Daily Sync-ups")
    .sheet(
      item: $store.scope(state: \.destination?.add, action: \.destination.add)
    ) { addSyncUpStore in
      NavigationStack {
        SyncUpFormView(store: addSyncUpStore)
          .navigationTitle("New sync-up")
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Dismiss") {
                store.send(.dismissAddSyncUpButtonTapped)
              }
            }
            ToolbarItem(placement: .confirmationAction) {
              Button("Save") {
                store.send(.saveSyncUpButtonTapped)
              }
            }
          }
      }
    }
  }
}

struct CardView: View {
  let syncUp: SyncUp

  var body: some View {
    VStack(alignment: .leading) {
      HStack {
        Text(syncUp.title)
          .font(.headline)
        Spacer()
        StatusBadge(status: syncUp.status)
      }
      Spacer()
      HStack {
        Label("\(syncUp.attendees.count)", systemImage: "person.3")
        Spacer()
        Label(syncUp.duration.formatted(.units()), systemImage: "clock")
          .labelStyle(.trailingIcon)
      }
      .font(.caption)
    }
    .padding()
    .foregroundColor(syncUp.theme.accentColor)
  }
}

struct StatusBadge: View {
  let status: SyncUp.Status

  var body: some View {
    Text(status.label)
      .font(.caption2)
      .fontWeight(.medium)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(status.backgroundColor)
      .foregroundColor(status.foregroundColor)
      .cornerRadius(4)
  }
}

extension SyncUp.Status {
  var label: String {
    switch self {
    case .draft: return "Draft"
    case .active: return "Active"
    case .archived: return "Archived"
    }
  }

  var backgroundColor: Color {
    switch self {
    case .draft: return .yellow.opacity(0.3)
    case .active: return .green.opacity(0.3)
    case .archived: return .gray.opacity(0.3)
    }
  }

  var foregroundColor: Color {
    switch self {
    case .draft: return .orange
    case .active: return .green
    case .archived: return .gray
    }
  }
}

struct TrailingIconLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack {
      configuration.title
      configuration.icon
    }
  }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
  static var trailingIcon: Self { Self() }
}

#Preview("List") {
  @Shared(.syncUps) var syncUps = [
    .mock,
    .productMock,
    .engineeringMock,
  ]
  NavigationStack {
    SyncUpsListView(
      store: Store(initialState: SyncUpsList.State()) {
        SyncUpsList()
      }
    )
  }
}

#Preview("Card") {
  CardView(
    syncUp: SyncUp(
      id: SyncUp.ID(),
      duration: .seconds(60),
      title: "Point-Free Morning Sync"
    )
  )
}

extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<SyncUp>>.Default {
  static var syncUps: Self {
    Self[.fileStorage(.documentsDirectory.appending(component: "sync-ups.json")), default: []]
  }
}
