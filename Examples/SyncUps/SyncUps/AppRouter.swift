/*
 HOW:
   Import this file and use `appRouter` to parse/generate deep link URLs.
   
   [Inputs]
   - URL: A deep link URL (e.g., syncups://stopwatches/123)
   
   [Outputs]
   - AppRoute: A type-safe route enum case
   
   [Side Effects]
   - None (pure parsing/generation)

 WHO:
   Agent (Cursor), User
   (Context: Adding WidgetKit/Live Activity deep linking support)

 WHAT:
   Type-safe, bidirectional URL routing for the SyncUps stopwatch app.
   Uses swift-url-routing for compile-time safe URL parsing and generation.
   
   Supports routes for:
   - Stopwatch list (root)
   - Stopwatch detail (by ID)
   - Create new stopwatch
   - Create new favorite (recording)

 WHEN:
   2025-12-16
   Last Modified: 2025-12-16
   [Change Log:
     - 2025-12-16: Initial creation for widget/Live Activity deep linking
   ]

 WHERE:
   SyncUps/AppRouter.swift

 WHY:
   Widgets and Live Activities need to deep link into the app to navigate
   to specific stopwatches. Using swift-url-routing provides:
   1. Type safety - routes are enum cases, not stringly-typed
   2. Bidirectionality - can both parse URLs and generate them
   3. Testability - easy to unit test routing logic
   4. Consistency - same router used for widgets, Live Activities, and universal links
*/

import Foundation
import Tagged
import URLRouting

// MARK: - App Route

/// All possible navigation destinations accessible via deep links.
///
/// This enum is the single source of truth for app navigation targets.
/// Used by:
/// - Widget tap handlers (NavigateToStopwatchIntent)
/// - Live Activity tap handlers
/// - Universal links (if configured)
/// - App-internal navigation (for consistency)
///
/// ## URL Scheme
///
/// The app uses the `syncups://` scheme. Examples:
/// - `syncups://stopwatches` → list view
/// - `syncups://stopwatches/{uuid}` → detail view
/// - `syncups://stopwatches/new` → create new stopwatch
/// - `syncups://stopwatches/new-favorite` → create and set as favorite
///
/// ## Example Usage
///
/// ```swift
/// // Parse incoming URL
/// if let route = try? appRouter.match(url: url) {
///   switch route {
///   case .stopwatchList:
///     state.destination = nil
///   case let .stopwatchDetail(id):
///     // Navigate to detail
///   case .createStopwatch:
///     // Create new stopwatch
///   case .createFavorite:
///     // Create new favorite
///   }
/// }
///
/// // Generate URL for widget
/// let url = appRouter.url(for: .stopwatchDetail(id: stopwatch.id))
/// ```
enum AppRoute: Equatable {
  /// Navigate to the stopwatch list (root view).
  case stopwatchList
  
  /// Navigate to a specific stopwatch's detail view.
  case stopwatchDetail(id: StopwatchItem.ID)
  
  /// Create a new stopwatch (not favorite).
  case createStopwatch
  
  /// Create a new stopwatch and set it as the favorite (active recording).
  case createFavorite
}

// MARK: - Router Definition

/// The bidirectional router for parsing and generating app URLs.
///
/// Uses swift-url-routing's `OneOf` combinator to try each route in order.
/// Routes are matched top-to-bottom, so more specific routes should come first.
///
/// ## Thread Safety
///
/// This router is stateless and can be used from any thread.
///
/// ## Performance
///
/// Parsing is O(n) where n is the number of routes. With only 4 routes,
/// this is effectively O(1) for practical purposes.
let appRouter = OneOf {
  // GET /stopwatches/new-favorite (must come before /stopwatches/:id)
  Route(.case(AppRoute.createFavorite)) {
    Path { "stopwatches"; "new-favorite" }
  }
  
  // GET /stopwatches/new (must come before /stopwatches/:id)
  Route(.case(AppRoute.createStopwatch)) {
    Path { "stopwatches"; "new" }
  }
  
  // GET /stopwatches/:id
  Route(.case(AppRoute.stopwatchDetail)) {
    Path { "stopwatches" }
    Path { StopwatchItem.ID.parser() }
  }
  
  // GET /stopwatches (root)
  Route(.case(AppRoute.stopwatchList)) {
    Path { "stopwatches" }
  }
}

// MARK: - Tagged UUID Parser

/// Parser for `Tagged<StopwatchItem, UUID>` to enable type-safe ID parsing.
///
/// This extension allows the router to parse UUID strings directly into
/// the strongly-typed `StopwatchItem.ID` (which is `Tagged<StopwatchItem, UUID>`).
extension Tagged: ParserPrinter where RawValue == UUID {
  public var body: some ParserPrinter<Substring.UTF8View, Self> {
    UUID.parser().map(.memberwise(Self.init(rawValue:)))
  }
}

// MARK: - URL Scheme Configuration

/// The URL scheme used for deep links into the app.
///
/// This should match the URL scheme configured in Info.plist under
/// `CFBundleURLTypes` → `CFBundleURLSchemes`.
let appURLScheme = "syncups"

// MARK: - Router Convenience Extensions

extension ParserPrinter where Input == URLRequestData, Output == AppRoute {
  /// Attempts to match a URL against this router.
  ///
  /// - Parameter url: The URL to match (must use the app's URL scheme)
  /// - Returns: The matched route, or throws if no match
  /// - Throws: Parsing error if the URL doesn't match any route
  ///
  /// ## Example
  ///
  /// ```swift
  /// let url = URL(string: "syncups://stopwatches/123e4567-e89b-12d3-a456-426614174000")!
  /// let route = try appRouter.match(url: url)
  /// // route == .stopwatchDetail(id: ...)
  /// ```
  func match(url: URL) throws -> AppRoute {
    try self.parse(URLRequestData(url: url)!)
  }
  
  /// Generates a URL for the given route.
  ///
  /// - Parameter route: The route to generate a URL for
  /// - Returns: The generated URL, or nil if generation fails
  ///
  /// ## Example
  ///
  /// ```swift
  /// let id = StopwatchItem.ID(UUID())
  /// let url = appRouter.url(for: .stopwatchDetail(id: id))
  /// // url == URL(string: "syncups://stopwatches/\(id)")
  /// ```
  func url(for route: AppRoute) -> URL? {
    guard let request = try? self.print(route) else { return nil }
    var components = URLComponents()
    components.scheme = appURLScheme
    components.host = request.path.first.map(String.init)
    components.path = "/" + request.path.dropFirst().joined(separator: "/")
    return components.url
  }
  
  /// Generates just the path component for the given route.
  ///
  /// Useful for debugging or logging without the scheme.
  ///
  /// - Parameter route: The route to generate a path for
  /// - Returns: The path string (e.g., "/stopwatches/123")
  func path(for route: AppRoute) -> String {
    guard let request = try? self.print(route) else { return "/" }
    return "/" + request.path.joined(separator: "/")
  }
}


