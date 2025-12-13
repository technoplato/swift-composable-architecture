import ComposableArchitecture
import IdentifiedCollections
import SwiftUI

@Reducer
struct AppFeature {
  @Reducer
  enum Path {
    case detail(SyncUpDetail)
    case meeting(Meeting, syncUp: SyncUp)
    case record(RecordMeeting)
    case stopwatchDetail(StopwatchDetail)
  }

  @ObservableState
  struct State: Equatable {
    var path = StackState<Path.State>()
    var syncUpsList = SyncUpsList.State()
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID
    @Shared(.stopwatches) var stopwatches

    /// Returns the favorite stopwatch if it exists (for checking existence)
    var favoriteStopwatch: StopwatchItem? {
      guard let favoriteID = favoriteStopwatchID else { return nil }
      return stopwatches[id: favoriteID]
    }

    /// Returns true if we're currently viewing the favorite stopwatch's detail
    var isViewingFavoriteDetail: Bool {
      guard let favoriteID = favoriteStopwatchID else { return false }
      return path.contains { pathState in
        if case let .stopwatchDetail(detailState) = pathState {
          return detailState.stopwatch.id == favoriteID
        }
        return false
      }
    }
  }

  enum Action {
    case floatingStopwatch(FloatingStopwatchAction)
    case path(StackActionOf<Path>)
    case syncUpsList(SyncUpsList.Action)

    @CasePathable
    enum FloatingStopwatchAction {
      case deleteTapped
      case toggleTapped
      case unfavoriteTapped
    }
  }

  @Dependency(\.date.now) var now
  @Dependency(\.uuid) var uuid

  var body: some ReducerOf<Self> {
    Scope(state: \.syncUpsList, action: \.syncUpsList) {
      SyncUpsList()
    }
    Reduce { state, action in
      switch action {
      case .floatingStopwatch(.deleteTapped):
        guard let favoriteID = state.favoriteStopwatchID else { return .none }

        // Find next stopwatch to auto-select
        let currentIndex = state.stopwatches.firstIndex(where: { $0.id == favoriteID })
        var nextID: StopwatchItem.ID? = nil

        if let index = currentIndex {
          if index + 1 < state.stopwatches.count {
            nextID = state.stopwatches[index + 1].id
          } else if index > 0 {
            nextID = state.stopwatches[index - 1].id
          }
        }

        // Update favorite ID before deletion
        state.$favoriteStopwatchID.withLock { $0 = nextID }

        // Delete the stopwatch
        state.$stopwatches.withLock { _ = $0.remove(id: favoriteID) }
        return .none

      case .floatingStopwatch(.toggleTapped):
        guard let favoriteID = state.favoriteStopwatchID,
              let index = state.stopwatches.firstIndex(where: { $0.id == favoriteID })
        else { return .none }

        let currentTime = now
        state.$stopwatches.withLock { stopwatches in
          if stopwatches[index].isRunning {
            // Pause
            stopwatches[index].elapsedMilliseconds = stopwatches[index].currentElapsedMilliseconds(now: currentTime)
            stopwatches[index].lastStartTime = nil
            stopwatches[index].isRunning = false
          } else {
            // Start
            stopwatches[index].lastStartTime = currentTime
            stopwatches[index].isRunning = true
          }
        }
        return .none

      case .floatingStopwatch(.unfavoriteTapped):
        state.$favoriteStopwatchID.withLock { $0 = nil }
        return .none

      case let .path(.element(_, .detail(.delegate(delegateAction)))):
        switch delegateAction {
        case let .startMeeting(sharedSyncUp):
          state.path.append(.record(RecordMeeting.State(syncUp: sharedSyncUp)))
          return .none
        }

      case .path:
        return .none

      case .syncUpsList:
        return .none
      }
    }
    .forEach(\.path, action: \.path)
  }
}
extension AppFeature.Path.State: Equatable {}

struct AppView: View {
  @Bindable var store: StoreOf<AppFeature>

