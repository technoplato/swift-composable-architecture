import ComposableArchitecture
import IdentifiedCollections
import SwiftUI

// MARK: - AppFeature
/// The root feature of the application that manages navigation and coordinates child features.
///
/// This feature uses **tree-based navigation** with a single optional `destination` state that
/// represents which detail screen (if any) is currently being presented. Navigation is
/// **replacement-based**: setting `destination = .stopwatchDetail(...)` replaces whatever
/// was previously shown.
///
/// ## Architecture Overview
///
/// ```
/// AppFeature (root)
/// ├── FloatingStopwatchControls (always present, context-aware)
/// └── Destination? (optional, tree-based)
///     └── StopwatchDetail
/// ```
///
/// ## Navigation Model
///
/// Unlike stack-based navigation where screens push onto a stack, tree-based navigation
/// uses a single optional enum to represent "what's being shown":
///
/// ```swift
/// // Navigate to a stopwatch detail
/// state.destination = .stopwatchDetail(StopwatchDetail.State(stopwatch: sharedStopwatch))
///
/// // Dismiss (go back to list)
/// state.destination = nil
///
/// // Replace current detail with different stopwatch
/// state.destination = .stopwatchDetail(StopwatchDetail.State(stopwatch: differentStopwatch))
/// ```
///
/// ## Floating Controls Integration
///
/// The floating controls are **context-aware** of navigation state. They receive the current
/// `destination` and adapt their UI based on:
/// 1. What screen is being viewed (list vs favorite detail vs non-favorite detail)
/// 2. Whether a favorite stopwatch exists
/// 3. Whether a non-favorite is currently playing
///
/// ## Delegate Pattern
///
/// Child features communicate with AppFeature through delegate actions:
/// - `FloatingStopwatchControls.Delegate` - navigation requests, delete requests
/// - Navigation changes are handled by setting `state.destination`
///
/// ## Example Usage
///
/// ```swift
/// @main
/// struct StopwatchApp: App {
///   var body: some Scene {
///     WindowGroup {
///       AppView(
///         store: Store(initialState: AppFeature.State()) {
///           AppFeature()
///         }
///       )
///     }
///   }
/// }
/// ```

@Reducer
struct AppFeature {
  // MARK: - Destination
  /// Represents the possible navigation destinations from the root.
  ///
  /// Using an enum with the `@Reducer` macro provides:
  /// - Compile-time guarantee that only one destination is active
  /// - Automatic `State` and `Action` type generation
  /// - Built-in reducer composition via `ifLet`
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Navigate to stopwatch detail
  /// state.destination = .stopwatchDetail(
  ///   StopwatchDetail.State(stopwatch: sharedStopwatch)
  /// )
  ///
  /// // Check what's currently shown
  /// if case .stopwatchDetail(let detailState) = state.destination {
  ///   print("Viewing: \(detailState.stopwatch.title)")
  /// }
  /// ```
  @Reducer
  enum Destination {
    case stopwatchDetail(StopwatchDetail)
  }

  // MARK: - State
  @ObservableState
  struct State: Equatable {
    /// The currently presented destination, or `nil` if viewing the list.
    ///
    /// This single optional drives all navigation in the app. Setting it to a
    /// `.stopwatchDetail` case presents that detail; setting it to `nil` dismisses.
    @Presents var destination: Destination.State?
    
    /// State for the floating controls that appear at the bottom of every screen.
    /// The floating controls are context-aware and adapt based on `destination`.
    var floatingControls = FloatingStopwatchControls.State()
    
    // MARK: Shared State
    /// The list of all stopwatches, persisted to disk.
    @Shared(.stopwatches) var stopwatches
    
    /// The ID of the "favorite" stopwatch (the active recording), persisted to disk.
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID
    
    /// The ID of the most recently played non-favorite stopwatch (in-memory only).
    @Shared(.lastPlayedLocalStopwatchID) var lastPlayedLocalStopwatchID
    
    // MARK: - Computed Properties
    
