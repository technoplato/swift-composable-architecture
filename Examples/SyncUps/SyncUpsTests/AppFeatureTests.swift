import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import SyncUps

// MARK: - AppFeatureTests
/// Tests for the AppFeature reducer and its integration with FloatingStopwatchControls.

@MainActor
struct AppFeatureTests {
  init() { uncheckedUseMainSerialExecutor = true }

  // MARK: - Navigation Tests

  @Test
  func navigateToStopwatchDetail() async throws {
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(id: stopwatchID, title: "Test Stopwatch")

    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatchID

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    // Navigate to favorite detail via floating controls
    let sharedStopwatch = try #require(Shared($stopwatches[id: stopwatchID]))

    await store.send(.floatingControls(.navigateToFavoriteDetailTapped))
    await store.receive(\.floatingControls.delegate.navigateToStopwatch) {
      $0.destination = .stopwatchDetail(StopwatchDetail.State(stopwatch: sharedStopwatch))
    }

    // Verify we're viewing the favorite's detail
    #expect(store.state.isViewingFavoriteDetail == true)
  }

  @Test
  func dismissStopwatchDetail() async throws {
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(id: stopwatchID, title: "Test Stopwatch")

    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatchID

    let sharedStopwatch = try #require(Shared($stopwatches[id: stopwatchID]))

    let store = TestStore(
      initialState: AppFeature.State(
        destination: .stopwatchDetail(StopwatchDetail.State(stopwatch: sharedStopwatch))
      )
    ) {
      AppFeature()
    }

    // Verify we're viewing the detail
    #expect(store.state.isViewingFavoriteDetail == true)

    // Dismiss via destination binding
    await store.send(.destination(.dismiss)) {
      $0.destination = nil
    }

    // Verify we're back on the list
    #expect(store.state.isViewingFavoriteDetail == false)
  }

  // MARK: - Floating Controls Tests

  @Test
  func floatingControlsToggleFavoritePlayback() async throws {
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let startTime = Date(timeIntervalSince1970: 1_000_000)
    let stopwatch = StopwatchItem(
      id: stopwatchID,
      title: "Test Stopwatch",
      elapsedMilliseconds: 5000,
      isRunning: false
    )

    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatchID

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.date.now = startTime
    }

    // Verify initial state - favorite is paused
    #expect(store.state.stopwatches[id: stopwatchID]?.isRunning == false)

    // Toggle (start) the favorite
    await store.send(.floatingControls(.toggleFavoritePlayback)) {
      $0.$stopwatches.withLock { items in
        items[id: stopwatchID]?.isRunning = true
        items[id: stopwatchID]?.lastStartTime = startTime
      }
    }

    #expect(store.state.stopwatches[id: stopwatchID]?.isRunning == true)

    // Toggle (pause) the favorite
    await store.send(.floatingControls(.toggleFavoritePlayback)) {
      $0.$stopwatches.withLock { items in
        items[id: stopwatchID]?.isRunning = false
        items[id: stopwatchID]?.lastStartTime = nil
      }
    }

    #expect(store.state.stopwatches[id: stopwatchID]?.isRunning == false)
  }

  @Test
  func floatingControlsDeleteFavorite() async {
    let stopwatch1ID = StopwatchItem.ID(UUID(0))
    let stopwatch2ID = StopwatchItem.ID(UUID(1))

    let stopwatch1 = StopwatchItem(id: stopwatch1ID, title: "Stopwatch 1")
    let stopwatch2 = StopwatchItem(id: stopwatch2ID, title: "Stopwatch 2")

    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [
      stopwatch1, stopwatch2,
    ]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatch1ID

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    // Delete the favorite - should auto-select next
    await store.withExhaustivity(.off) {
      await store.send(.floatingControls(.deleteFavoriteTapped))
      await store.receive(\.floatingControls.delegate.deleteRequested)
    }

    #expect(store.state.favoriteStopwatchID == stopwatch2ID)
    #expect(store.state.stopwatches.count == 1)
  }

  @Test
  func floatingControlsUnfavorite() async {
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(id: stopwatchID, title: "My Stopwatch")

    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatchID

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    #expect(store.state.favoriteStopwatchID == stopwatchID)

    await store.send(.floatingControls(.unfavoriteTapped)) {
      $0.$favoriteStopwatchID.withLock { $0 = nil }
    }

    #expect(store.state.favoriteStopwatchID == nil)
    #expect(store.state.stopwatches.count == 1) // Stopwatch still exists
  }

  // MARK: - Create New Favorite Tests

  @Test
  func createNewFavorite_shouldNavigateToDetail() async {
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = []
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = nil

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSince1970: 1_000_000)
    }

    #expect(store.state.stopwatches.isEmpty)
    #expect(store.state.favoriteStopwatchID == nil)

    let expectedID = StopwatchItem.ID(UUID(0))

    // Create new favorite from floating controls (idle mode)
    await store.withExhaustivity(.off) {
      await store.send(.floatingControls(.createNewStopwatchTapped))
      await store.receive(\.floatingControls.delegate.createAndNavigateToNewFavorite)
    }

    #expect(store.state.stopwatches.count == 1)
    #expect(store.state.favoriteStopwatchID == expectedID)
    #expect(store.state.destination != nil)
  }

  // MARK: - Mode Derivation Tests

  @Test
  func modeDerivation_listNoFavoriteNoPlayback_idle() async {
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = []
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = nil

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    // On list (nil viewing ID), no favorite, no playback → idle mode
    let mode = store.state.floatingControls.mode(currentlyViewingStopwatchID: nil)
    #expect(mode == .idle)
  }

  @Test
  func modeDerivation_listWithFavorite_listFavoriteOnly() async {
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(id: stopwatchID, title: "Favorite")

    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatchID

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    // On list, has favorite, no non-favorite playing
    let mode = store.state.floatingControls.mode(currentlyViewingStopwatchID: nil)
    if case .listFavoriteOnly(let favID) = mode {
      #expect(favID == stopwatchID)
    } else {
      Issue.record("Expected listFavoriteOnly mode, got \(mode)")
    }
  }

  // MARK: - Bug Fix Tests

  @Test
  func deletingLastFavoritedStopwatch_setsToNil() async throws {
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(id: stopwatchID, title: "Only Stopwatch")

    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatchID

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    #expect(store.state.stopwatches.count == 1)
    #expect(store.state.favoriteStopwatchID == stopwatchID)

    await store.withExhaustivity(.off) {
      await store.send(.floatingControls(.deleteFavoriteTapped))
      await store.receive(\.floatingControls.delegate.deleteRequested)
    }

    #expect(store.state.stopwatches.count == 0)
    #expect(store.state.favoriteStopwatchID == nil)
  }

  @Test
  func idBasedSubscript_safelyHandlesDeletion() async throws {
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(id: stopwatchID, title: "Test")

    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatchID

    // CORRECT PATTERN: ID-based subscript returns optional
    let sharedStopwatchBefore = Shared($stopwatches[id: stopwatchID])
    #expect(sharedStopwatchBefore != nil)

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    await store.withExhaustivity(.off) {
      await store.send(.floatingControls(.deleteFavoriteTapped))
      await store.receive(\.floatingControls.delegate.deleteRequested)
    }

    // SAFE: ID-based subscript returns nil after deletion
    let sharedStopwatchAfter = Shared($stopwatches[id: stopwatchID])
    #expect(sharedStopwatchAfter == nil)
  }
}
