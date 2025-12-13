import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import SyncUps

@MainActor
struct AppFeatureTests {
  init() { uncheckedUseMainSerialExecutor = true }

  @Test
  func detailEdit() async throws {
    let syncUp = SyncUp.mock
    @Shared(.syncUps) var syncUps = [syncUp]
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    let sharedSyncUp = try #require(Shared($syncUps[id: syncUp.id]))

    await store.send(\.path.push, (id: 0, .detail(SyncUpDetail.State(syncUp: sharedSyncUp)))) {
      $0.path[id: 0] = .detail(SyncUpDetail.State(syncUp: sharedSyncUp))
    }

    await store.send(\.path[id: 0].detail.editButtonTapped) {
      $0.path[id: 0]?.modify(\.detail) { $0.destination = .edit(SyncUpForm.State(syncUp: syncUp)) }
    }

    var newSyncUp = syncUp
    newSyncUp.title = "Blob"
    await store.send(\.path[id: 0].detail.destination.edit.binding.syncUp, newSyncUp) {
      $0.path[id: 0]?.modify(\.detail) {
        $0.destination?.modify(\.edit) { $0.syncUp.title = "Blob" }
      }
    }

    await store.send(\.path[id: 0].detail.doneEditingButtonTapped) {
      $0.path[id: 0]?.modify(\.detail) {
        $0.destination = nil
        $0.$syncUp.withLock { $0.title = "Blob" }
      }
    }
    .finish()
  }

  @Test
  func delete() async throws {
    let syncUp = SyncUp.mock
    @Shared(.syncUps) var syncUps = [syncUp]
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    let sharedSyncUp = try #require(Shared($syncUps[id: syncUp.id]))

    await store.send(\.path.push, (id: 0, .detail(SyncUpDetail.State(syncUp: sharedSyncUp)))) {
      $0.path[id: 0] = .detail(SyncUpDetail.State(syncUp: sharedSyncUp))
    }

    await store.send(\.path[id: 0].detail.deleteButtonTapped) {
      $0.path[id: 0]?.modify(\.detail) { $0.destination = .alert(.deleteSyncUp) }
    }

    await store.send(\.path[id: 0].detail.destination.alert.confirmDeletion) {
      $0.path[id: 0]?.modify(\.detail) { $0.destination = nil }
      $0.syncUpsList.$syncUps.withLock { $0 = [] }
    }

    await store.receive(\.path.popFrom) {
      $0.path = StackState()
    }
  }

  @Test
  func recording() async {
    let speechResult = SpeechRecognitionResult(
      bestTranscription: Transcription(formattedString: "I completed the project"),
      isFinal: true
    )
    let syncUp = SyncUp(
      id: SyncUp.ID(),
      attendees: [
        Attendee(id: Attendee.ID()),
        Attendee(id: Attendee.ID()),
        Attendee(id: Attendee.ID()),
      ],
      duration: .seconds(6)
    )

    let sharedSyncUp = Shared(value: syncUp)
    let store = TestStore(
      initialState: AppFeature.State(
        path: StackState([
          .detail(SyncUpDetail.State(syncUp: sharedSyncUp)),
          .record(RecordMeeting.State(syncUp: sharedSyncUp)),
        ])
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_234_567_890)
      $0.continuousClock = ImmediateClock()
      $0.speechClient.authorizationStatus = { .authorized }
      $0.speechClient.startTask = { @Sendable _ in
        AsyncThrowingStream { continuation in
          continuation.yield(speechResult)
          continuation.finish()
        }
      }
      $0.uuid = .incrementing
    }

    await store.withExhaustivity(.off) {
      await store.send(\.path[id: 1].record.onTask)
      await store.receive(\.path.popFrom) {
        #expect($0.path.count == 1)
      }
    }
    await store.finish()
    store.assert {
      $0.path[id: 0]?.modify(\.detail) {
        $0.$syncUp.withLock {
          $0.meetings = [
            Meeting(
              id: Meeting.ID(UUID(0)),
              date: Date(timeIntervalSince1970: 1_234_567_890),
              transcript: "I completed the project"
            )
          ]
        }
      }
    }
  }