  var body: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      ZStack(alignment: .bottom) {
        SyncUpsListView(store: store.scope(state: \.syncUpsList, action: \.syncUpsList))
          .safeAreaInset(edge: .bottom) {
            // Reserve space for floating widget when visible
            if store.favoriteStopwatch != nil && !store.isViewingFavoriteDetail {
              Color.clear.frame(height: 80)
            }
          }

        // Floating favorite stopwatch widget (must be inside NavigationStack for NavigationLink to work)
        if let favoriteID = store.favoriteStopwatchID {
          FloatingStopwatchOverlay(
            store: store,
            stopwatches: store.$stopwatches,
            favoriteID: favoriteID,
            isViewingFavoriteDetail: store.isViewingFavoriteDetail
          )
        }
      }
      .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.favoriteStopwatchID != nil && !store.isViewingFavoriteDetail)
    } destination: { store in
      switch store.case {
      case let .detail(store):
        SyncUpDetailView(store: store)
      case let .meeting(meeting, syncUp):
        MeetingView(meeting: meeting, syncUp: syncUp)
      case let .record(store):
        RecordMeetingView(store: store)
      case let .stopwatchDetail(store):
        StopwatchDetailView(store: store)
      }
    }
  }
}

/// A separate view that handles the floating widget with proper @Shared bindings
struct FloatingStopwatchOverlay: View {
  let store: StoreOf<AppFeature>
  @Shared var stopwatches: IdentifiedArrayOf<StopwatchItem>
  let favoriteID: StopwatchItem.ID
  let isViewingFavoriteDetail: Bool

  var body: some View {
    if let index = stopwatches.firstIndex(where: { $0.id == favoriteID }),
       !isViewingFavoriteDetail {
      NavigationLink(
        state: AppFeature.Path.State.stopwatchDetail(
          StopwatchDetail.State(stopwatch: $stopwatches[index])
        )
      ) {
        FloatingStopwatchWidgetView(
          store: store,
          stopwatch: $stopwatches[index]
        )
      }
      .buttonStyle(.plain)
      .padding(.bottom, 8)
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }
}

/// The actual floating widget view that sends actions to the store
struct FloatingStopwatchWidgetView: View {
  let store: StoreOf<AppFeature>
  @Shared var stopwatch: StopwatchItem

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.01, paused: !stopwatch.isRunning)) { context in
      let currentMs = stopwatch.currentElapsedMilliseconds(now: context.date)

      HStack(spacing: 16) {
        // Stopwatch info (tappable for navigation)
        VStack(alignment: .leading, spacing: 2) {
          Text(stopwatch.title.isEmpty ? "Stopwatch" : stopwatch.title)
            .font(.subheadline)
            .fontWeight(.medium)
            .lineLimit(1)

          HStack(spacing: 4) {
            StopwatchWidgetDisplay(milliseconds: currentMs)
            if stopwatch.isRunning {
              Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            }
          }
        }

        Spacer()

        // Pause/Play button
        Button {
          store.send(.floatingStopwatch(.toggleTapped))
        } label: {
          Image(systemName: stopwatch.isRunning ? "pause.fill" : "play.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(stopwatch.isRunning ? Color.orange : Color.green)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)

        // Unstar button
        Button {
          store.send(.floatingStopwatch(.unfavoriteTapped))
        } label: {
          Image(systemName: "star.slash.fill")
            .font(.system(size: 16))
            .foregroundColor(.yellow)
            .frame(width: 36, height: 36)
            .background(Color(.systemGray5))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)

        // Delete button
        Button {
          store.send(.floatingStopwatch(.deleteTapped))
        } label: {
          Image(systemName: "trash.fill")
            .font(.system(size: 16))
            .foregroundColor(.red)
            .frame(width: 36, height: 36)
            .background(Color(.systemGray5))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(.ultraThinMaterial)
          .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
      )
      .padding(.horizontal, 16)
    }
  }
}

#Preview {
  @Shared(.syncUps) var syncUps = [
    .mock,
    .productMock,
    .engineeringMock,
  ]
  AppView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}