    /// Returns the ID of the stopwatch currently being viewed in detail, if any.
    ///
    /// This is used by floating controls to determine navigation context:
    /// - `nil` = viewing the list
    /// - Some ID = viewing that stopwatch's detail
    var currentlyViewingStopwatchID: StopwatchItem.ID? {
      guard case .stopwatchDetail(let detailState) = destination else {
        return nil
      }
      return detailState.stopwatch.id
    }
    
    /// Returns true if currently viewing the favorite stopwatch's detail.
    var isViewingFavoriteDetail: Bool {
      guard let favoriteID = favoriteStopwatchID,
            let viewingID = currentlyViewingStopwatchID else {
        return false
      }
      return viewingID == favoriteID
    }
    
    /// Returns true if currently viewing a non-favorite stopwatch's detail.
    var isViewingNonFavoriteDetail: Bool {
      guard let viewingID = currentlyViewingStopwatchID else {
        return false
      }
      return viewingID != favoriteStopwatchID
    }
  }

  // MARK: - Action
  enum Action {
    /// Actions from the destination (detail screen).
    case destination(PresentationAction<Destination.Action>)
    
    /// Actions from the floating controls.
    case floatingControls(FloatingStopwatchControls.Action)
    
    /// Actions from the stopwatch list.
    case stopwatchList(StopwatchListAction)
    
    /// User tapped on a stopwatch in the list to view its detail.
    case stopwatchTapped(StopwatchItem.ID)
    
    /// User requested to add a new stopwatch.
    case addStopwatchTapped
    
    /// User deleted stopwatches from the list.
    case deleteStopwatches(IndexSet)
  }
  
  /// Actions that can occur on individual stopwatch cards in the list.
  enum StopwatchListAction {
    case toggleTapped(StopwatchItem.ID)
    case favoriteTapped(StopwatchItem.ID)
  }

  // MARK: - Dependencies
  @Dependency(\.date.now) var now
  @Dependency(\.uuid) var uuid

