import ComposableArchitecture
import Foundation
import Testing

@testable import SyncUps

@MainActor
struct SyncUpsListTests {
  init() { uncheckedUseMainSerialExecutor = true }

  @Test
  func add() async throws {
    let store = TestStore(initialState: SyncUpsList.State()) {
      SyncUpsList()
    } withDependencies: {
      $0.uuid = .incrementing
    }

    var syncUp = SyncUp(
      id: SyncUp.ID(UUID(0)),
      attendees: [
        Attendee(id: Attendee.ID(UUID(1)))
      ]
    )
    // addSyncUpButtonTapped creates the sync-up immediately as a draft and opens the form
    await store.send(.addSyncUpButtonTapped) {
      $0.$syncUps.withLock { _ = $0.append(syncUp) }
      $0.destination = .add(SyncUpForm.State(syncUp: syncUp))
    }

    syncUp.title = "Engineering"
    await store.send(\.destination.add.binding.syncUp, syncUp) {
      $0.destination?.modify(\.add) { $0.syncUp.title = "Engineering" }
    }

    // saveSyncUpButtonTapped marks it as active
    syncUp.status = .active
    await store.send(.saveSyncUpButtonTapped) {
      $0.destination = nil
      $0.$syncUps.withLock { $0[id: syncUp.id] = syncUp }
    }
  }

  @Test
  func addAndConfirmValidatesAttendees() async throws {
    @Dependency(\.uuid) var uuid

    // The sync-up already exists as a draft (created when add button was tapped)
    let draftSyncUp = SyncUp(
      id: SyncUp.ID(uuidString: "deadbeef-dead-beef-dead-beefdeadbeef")!,
      attendees: [
        Attendee(id: Attendee.ID(uuid()), name: ""),
        Attendee(id: Attendee.ID(uuid()), name: "    "),
      ],
      title: "Design"
    )

    @Shared(.syncUps) var syncUps = [draftSyncUp]

    let store = TestStore(
      initialState: SyncUpsList.State(
        destination: .add(SyncUpForm.State(syncUp: draftSyncUp))
      )
    ) {
      SyncUpsList()
    } withDependencies: {
      $0.uuid = .incrementing
    }

    // saveSyncUpButtonTapped validates attendees and marks as active
    await store.send(.saveSyncUpButtonTapped) {
      $0.destination = nil
      $0.$syncUps.withLock {
        var savedSyncUp = SyncUp(
          id: SyncUp.ID(uuidString: "deadbeef-dead-beef-dead-beefdeadbeef")!,
          attendees: [
            Attendee(id: Attendee.ID(UUID(0)))
          ],
          title: "Design"
        )
        savedSyncUp.status = .active
        $0 = [savedSyncUp]
      }
    }
  }
}
