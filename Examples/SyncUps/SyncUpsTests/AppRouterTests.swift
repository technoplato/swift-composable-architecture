/*
 HOW:
   Run tests via Xcode or `swift test` to verify router behavior.

 WHO:
   Agent (Cursor), User
   (Context: Adding WidgetKit/Live Activity deep linking support)

 WHAT:
   Unit tests for the AppRouter deep linking system.
   Verifies bidirectional URL parsing and generation.

 WHEN:
   2025-12-16
   Last Modified: 2025-12-16

 WHERE:
   SyncUpsTests/AppRouterTests.swift

 WHY:
   Ensures deep links from widgets and Live Activities correctly
   navigate to the intended destinations. Bidirectional testing
   catches both parsing and generation bugs.
*/

import Foundation
import Testing
import URLRouting

@testable import SyncUps

// MARK: - AppRouterTests

@Suite struct AppRouterTests {
  
  // MARK: - Parsing Tests
  
  @Test func parseStopwatchList() throws {
    let url = URL(string: "syncups://stopwatches")!
    let route = try appRouter.match(url: url)
    #expect(route == .stopwatchList)
  }
  
  @Test func parseStopwatchListWithTrailingSlash() throws {
    let url = URL(string: "syncups://stopwatches/")!
    let route = try appRouter.match(url: url)
    #expect(route == .stopwatchList)
  }
  
  @Test func parseStopwatchDetail() throws {
    let uuid = UUID()
    let url = URL(string: "syncups://stopwatches/\(uuid)")!
    let route = try appRouter.match(url: url)
    #expect(route == .stopwatchDetail(id: StopwatchItem.ID(uuid)))
  }
  
  @Test func parseCreateStopwatch() throws {
    let url = URL(string: "syncups://stopwatches/new")!
    let route = try appRouter.match(url: url)
    #expect(route == .createStopwatch)
  }
  
  @Test func parseCreateFavorite() throws {
    let url = URL(string: "syncups://stopwatches/new-favorite")!
    let route = try appRouter.match(url: url)
    #expect(route == .createFavorite)
  }
  
  // MARK: - Generation Tests
  
  @Test func generateStopwatchListPath() {
    let path = appRouter.path(for: .stopwatchList)
    #expect(path == "/stopwatches")
  }
  
  @Test func generateStopwatchDetailPath() {
    let uuid = UUID()
    let id = StopwatchItem.ID(uuid)
    let path = appRouter.path(for: .stopwatchDetail(id: id))
    #expect(path == "/stopwatches/\(uuid.uuidString.uppercased())")
  }
  
  @Test func generateCreateStopwatchPath() {
    let path = appRouter.path(for: .createStopwatch)
    #expect(path == "/stopwatches/new")
  }
  
  @Test func generateCreateFavoritePath() {
    let path = appRouter.path(for: .createFavorite)
    #expect(path == "/stopwatches/new-favorite")
  }
  
  // MARK: - Round-Trip Tests
  
  @Test func roundTripStopwatchDetail() throws {
    let uuid = UUID()
    let id = StopwatchItem.ID(uuid)
    let originalRoute = AppRoute.stopwatchDetail(id: id)
    
    // Generate URL
    let url = try #require(appRouter.url(for: originalRoute))
    
    // Parse back
    let parsedRoute = try appRouter.match(url: url)
    
    #expect(parsedRoute == originalRoute)
  }
  
  @Test func roundTripAllRoutes() throws {
    let testCases: [AppRoute] = [
      .stopwatchList,
      .stopwatchDetail(id: StopwatchItem.ID(UUID())),
      .createStopwatch,
      .createFavorite,
    ]
    
    for originalRoute in testCases {
      let url = try #require(appRouter.url(for: originalRoute))
      let parsedRoute = try appRouter.match(url: url)
      #expect(parsedRoute == originalRoute, "Round-trip failed for \(originalRoute)")
    }
  }
  
  // MARK: - URL Generation Tests
  
  @Test func generateFullURL() throws {
    let uuid = UUID()
    let id = StopwatchItem.ID(uuid)
    let url = try #require(appRouter.url(for: .stopwatchDetail(id: id)))
    
    #expect(url.scheme == "syncups")
    #expect(url.absoluteString.contains(uuid.uuidString.uppercased()))
  }
  
  // MARK: - Edge Cases
  
  @Test func invalidURLThrows() {
    let url = URL(string: "syncups://invalid/path")!
    #expect(throws: Error.self) {
      _ = try appRouter.match(url: url)
    }
  }
  
  @Test func wrongSchemeStillParses() throws {
    // The router doesn't validate scheme - that's the app's responsibility
    let url = URL(string: "https://stopwatches")!
    let route = try appRouter.match(url: url)
    #expect(route == .stopwatchList)
  }
}




