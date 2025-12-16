/*
 HOW:
   Run tests via Xcode or `swift test` to verify Live Activity integration.

 WHO:
   Agent (Cursor), User
   (Context: Adding WidgetKit/Live Activity support)

 WHAT:
   Integration tests for Live Activity management in AppFeature.
   Verifies correct start/update/end calls to ActivityKitClient.

 WHEN:
   2025-12-16
   Last Modified: 2025-12-16

 WHERE:
   SyncUpsTests/LiveActivityTests.swift

 WHY:
   Ensures Live Activities are correctly managed in response to
   favorite stopwatch changes. Uses TCA's TestStore and dependency
   injection to verify ActivityKitClient calls without real activities.
*/

import ActivityKit
import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import SyncUps

// MARK: - Live Activity Tests

@MainActor
@Suite struct LiveActivityTests {
  init() { uncheckedUseMainSerialExecutor = true }
  
  // MARK: - Start Activity Tests
  
  @Test func startsLiveActivityWhenFavoriteCreated() async throws {
    let activityStarted = LockIsolated<(StopwatchAttributes, StopwatchAttributes.ContentState)?>(nil)
    
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = []
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = nil
    @Shared(.activeLiveActivityID) var activeLiveActivityID: String? = nil
    
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
      LiveActivityReducer()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.date = .constant(Date(timeIntervalSince1970: 0))
      $0.activityKit.start = { attrs, state in
        activityStarted.setValue((attrs, state))
        return "test-activity-123"
      }
    }
    
    // Create a new favorite via floating controls
    await store.send(.floatingControls(.delegate(.createAndNavigateToNewFavorite))) {
      // State changes from main reducer
      let newID = StopwatchItem.ID(UUID(0))
      $0.$stopwatches.withLock { items in
        items.append(StopwatchItem(
          id: newID,
          title: "Stopwatch 1",
          isRunning: true,
          lastStartTime: Date(timeIntervalSince1970: 0)
        ))
      }
      $0.$favoriteStopwatchID.withLock { $0 = newID }
      
      // Navigation
      if let shared = Shared($0.$stopwatches[id: newID]) {
        $0.destination = .stopwatchDetail(StopwatchDetail.State(stopwatch: shared))
      }
    }
    
    // Verify Live Activity was started
    await store.receive(\.liveActivity.activityStarted) {
      $0.$activeLiveActivityID.withLock { $0 = "test-activity-123" }
    }
    