  @Test
  func floatingStopwatchToggleAndNavigate() async throws {
    // Create stopwatches with controlled UUIDs
    let stopwatch1ID = StopwatchItem.ID(UUID(0))
    let stopwatch2ID = StopwatchItem.ID(UUID(1))
    let stopwatch3ID = StopwatchItem.ID(UUID(2))

    let startTime = Date(timeIntervalSince1970: 1_000_000)

    let stopwatch1 = StopwatchItem(
      id: stopwatch1ID,
      title: "Stopwatch 1",
      elapsedMilliseconds: 0,
      isRunning: true,
      lastStartTime: startTime
    )
    let stopwatch2 = StopwatchItem(
      id: stopwatch2ID,
      title: "Stopwatch 2",
      elapsedMilliseconds: 5000,
      isRunning: false
    )
    let stopwatch3 = StopwatchItem(
      id: stopwatch3ID,
      title: "Stopwatch 3",
      elapsedMilliseconds: 10000,
      isRunning: false
    )

    // Set up shared state
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [
      stopwatch1,
      stopwatch2,
      stopwatch3,
    ]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatch2ID

    // Time after 3 seconds
    let pauseTime = Date(timeIntervalSince1970: 1_000_003)

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.date.now = pauseTime
      $0.uuid = .incrementing
    }

    // Verify initial state - stopwatch 2 is favorite and paused
    #expect(store.state.favoriteStopwatchID == stopwatch2ID)
    #expect(store.state.favoriteStopwatch?.isRunning == false)
    #expect(store.state.favoriteStopwatch?.elapsedMilliseconds == 5000)

    // Toggle (start) the favorite stopwatch
    await store.send(.floatingStopwatch(.toggleTapped)) {
      // Stopwatch 2 should now be running with lastStartTime set
      $0.$stopwatches.withLock { stopwatches in
        stopwatches[id: stopwatch2ID]?.isRunning = true
        stopwatches[id: stopwatch2ID]?.lastStartTime = pauseTime
      }
    }

    // Verify it's running
    #expect(store.state.favoriteStopwatch?.isRunning == true)

    // Toggle (pause) the favorite stopwatch
    await store.send(.floatingStopwatch(.toggleTapped)) {
      // Stopwatch 2 should now be paused with elapsed time updated
      $0.$stopwatches.withLock { stopwatches in
        // Since we paused at the same time we started, elapsed stays at 5000
        stopwatches[id: stopwatch2ID]?.elapsedMilliseconds = 5000
        stopwatches[id: stopwatch2ID]?.isRunning = false
        stopwatches[id: stopwatch2ID]?.lastStartTime = nil
      }
    }

    // Verify it's paused
    #expect(store.state.favoriteStopwatch?.isRunning == false)

    // Now navigate to the stopwatch detail
    let sharedStopwatch = try #require(Shared($stopwatches[id: stopwatch2ID]))

    await store.send(\.path.push, (id: 0, .stopwatchDetail(StopwatchDetail.State(stopwatch: sharedStopwatch)))) {
      $0.path[id: 0] = .stopwatchDetail(StopwatchDetail.State(stopwatch: sharedStopwatch))
    }

    // Verify we're viewing the favorite's detail
    #expect(store.state.isViewingFavoriteDetail == true)

    // Pop back
    await store.send(\.path.popFrom, 0) {
      $0.path = StackState()
    }

    // Verify we're no longer viewing the favorite's detail
    #expect(store.state.isViewingFavoriteDetail == false)
  }

  @Test
  func floatingStopwatchDelete() async {
    let stopwatch1ID = StopwatchItem.ID(UUID(0))
    let stopwatch2ID = StopwatchItem.ID(UUID(1))
    let stopwatch3ID = StopwatchItem.ID(UUID(2))

    let stopwatch1 = StopwatchItem(id: stopwatch1ID, title: "Stopwatch 1")
    let stopwatch2 = StopwatchItem(id: stopwatch2ID, title: "Stopwatch 2")
    let stopwatch3 = StopwatchItem(id: stopwatch3ID, title: "Stopwatch 3")

    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [
      stopwatch1,
      stopwatch2,
      stopwatch3,
    ]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatch2ID

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    // Delete the favorite - should auto-select next (stopwatch3)
    await store.send(.floatingStopwatch(.deleteTapped)) {
      $0.$favoriteStopwatchID.withLock { $0 = stopwatch3ID }
      $0.$stopwatches.withLock { _ = $0.remove(id: stopwatch2ID) }
    }

    #expect(store.state.favoriteStopwatchID == stopwatch3ID)
    #expect(store.state.stopwatches.count == 2)
  }

  @Test
  func floatingStopwatchUnfavorite() async {
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(id: stopwatchID, title: "My Stopwatch")

    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatchID

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    }

    #expect(store.state.favoriteStopwatchID == stopwatchID)

    await store.send(.floatingStopwatch(.unfavoriteTapped)) {
      $0.$favoriteStopwatchID.withLock { $0 = nil }
    }

    #expect(store.state.favoriteStopwatchID == nil)
    // Stopwatch should still exist
    #expect(store.state.stopwatches.count == 1)
  }
}