  // MARK: - Body
  var body: some ReducerOf<Self> {
    // Compose the floating controls reducer
    Scope(state: \.floatingControls, action: \.floatingControls) {
      FloatingStopwatchControls()
    }
    
    Reduce { state, action in
      switch action {
      // MARK: - List Actions
        
      case .addStopwatchTapped:
        let newStopwatch = StopwatchItem(
          id: StopwatchItem.ID(uuid()),
          title: "Stopwatch \(state.stopwatches.count + 1)",
          isRunning: true,
          lastStartTime: now
        )
        state.$stopwatches.withLock { _ = $0.append(newStopwatch) }
        return .none
        
      case let .stopwatchTapped(id):
        guard let sharedStopwatch = Shared(state.$stopwatches[id: id]) else { return .none }
        state.destination = .stopwatchDetail(StopwatchDetail.State(stopwatch: sharedStopwatch))
        return .none
        
      case let .deleteStopwatches(indexSet):
        let idsToDelete = indexSet.compactMap { index -> StopwatchItem.ID? in
          guard index < state.stopwatches.count else { return nil }
          return state.stopwatches[index].id
        }
        for id in idsToDelete {
          deleteStopwatch(id: id, state: &state)
        }
        return .none
        
      case let .stopwatchList(.toggleTapped(id)):
        let isFavorite = id == state.favoriteStopwatchID
        let wasRunning = state.stopwatches[id: id]?.isRunning ?? false
        
        state.$stopwatches.withLock { items in
          items[id: id]?.toggle(now: now)
        }
        
        // If starting a non-favorite, enforce single-playback constraint
        if !isFavorite && !wasRunning {
          state.$stopwatches.withLock { items in
            items.pauseAllNonFavorites(
              except: id,
              favoriteID: state.favoriteStopwatchID,
              now: now
            )
          }
          state.$lastPlayedLocalStopwatchID.withLock { $0 = id }
        }
        return .none
        
      case let .stopwatchList(.favoriteTapped(id)):
        state.$favoriteStopwatchID.withLock { currentFavorite in
          if currentFavorite == id {
            currentFavorite = nil
          } else {
            currentFavorite = id
          }
        }
        return .none

      // MARK: - FloatingStopwatchControls Delegate Actions

      case let .floatingControls(.delegate(.navigateToStopwatch(id))):
        guard let sharedStopwatch = Shared(state.$stopwatches[id: id]) else { return .none }
        // Tree-based: replace destination (not push)
        state.destination = .stopwatchDetail(StopwatchDetail.State(stopwatch: sharedStopwatch))
        return .none

      case .floatingControls(.delegate(.createAndNavigateToNewFavorite)):
        // Pause any playing non-favorite when starting a new recording
        state.$stopwatches.withLock { items in
          items.pauseAllNonFavorites(except: nil, favoriteID: nil, now: now)
        }

        let newStopwatch = StopwatchItem(
          id: StopwatchItem.ID(uuid()),
          title: "Stopwatch \(state.stopwatches.count + 1)",
          isRunning: true,
          lastStartTime: now
        )
        state.$stopwatches.withLock { _ = $0.append(newStopwatch) }
        state.$favoriteStopwatchID.withLock { $0 = newStopwatch.id }
        
        // Navigate to the new stopwatch detail
        if let sharedStopwatch = Shared(state.$stopwatches[id: newStopwatch.id]) {
          state.destination = .stopwatchDetail(StopwatchDetail.State(stopwatch: sharedStopwatch))
        }
        return .none

      case let .floatingControls(.delegate(.nonFavoriteStarted(startedID))):
        // Pause all other non-favorites (VoiceMemos pattern)
        state.$stopwatches.withLock { items in
          items.pauseAllNonFavorites(
            except: startedID,
            favoriteID: state.favoriteStopwatchID,
            now: now
          )
        }
        state.$lastPlayedLocalStopwatchID.withLock { $0 = startedID }
        return .none

      case let .floatingControls(.delegate(.deleteRequested(id))):
        let wasViewingDeleted = state.currentlyViewingStopwatchID == id
        deleteStopwatch(id: id, state: &state)
        // If we were viewing the deleted stopwatch, dismiss
        if wasViewingDeleted {
          state.destination = nil
        }
        return .none

      case .floatingControls:
        return .none

      // MARK: - Destination Actions
        
      case .destination:
        return .none
      }
    }
    // Tree-based navigation: use ifLet instead of forEach
    .ifLet(\.$destination, action: \.destination)
  }

  // MARK: - Private Helpers
  
  /// Deletes a stopwatch and handles cleanup (clears favorite/lastPlayed references).
  ///
  /// If the deleted stopwatch was the favorite, clears the favorite reference (no auto-select).
  /// If the deleted stopwatch was the lastPlayedLocal, clears that reference.
  private func deleteStopwatch(id: StopwatchItem.ID, state: inout State) {
    // Clear favorite reference if we're deleting the favorite (no auto-select)
    if state.favoriteStopwatchID == id {
      state.$favoriteStopwatchID.withLock { $0 = nil }
    }

    // Clear lastPlayedLocal if we're deleting it
    if state.lastPlayedLocalStopwatchID == id {
      state.$lastPlayedLocalStopwatchID.withLock { $0 = nil }
    }

    // Remove the stopwatch
    state.$stopwatches.withLock { items in
      _ = items.remove(id: id)
    }
  }
}

// MARK: - Equatable Conformance
extension AppFeature.Destination.State: Equatable {}

// MARK: - AppView
/// The root view of the application.
///
/// Uses tree-based navigation with `navigationDestination(item:)` to present detail screens.
/// The floating controls overlay is always visible and adapts to the current navigation context.
///
/// ## Structure
///
/// ```
/// ZStack
/// ├── NavigationStack
/// │   ├── StopwatchListView (root)
/// │   └── .navigationDestination → StopwatchDetailView
/// └── FloatingStopwatchControlsView (overlay)
/// ```