    // Verify correct attributes were passed
    let started = try #require(activityStarted.value)
    #expect(started.0.title == "Stopwatch 1")
    #expect(started.1.isRunning == true)
    #expect(started.1.hasFavorite == true)
  }
  
  @Test func startsLiveActivityWhenExistingStopwatchBecomeFavorite() async throws {
    let activityStarted = LockIsolated<String?>(nil)
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(
      id: stopwatchID,
      title: "Existing Stopwatch",
      elapsedMilliseconds: 5000,
      isRunning: false
    )
    
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = nil
    
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
      LiveActivityReducer()
    } withDependencies: {
      $0.activityKit.start = { _, _ in
        activityStarted.setValue("activity-for-existing")
        return "activity-for-existing"
      }
    }
    
    // Favorite an existing stopwatch
    await store.send(.stopwatchList(.favoriteTapped(stopwatchID))) {
      $0.$favoriteStopwatchID.withLock { $0 = stopwatchID }
    }
    
    // Verify Live Activity was started
    await store.receive(\.liveActivity.activityStarted) {
      $0.$activeLiveActivityID.withLock { $0 = "activity-for-existing" }
    }
    
    #expect(activityStarted.value == "activity-for-existing")
  }
  
  // MARK: - Update Activity Tests
  
  @Test func updatesLiveActivityWhenFavoriteToggled() async throws {
    let updateCalls = LockIsolated<[StopwatchAttributes.ContentState]>([])
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(
      id: stopwatchID,
      title: "Recording",
      isRunning: true,
      lastStartTime: Date()
    )
    
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatchID
    @Shared(.activeLiveActivityID) var activeLiveActivityID: String? = "existing-activity"
    
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
      LiveActivityReducer()
    } withDependencies: {
      $0.date = .constant(Date(timeIntervalSince1970: 1000))
      $0.activityKit.update = { _, state in
        updateCalls.withValue { $0.append(state) }
      }
    }
    
    // Toggle the favorite (pause it)
    await store.send(.stopwatchList(.toggleTapped(stopwatchID))) {
      $0.$stopwatches.withLock { items in
        items[id: stopwatchID]?.toggle(now: Date(timeIntervalSince1970: 1000))
      }
    }
    
    // Verify Live Activity was updated
    await store.receive(\.liveActivity.activityUpdated)
    
    #expect(updateCalls.value.count == 1)
    #expect(updateCalls.value.first?.isRunning == false)
  }
  
  @Test func updatesLiveActivityWhenNonFavoriteStarts() async throws {
    let updateCalls = LockIsolated<Int>(0)
    let favoriteID = StopwatchItem.ID(UUID(0))
    let playbackID = StopwatchItem.ID(UUID(1))
    
    let favorite = StopwatchItem(id: favoriteID, title: "Recording", isRunning: true, lastStartTime: Date())
    let playback = StopwatchItem(id: playbackID, title: "Reference Audio", isRunning: false)
    
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [favorite, playback]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = favoriteID
    @Shared(.activeLiveActivityID) var activeLiveActivityID: String? = "recording-activity"
    
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
      LiveActivityReducer()
    } withDependencies: {
      $0.date = .constant(Date(timeIntervalSince1970: 1000))
      $0.activityKit.update = { _, state in
        updateCalls.withValue { $0 += 1 }
        // Verify dual mode is indicated
        #expect(state.hasPlayingNonFavorite == true)
        #expect(state.playingNonFavoriteTitle == "Reference Audio")
      }
    }
    
    // Start the non-favorite (playback)
    await store.send(.stopwatchList(.toggleTapped(playbackID))) {
      $0.$stopwatches.withLock { items in
        items[id: playbackID]?.toggle(now: Date(timeIntervalSince1970: 1000))
      }
      $0.$lastPlayedLocalStopwatchID.withLock { $0 = playbackID }
    }
    
    // Verify Live Activity was updated with dual mode
    await store.receive(\.liveActivity.activityUpdated)
    
    #expect(updateCalls.value == 1)
  }
  
  // MARK: - End Activity Tests
  
  @Test func endsLiveActivityWhenFavoriteDeleted() async throws {
    let endedActivityID = LockIsolated<String?>(nil)
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(id: stopwatchID, title: "Recording")
    
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatchID
    @Shared(.activeLiveActivityID) var activeLiveActivityID: String? = "activity-to-end"
    
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
      LiveActivityReducer()
    } withDependencies: {
      $0.activityKit.end = { id, _, _ in
        endedActivityID.setValue(id)
      }
    }
    
    // Delete the favorite via floating controls
    await store.send(.floatingControls(.delegate(.deleteRequested(stopwatchID)))) {
      $0.$favoriteStopwatchID.withLock { $0 = nil }
      $0.$stopwatches.withLock { _ = $0.remove(id: stopwatchID) }
    }
    
    // Verify Live Activity was ended
    await store.receive(\.liveActivity.activityEnded) {
      $0.$activeLiveActivityID.withLock { $0 = nil }
    }
    
    #expect(endedActivityID.value == "activity-to-end")
  }
  
  @Test func endsLiveActivityWhenFavoriteUnfavorited() async throws {
    let endedActivityID = LockIsolated<String?>(nil)
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(id: stopwatchID, title: "Recording")
    
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID: StopwatchItem.ID? = stopwatchID
    @Shared(.activeLiveActivityID) var activeLiveActivityID: String? = "activity-to-end"
    
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
      LiveActivityReducer()
    } withDependencies: {
      $0.activityKit.end = { id, _, _ in
        endedActivityID.setValue(id)
      }
    }
    
    // Unfavorite by tapping favorite button again
    await store.send(.stopwatchList(.favoriteTapped(stopwatchID))) {
      $0.$favoriteStopwatchID.withLock { $0 = nil }
    }
    
    // Verify Live Activity was ended
    await store.receive(\.liveActivity.activityEnded) {
      $0.$activeLiveActivityID.withLock { $0 = nil }
    }
    
    #expect(endedActivityID.value == "activity-to-end")
  }
  
  // MARK: - Deep Link Tests
  
  @Test func handlesDeepLinkToStopwatchDetail() async throws {
    let stopwatchID = StopwatchItem.ID(UUID(0))
    let stopwatch = StopwatchItem(id: stopwatchID, title: "Test Stopwatch")
    
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = [stopwatch]
    
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
      LiveActivityReducer()
    }
    
    // Simulate deep link from widget
    let url = URL(string: "syncups://stopwatches/\(stopwatchID.rawValue)")!
    
    await store.send(.liveActivity(.deepLinkReceived(url))) {
      if let shared = Shared($0.$stopwatches[id: stopwatchID]) {
        $0.destination = .stopwatchDetail(StopwatchDetail.State(stopwatch: shared))
      }
    }
  }
  
  @Test func handlesDeepLinkToCreateFavorite() async throws {
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = []
    
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
      LiveActivityReducer()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.date = .constant(Date(timeIntervalSince1970: 0))
      $0.activityKit.start = { _, _ in "new-activity" }
    }
    
    // Simulate deep link to create favorite
    let url = URL(string: "syncups://stopwatches/new-favorite")!
    
    await store.send(.liveActivity(.deepLinkReceived(url)))
    
    // Should trigger createAndNavigateToNewFavorite
    await store.receive(\.floatingControls.delegate.createAndNavigateToNewFavorite) {
      let newID = StopwatchItem.ID(UUID(0))
      $0.$stopwatches.withLock { items in
        items.append(StopwatchItem(
          id: newID,
          title: "Stopwatch 1",
          isRunning: true,
          lastStartTime: Date(timeIntervalSince1970: 0)
        ))
      }
      $0.$favoriteStopwatchID.withLock { $0 = newID }
      
      if let shared = Shared($0.$stopwatches[id: newID]) {
        $0.destination = .stopwatchDetail(StopwatchDetail.State(stopwatch: shared))
      }
    }
    
    await store.receive(\.liveActivity.activityStarted) {
      $0.$activeLiveActivityID.withLock { $0 = "new-activity" }
    }
  }
  
  // MARK: - Error Handling Tests
  
  @Test func handlesActivityStartError() async throws {
    @Shared(.stopwatches) var stopwatches: IdentifiedArrayOf<StopwatchItem> = []
    
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
      LiveActivityReducer()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.date = .constant(Date(timeIntervalSince1970: 0))
      $0.activityKit.start = { _, _ in
        throw ActivityKitClientError.activitiesDisabled
      }
    }
    
    await store.send(.floatingControls(.delegate(.createAndNavigateToNewFavorite))) {
      let newID = StopwatchItem.ID(UUID(0))
      $0.$stopwatches.withLock { items in
        items.append(StopwatchItem(
          id: newID,
          title: "Stopwatch 1",
          isRunning: true,
          lastStartTime: Date(timeIntervalSince1970: 0)
        ))
      }
      $0.$favoriteStopwatchID.withLock { $0 = newID }
      
      if let shared = Shared($0.$stopwatches[id: newID]) {
        $0.destination = .stopwatchDetail(StopwatchDetail.State(stopwatch: shared))
      }
    }
    
    // Should receive error action instead of success
    await store.receive(\.liveActivity.activityError)
    
    // Activity ID should remain nil
    #expect(store.state.activeLiveActivityID == nil)
  }
}