struct AppView: View {
  @Bindable var store: StoreOf<AppFeature>
  
  /// Toggle to switch between V1 (reducer-managed timer) and V2 (TimelineView) detail views.
  /// Set to `true` to test the TimelineView-based approach that fixes the navigation bug.
  private let useTimelineViewDetail = true

  var body: some View {
    ZStack(alignment: .bottom) {
      NavigationStack {
        StopwatchListView(store: store)
          .navigationDestination(
            item: $store.scope(state: \.destination?.stopwatchDetail, action: \.destination.stopwatchDetail)
          ) { detailStore in
            if useTimelineViewDetail {
              // V2: TimelineView-based (no reducer timer, fixes navigation bug)
              StopwatchDetailViewV2(stopwatch: detailStore.$stopwatch)
            } else {
              // V1: Reducer-managed timer (has navigation bug)
              StopwatchDetailView(store: detailStore)
            }
          }
          .safeAreaInset(edge: .bottom) {
            // Reserve space for floating controls
            Color.clear.frame(height: 80)
          }
      }

      // Floating stopwatch controls - always visible, context-aware
      // Note: Removed .transition(.move(edge: .bottom)) as it caused jarring animations
      // when switching between stopwatches (mode changes triggered the transition).
      FloatingStopwatchControlsView(
        store: store.scope(state: \.floatingControls, action: \.floatingControls),
        destination: store.destination,
        currentlyViewingStopwatchID: store.currentlyViewingStopwatchID
      )
    }
  }
}

// MARK: - StopwatchListView
/// The main list view showing all stopwatches.
///
/// Each stopwatch is displayed as a card with:
/// - Title and elapsed time
/// - Running indicator
/// - Play/pause button
/// - Favorite button
///
/// Tapping the card navigates to the detail view.

struct StopwatchListView: View {
  let store: StoreOf<AppFeature>
  
  /// Debug flag to visualize the tappable area. Set to `true` to see a pink overlay.
  private let debugTapArea = false
  
  var body: some View {
    List {
      Section {
        ForEach(Array(store.$stopwatches)) { $stopwatch in
          let id = stopwatch.id
          StopwatchCard(
            stopwatch: $stopwatch,
            onToggle: { store.send(.stopwatchList(.toggleTapped(id))) },
            onFavorite: { store.send(.stopwatchList(.favoriteTapped(id))) }
          )
          // Debug: visualize the tappable area (set debugTapArea = true)
          .background(debugTapArea ? Color.pink.opacity(0.3) : Color.clear)
          // Make the entire row tappable for navigation
          .contentShape(Rectangle())
          .onTapGesture {
            store.send(.stopwatchTapped(id))
          }
          .listRowBackground(Color(.systemBackground))
          .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
        .onDelete { indexSet in
          store.send(.deleteStopwatches(indexSet))
        }

      } header: {
        HStack {
          Text("Stopwatches")
          Spacer()
          Text("\(store.stopwatches.count)")
            .foregroundColor(.secondary)
        }
      }
    }
    .navigationTitle("Stopwatches")
  }
}

// MARK: - Previews

#Preview("App") {
  @Shared(.stopwatches) var stopwatches = [
    StopwatchItem(id: StopwatchItem.ID(UUID()), title: "Meeting", elapsedMilliseconds: 65432),
    StopwatchItem(id: StopwatchItem.ID(UUID()), title: "Workout", elapsedMilliseconds: 120000, isRunning: true, lastStartTime: Date()),
  ]
  
  return AppView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}

#Preview("List with Stopwatches") {
  @Shared(.stopwatches) var stopwatches = [
    StopwatchItem(id: StopwatchItem.ID(UUID()), title: "Meeting", elapsedMilliseconds: 65432),
    StopwatchItem(id: StopwatchItem.ID(UUID()), title: "Workout", isRunning: true, lastStartTime: Date()),
  ]
  
  return NavigationStack {
    StopwatchListView(
      store: Store(initialState: AppFeature.State()) {
        AppFeature()
      }
    )
  }
}
