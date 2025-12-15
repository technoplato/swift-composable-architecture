import ComposableArchitecture
import IdentifiedCollections
import SwiftUI

// MARK: - FloatingStopwatchControls Feature
/// A context-aware floating control panel that adapts based on navigation and playback state.
///
/// The floating controls are the **sole control surface** for all stopwatch operations.
/// They appear at the bottom of every screen and morph their UI based on three inputs:
///
/// 1. **Navigation context**: What screen is the user viewing? (list, favorite detail, non-favorite detail)
/// 2. **Favorite state**: Does a favorite stopwatch exist?
/// 3. **Playback state**: Is a non-favorite stopwatch currently running?
///
/// ## Mode Matrix
///
/// | Viewing        | Has Favorite | Non-Fav Playing | Mode                              |
/// |----------------|--------------|-----------------|-----------------------------------|
/// | List           | No           | No              | `idle`                            |
/// | List           | No           | Yes             | `listPlaybackOnly`                |
/// | List           | Yes          | No              | `listFavoriteOnly`                |
/// | List           | Yes          | Yes             | `listFavoritePlusPlayback`        |
/// | Fav Detail     | Yes          | No              | `favoriteDetailOnly`              |
/// | Fav Detail     | Yes          | Yes             | `favoriteDetailPlusPlayback`      |
/// | Non-Fav Detail | No           | *               | `nonFavoriteDetailOnly`           |
/// | Non-Fav Detail | Yes          | *               | `nonFavoriteDetailWithFavorite`   |
///
/// ## Architecture
///
/// The floating controls use **delegate actions** to communicate with the parent (AppFeature).
/// This keeps navigation logic centralized and allows the parent to coordinate cross-cutting
/// concerns like the single-playback constraint.
///
/// ```swift
/// // Parent handles navigation via delegate
/// case let .floatingControls(.delegate(.navigateToStopwatch(id))):
///   state.destination = .stopwatchDetail(...)
/// ```
///
/// ## Example Usage
///
/// ```swift
/// FloatingStopwatchControlsView(
///   store: store.scope(state: \.floatingControls, action: \.floatingControls),
///   destination: store.destination,
///   currentlyViewingStopwatchID: store.currentlyViewingStopwatchID
/// )
/// ```

@Reducer
struct FloatingStopwatchControls {
  // MARK: - Mode
  /// The mode determines which UI variant to display.
  ///
  /// Mode is **derived** from three inputs, never stored directly:
  /// 1. Navigation state (passed from parent)
  /// 2. `@Shared(.favoriteStopwatchID)`
  /// 3. `@Shared(.stopwatches)` (to find running non-favorites)
  ///
  /// ## Viewing List Cases
  ///
  /// When `currentlyViewingStopwatchID == nil`:
  ///
  /// - **idle**: No favorite, nothing playing → FAB to create new
  /// - **listPlaybackOnly**: No favorite, non-fav playing → playback controls + create button
  /// - **listFavoriteOnly**: Has favorite, nothing else playing → favorite controls
  /// - **listFavoritePlusPlayback**: Has favorite AND non-fav playing → playback + jump to fav
  ///
  /// ## Viewing Favorite Detail Cases
  ///
  /// When viewing the favorite stopwatch's detail:
  ///
  /// - **favoriteDetailOnly**: No non-fav playing → favorite controls (no jump button)
  /// - **favoriteDetailPlusPlayback**: Non-fav playing → favorite controls + jump to playing
  ///
  /// ## Viewing Non-Favorite Detail Cases
  ///
  /// When viewing a non-favorite stopwatch's detail:
  ///
  /// - **nonFavoriteDetailOnly**: No favorite → contextual controls + create fav button
  /// - **nonFavoriteDetailWithFavorite**: Has favorite → contextual controls + jump to fav
  enum Mode: Equatable {
    // MARK: Viewing List
    
    /// No favorite exists, nothing is playing.
    /// Shows: FAB to create new stopwatch.
    case idle
    
    /// No favorite exists, but a non-favorite is playing.
    /// Shows: Play/pause for playing stopwatch, create new favorite button.
    case listPlaybackOnly(playingID: StopwatchItem.ID)
    
    /// Favorite exists, no non-favorite is playing.
    /// Shows: Play/pause favorite, unfavorite, delete, navigate to detail.
    case listFavoriteOnly(favoriteID: StopwatchItem.ID)
    
    /// Favorite exists AND a non-favorite is playing.
    /// Shows: Play/pause non-favorite, jump to favorite button.
    case listFavoritePlusPlayback(favoriteID: StopwatchItem.ID, playingID: StopwatchItem.ID)
    
    // MARK: Viewing Favorite Detail
    
    /// Viewing favorite detail, no non-favorite is playing.
    /// Shows: Play/pause favorite, unfavorite, delete. NO jump button.
    case favoriteDetailOnly(favoriteID: StopwatchItem.ID)
    
    /// Viewing favorite detail, a non-favorite is playing.
    /// Shows: Play/pause favorite, unfavorite, delete, jump to playing.
    case favoriteDetailPlusPlayback(favoriteID: StopwatchItem.ID, playingID: StopwatchItem.ID)
    
    // MARK: Viewing Non-Favorite Detail
    
    /// Viewing non-favorite detail, no favorite exists.
    /// Shows: Play/pause THIS stopwatch, create new favorite button.
    case nonFavoriteDetailOnly(viewingID: StopwatchItem.ID)
    
    /// Viewing non-favorite detail, favorite exists.
    /// Shows: Play/pause THIS stopwatch, jump to favorite button.
    case nonFavoriteDetailWithFavorite(viewingID: StopwatchItem.ID, favoriteID: StopwatchItem.ID)
    
    // MARK: - Structural Identity
    
    /// A simplified representation of the mode that ignores associated IDs.
    ///
    /// Used for animations - we only want to animate when the **structure** of the
    /// floating controls changes (e.g., idle → listFavoriteOnly), not when the
    /// content changes within the same structure (e.g., switching which stopwatch is playing).
    ///
    /// Without this, switching between stopwatches would cause jarring animations
    /// because the mode's associated values change, triggering SwiftUI's animation system.
    enum StructuralType: Equatable {
      case idle
      case listPlaybackOnly
      case listFavoriteOnly
      case listFavoritePlusPlayback
      case favoriteDetailOnly
      case favoriteDetailPlusPlayback
      case nonFavoriteDetailOnly
      case nonFavoriteDetailWithFavorite
    }
    
    /// Returns the structural type of this mode, ignoring associated IDs.
    var structuralType: StructuralType {
      switch self {
      case .idle: return .idle
      case .listPlaybackOnly: return .listPlaybackOnly
      case .listFavoriteOnly: return .listFavoriteOnly
      case .listFavoritePlusPlayback: return .listFavoritePlusPlayback
      case .favoriteDetailOnly: return .favoriteDetailOnly
      case .favoriteDetailPlusPlayback: return .favoriteDetailPlusPlayback
      case .nonFavoriteDetailOnly: return .nonFavoriteDetailOnly
      case .nonFavoriteDetailWithFavorite: return .nonFavoriteDetailWithFavorite
      }
    }
  }

  // MARK: - State
  @ObservableState
  struct State: Equatable {
    @Shared(.stopwatches) var stopwatches
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID
    @Shared(.lastPlayedLocalStopwatchID) var lastPlayedLocalStopwatchID
    
    // MARK: - Mode Derivation
    
    /// Derives the current mode from navigation context and shared state.
    ///
    /// The mode determines which UI variant to display. It considers:
    /// 1. What screen is being viewed (via `currentlyViewingStopwatchID`)
    /// 2. Whether a favorite exists
    /// 3. Whether a non-favorite is currently playing
    ///
    /// - Parameter currentlyViewingStopwatchID: The ID of the stopwatch detail being viewed,
    ///   or `nil` if viewing the list.
    /// - Returns: The appropriate mode for the current context.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Viewing list, has favorite, non-fav playing
    /// let mode = state.mode(currentlyViewingStopwatchID: nil)
    /// // Returns: .listFavoritePlusPlayback(favoriteID: ..., playingID: ...)
    ///
    /// // Viewing non-favorite detail, has favorite
    /// let mode = state.mode(currentlyViewingStopwatchID: someNonFavID)
    /// // Returns: .nonFavoriteDetailWithFavorite(viewingID: ..., favoriteID: ...)
    /// ```
    func mode(currentlyViewingStopwatchID: StopwatchItem.ID?) -> Mode {
      // Find running non-favorite (prioritize lastPlayedLocal if still running)
      let playingNonFavoriteID: StopwatchItem.ID? = {
        if let lastPlayedID = lastPlayedLocalStopwatchID,
           lastPlayedID != favoriteStopwatchID,
           let item = stopwatches[id: lastPlayedID],
           item.isRunning {
          return lastPlayedID
        }
        return stopwatches.first {
          $0.isRunning && $0.id != favoriteStopwatchID
        }?.id
      }()
      
      // Determine if we're viewing a detail and what kind
      if let viewingID = currentlyViewingStopwatchID {
        let isViewingFavorite = viewingID == favoriteStopwatchID
        
        if isViewingFavorite {
          // Viewing favorite detail
          if let playingID = playingNonFavoriteID {
            return .favoriteDetailPlusPlayback(favoriteID: viewingID, playingID: playingID)
          } else {
            return .favoriteDetailOnly(favoriteID: viewingID)
          }
        } else {
          // Viewing non-favorite detail
          if let favID = favoriteStopwatchID {
            return .nonFavoriteDetailWithFavorite(viewingID: viewingID, favoriteID: favID)
          } else {
            return .nonFavoriteDetailOnly(viewingID: viewingID)
          }
        }
      }
      
      // Viewing list
      switch (favoriteStopwatchID, playingNonFavoriteID) {
      case (nil, nil):
        return .idle
      case (nil, let playingID?):
        return .listPlaybackOnly(playingID: playingID)
      case (let favID?, nil):
        return .listFavoriteOnly(favoriteID: favID)
      case (let favID?, let playingID?):
        return .listFavoritePlusPlayback(favoriteID: favID, playingID: playingID)
      }
    }
  }

  // MARK: - Action
  enum Action {
    // MARK: Idle Mode
    /// User tapped FAB to create a new stopwatch (becomes favorite).
    case createNewStopwatchTapped

    // MARK: Favorite Controls
    /// Toggle play/pause on the favorite stopwatch.
    case toggleFavoritePlayback
    /// Remove favorite status from current favorite.
    case unfavoriteTapped
    /// Delete the favorite stopwatch.
    case deleteFavoriteTapped
    /// Navigate to the favorite's detail screen.
    case navigateToFavoriteDetailTapped

    // MARK: Non-Favorite / Contextual Controls
    /// Toggle play/pause on a non-favorite (contextual to current screen).
    case toggleContextualPlayback(StopwatchItem.ID)
    /// Create a new favorite and navigate to it.
    case createNewFavoriteTapped
    /// Navigate to a specific stopwatch's detail.
    case navigateToStopwatchTapped(StopwatchItem.ID)

    // MARK: Delegate
    /// Actions delegated to parent for navigation and cross-cutting concerns.
    case delegate(Delegate)

    @CasePathable
    enum Delegate {
      /// Request navigation to a stopwatch's detail screen.
      case navigateToStopwatch(StopwatchItem.ID)
      /// Request creation of a new favorite and navigation to it.
      case createAndNavigateToNewFavorite
      /// Notify parent that a non-favorite was started (for single-playback constraint).
      case nonFavoriteStarted(StopwatchItem.ID)
      /// Request deletion of a stopwatch.
      case deleteRequested(StopwatchItem.ID)
    }
  }

  // MARK: - Dependencies
  @Dependency(\.date.now) var now

  // MARK: - Body
  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      // MARK: Idle Mode
      case .createNewStopwatchTapped:
        return .send(.delegate(.createAndNavigateToNewFavorite))

      // MARK: Favorite Controls
      case .toggleFavoritePlayback:
        guard let favoriteID = state.favoriteStopwatchID else { return .none }
        state.$stopwatches.withLock { items in
          items[id: favoriteID]?.toggle(now: now)
        }
        return .none

      case .unfavoriteTapped:
        state.$favoriteStopwatchID.withLock { $0 = nil }
        return .none

      case .deleteFavoriteTapped:
        guard let favoriteID = state.favoriteStopwatchID else { return .none }
        return .send(.delegate(.deleteRequested(favoriteID)))

      case .navigateToFavoriteDetailTapped:
        guard let favoriteID = state.favoriteStopwatchID else { return .none }
        return .send(.delegate(.navigateToStopwatch(favoriteID)))

      // MARK: Non-Favorite / Contextual Controls
      case let .toggleContextualPlayback(id):
        let wasRunning = state.stopwatches[id: id]?.isRunning ?? false
        state.$stopwatches.withLock { items in
          items[id: id]?.toggle(now: now)
        }
        // If starting a non-favorite, notify parent for single-playback constraint
        if !wasRunning && id != state.favoriteStopwatchID {
          return .send(.delegate(.nonFavoriteStarted(id)))
        }
        return .none

      case .createNewFavoriteTapped:
        return .send(.delegate(.createAndNavigateToNewFavorite))

      case let .navigateToStopwatchTapped(id):
        return .send(.delegate(.navigateToStopwatch(id)))

      // MARK: Delegate (handled by parent)
      case .delegate:
        return .none
      }
    }
  }
}

// MARK: - FloatingStopwatchControlsView
/// The view that renders the floating controls based on the current mode.
///
/// This view receives navigation context from the parent and derives the appropriate
/// mode to display. It adapts its UI based on what screen is being viewed.
///
/// ## Morphing Animations
///
/// The floating controls use SwiftUI's `matchedGeometryEffect` to create smooth morphing
/// transitions between modes. When transitioning from idle (compact record button) to
/// recording (expanded control bar), the following elements animate:
///
/// - **Container**: The outer glow circle morphs into the control bar background
/// - **Primary button**: The red record button morphs into the green play/pause button
/// - **Icon**: The inner record circle morphs into the pause icon
///
/// This creates a "bloom" effect where the small button expands into the full control bar.
///
/// ## Parameters
///
/// - `store`: The store for FloatingStopwatchControls
/// - `destination`: The current navigation destination (from AppFeature)
/// - `currentlyViewingStopwatchID`: The ID of the stopwatch being viewed, or nil if on list
///
/// ## Example
///
/// ```swift
/// FloatingStopwatchControlsView(
///   store: store.scope(state: \.floatingControls, action: \.floatingControls),
///   destination: store.destination,
///   currentlyViewingStopwatchID: store.currentlyViewingStopwatchID
/// )
/// ```

struct FloatingStopwatchControlsView: View {
  let store: StoreOf<FloatingStopwatchControls>
  let destination: AppFeature.Destination.State?
  let currentlyViewingStopwatchID: StopwatchItem.ID?
  
  /// Namespace for coordinating matched geometry animations between mode transitions.
  ///
  /// Elements that share the same identifier within this namespace will animate smoothly
  /// between their positions and sizes when the mode changes.
  @Namespace private var controlsAnimation

  var body: some View {
    let mode = store.state.mode(currentlyViewingStopwatchID: currentlyViewingStopwatchID)
    
    WithPerceptionTracking {
      Group {
        switch mode {
        // MARK: List Modes
        case .idle:
          IdleModeView(store: store, animation: controlsAnimation)

        case .listPlaybackOnly(let playingID):
          if let stopwatch = Shared(store.$stopwatches[id: playingID]) {
            ListPlaybackOnlyView(store: store, stopwatch: stopwatch)
          }

        case .listFavoriteOnly(let favoriteID):
          if let stopwatch = Shared(store.$stopwatches[id: favoriteID]) {
            ListFavoriteOnlyView(
              store: store,
              stopwatch: stopwatch,
              animation: controlsAnimation
            )
          }

        case .listFavoritePlusPlayback(let favoriteID, let playingID):
          if let playingStopwatch = Shared(store.$stopwatches[id: playingID]),
             let favoriteStopwatch = Shared(store.$stopwatches[id: favoriteID]) {
            ListFavoritePlusPlaybackView(
              store: store,
              favoriteStopwatch: favoriteStopwatch,
              playingStopwatch: playingStopwatch
            )
          }

        // MARK: Favorite Detail Modes
        case .favoriteDetailOnly(let favoriteID):
          if let stopwatch = Shared(store.$stopwatches[id: favoriteID]) {
            FavoriteDetailOnlyView(store: store, stopwatch: stopwatch)
          }

        case .favoriteDetailPlusPlayback(let favoriteID, let playingID):
          if let favoriteStopwatch = Shared(store.$stopwatches[id: favoriteID]),
             let playingStopwatch = Shared(store.$stopwatches[id: playingID]) {
            FavoriteDetailPlusPlaybackView(
              store: store,
              favoriteStopwatch: favoriteStopwatch,
              playingStopwatch: playingStopwatch
            )
          }

        // MARK: Non-Favorite Detail Modes
        case .nonFavoriteDetailOnly(let viewingID):
          if let stopwatch = Shared(store.$stopwatches[id: viewingID]) {
            NonFavoriteDetailOnlyView(store: store, stopwatch: stopwatch)
          }

        case .nonFavoriteDetailWithFavorite(let viewingID, let favoriteID):
          if let viewingStopwatch = Shared(store.$stopwatches[id: viewingID]),
             let favoriteStopwatch = Shared(store.$stopwatches[id: favoriteID]) {
            NonFavoriteDetailWithFavoriteView(
              store: store,
              viewingStopwatch: viewingStopwatch,
              favoriteStopwatch: favoriteStopwatch
            )
          }
        }
      }
      // Only animate on structural mode changes (e.g., idle → listFavoriteOnly),
      // not on content changes within the same mode (e.g., switching which stopwatch is playing).
      .animation(.spring(response: 0.5, dampingFraction: 0.8), value: mode.structuralType)
    }
  }
}

// MARK: - Animation Namespace Keys
/// Keys used to coordinate `matchedGeometryEffect` animations between floating control modes.
///
/// When transitioning between modes (e.g., idle → recording), elements with matching keys
/// will animate smoothly between their positions and sizes. This creates the "morphing"
/// effect where the compact record button blooms into the expanded control bar.
///
/// ## Usage
///
/// ```swift
/// // In idle mode - the container is a small circle
/// Circle()
///   .matchedGeometryEffect(id: AnimationKey.container, in: animation)
///
/// // In recording mode - the container is a rounded rectangle
/// RoundedRectangle(cornerRadius: 16)
///   .matchedGeometryEffect(id: AnimationKey.container, in: animation)
/// ```
private enum AnimationKey {
  /// The outer container shape (circle in idle, rounded rect in expanded).
  case container
  /// The primary action button (record button in idle, play/pause in expanded).
  case primaryButton
  /// The icon within the primary button (record dot in idle, pause icon in expanded).
  case buttonIcon
}

// MARK: - Mode Views

// MARK: Idle Mode (Glowing Record Button)
/// Shows when: No favorite, nothing playing, viewing list.
///
/// Displays a small, glowing red record button centered at the bottom of the screen.
/// When tapped, creates a new stopwatch and transitions to the recording state with
/// a morphing animation.
///
/// ## Animation Behavior
///
/// The idle mode participates in matched geometry animations with the recording mode:
/// - The outer glow circle morphs into the control bar background
/// - The red record button morphs into the green play/pause button
/// - The white record dot morphs into the pause icon
///
/// This creates a smooth "bloom" effect where the compact button expands into the full
/// control bar.
private struct IdleModeView: View {
  let store: StoreOf<FloatingStopwatchControls>
  
  /// The animation namespace shared with other modes for coordinating transitions.
  var animation: Namespace.ID

  var body: some View {
    VStack {
      Spacer()
      
      Button {
        store.send(.createNewStopwatchTapped)
      } label: {
        ZStack {
          // Outer glow - morphs into control bar background
          Circle()
            .fill(Color.red.opacity(0.15))
            .frame(width: 72, height: 72)
            .matchedGeometryEffect(id: AnimationKey.container, in: animation)
          
          // Middle glow layer
          Circle()
            .fill(Color.red.opacity(0.25))
            .frame(width: 56, height: 56)
          
          // Main button - morphs into play/pause button
          Circle()
            .fill(
              LinearGradient(
                colors: [Color.red, Color.red.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            .frame(width: 44, height: 44)
            .overlay(
              Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
            .shadow(color: .red.opacity(0.6), radius: 12, x: 0, y: 4)
            .matchedGeometryEffect(id: AnimationKey.primaryButton, in: animation)
          
          // Inner record icon - morphs into pause icon
          Circle()
            .fill(Color.white)
            .frame(width: 16, height: 16)
            .matchedGeometryEffect(id: AnimationKey.buttonIcon, in: animation)
        }
      }
      .buttonStyle(.plain)
      .padding(.bottom, 24)
    }
  }
}

// MARK: List: Playback Only
/// Shows when: No favorite, non-fav playing, viewing list.
/// Controls: Play/pause playing, create new favorite.
private struct ListPlaybackOnlyView: View {
  let store: StoreOf<FloatingStopwatchControls>
  @Shared var stopwatch: StopwatchItem

  var body: some View {
    StopwatchControlBar(
      stopwatch: _stopwatch,
      label: "Playing",
      accentColor: .blue,
      onTap: { store.send(.navigateToStopwatchTapped(stopwatch.id)) },
      primaryButton: {
        PlayPauseButton(
          isRunning: stopwatch.isRunning,
          color: .blue,
          action: { store.send(.toggleContextualPlayback(stopwatch.id)) }
        )
      },
      secondaryButtons: {
        CreateFavoriteButton { store.send(.createNewFavoriteTapped) }
      }
    )
  }
}

// MARK: List: Favorite Only
/// Shows when: Has favorite, no non-fav playing, viewing list.
///
/// Displays the expanded control bar for the favorite (recording) stopwatch. This is the
/// primary destination when transitioning from idle mode after creating a new recording.
///
/// ## Animation Behavior
///
/// When transitioning from idle mode, the following morphing occurs:
/// - The red glow circle expands and transforms into the frosted glass control bar
/// - The red record button morphs into the green play/pause button
/// - The white record dot transforms into the pause icon
/// - Additional controls (unfavorite, delete) fade in from the right
///
/// Controls: Play/pause favorite, unfavorite, delete, nav to detail.
private struct ListFavoriteOnlyView: View {
  let store: StoreOf<FloatingStopwatchControls>
  @Shared var stopwatch: StopwatchItem
  
  /// The animation namespace shared with idle mode for coordinating transitions.
  var animation: Namespace.ID

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.01, paused: !stopwatch.isRunning)) { context in
      let currentMs = stopwatch.currentElapsedMilliseconds(now: context.date)

      let content = HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 4) {
            Text("Recording")
              .font(.caption)
              .foregroundColor(.secondary)
            Text(stopwatch.title.isEmpty ? "Stopwatch" : stopwatch.title)
              .font(.subheadline)
              .fontWeight(.medium)
              .lineLimit(1)
          }

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

        // Play/pause button - morphs from record button
        Button { store.send(.toggleFavoritePlayback) } label: {
          ZStack {
            Circle()
              .fill(stopwatch.isRunning ? Color.orange : Color.green)
              .frame(width: 36, height: 36)
              .matchedGeometryEffect(id: AnimationKey.primaryButton, in: animation)
            
            Image(systemName: stopwatch.isRunning ? "pause.fill" : "play.fill")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.white)
              .matchedGeometryEffect(id: AnimationKey.buttonIcon, in: animation)
          }
        }
        .buttonStyle(.plain)
        
        // Secondary controls - fade in during transition
        UnfavoriteButton { store.send(.unfavoriteTapped) }
          .transition(.opacity.combined(with: .scale(scale: 0.8)))
        DeleteButton { store.send(.deleteFavoriteTapped) }
          .transition(.opacity.combined(with: .scale(scale: 0.8)))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(.ultraThinMaterial)
          .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
          .matchedGeometryEffect(id: AnimationKey.container, in: animation)
      )
      .padding(.horizontal, 16)
      .padding(.bottom, 8)

      Button { store.send(.navigateToFavoriteDetailTapped) } label: { content }
        .buttonStyle(.plain)
    }
  }
}

// MARK: List: Favorite + Playback
/// Shows when: Has favorite AND non-fav playing, viewing list.
/// Controls: Play/pause non-fav, jump to favorite.
private struct ListFavoritePlusPlaybackView: View {
  let store: StoreOf<FloatingStopwatchControls>
  @Shared var favoriteStopwatch: StopwatchItem
  @Shared var playingStopwatch: StopwatchItem

  var body: some View {
    StopwatchControlBar(
      stopwatch: _playingStopwatch,
      label: "Playing",
      accentColor: .blue,
      onTap: { store.send(.navigateToStopwatchTapped(playingStopwatch.id)) },
      primaryButton: {
        PlayPauseButton(
          isRunning: playingStopwatch.isRunning,
          color: .blue,
          action: { store.send(.toggleContextualPlayback(playingStopwatch.id)) }
        )
      },
      secondaryButtons: {
        JumpToFavoriteButton(
          favoriteIsRunning: favoriteStopwatch.isRunning,
          action: { store.send(.navigateToFavoriteDetailTapped) }
        )
      }
    )
  }
}

// MARK: Favorite Detail: Only
/// Shows when: Viewing favorite detail, no non-fav playing.
/// Controls: Play/pause favorite, unfavorite, delete. NO jump button.
private struct FavoriteDetailOnlyView: View {
  let store: StoreOf<FloatingStopwatchControls>
  @Shared var stopwatch: StopwatchItem

  var body: some View {
    StopwatchControlBar(
      stopwatch: _stopwatch,
      label: "Recording",
      accentColor: .green,
      onTap: nil,  // Already on detail
      primaryButton: {
        PlayPauseButton(
          isRunning: stopwatch.isRunning,
          color: .green,
          action: { store.send(.toggleFavoritePlayback) }
        )
      },
      secondaryButtons: {
        UnfavoriteButton { store.send(.unfavoriteTapped) }
        DeleteButton { store.send(.deleteFavoriteTapped) }
      }
    )
  }
}

// MARK: Favorite Detail: + Playback
/// Shows when: Viewing favorite detail, non-fav playing.
/// Controls: Play/pause favorite, unfavorite, delete, jump to playing.
private struct FavoriteDetailPlusPlaybackView: View {
  let store: StoreOf<FloatingStopwatchControls>
  @Shared var favoriteStopwatch: StopwatchItem
  @Shared var playingStopwatch: StopwatchItem

  var body: some View {
    StopwatchControlBar(
      stopwatch: _favoriteStopwatch,
      label: "Recording",
      accentColor: .green,
      onTap: nil,  // Already on detail
      primaryButton: {
        PlayPauseButton(
          isRunning: favoriteStopwatch.isRunning,
          color: .green,
          action: { store.send(.toggleFavoritePlayback) }
        )
      },
      secondaryButtons: {
        UnfavoriteButton { store.send(.unfavoriteTapped) }
        DeleteButton { store.send(.deleteFavoriteTapped) }
        JumpToPlayingButton(
          playingTitle: playingStopwatch.title,
          action: { store.send(.navigateToStopwatchTapped(playingStopwatch.id)) }
        )
      }
    )
  }
}

// MARK: Non-Favorite Detail: Only
/// Shows when: Viewing non-fav detail, no favorite exists.
/// Controls: Play/pause THIS stopwatch, create new favorite.
private struct NonFavoriteDetailOnlyView: View {
  let store: StoreOf<FloatingStopwatchControls>
  @Shared var stopwatch: StopwatchItem

  var body: some View {
    StopwatchControlBar(
      stopwatch: _stopwatch,
      label: nil,
      accentColor: .blue,
      onTap: nil,  // Already on detail
      primaryButton: {
        PlayPauseButton(
          isRunning: stopwatch.isRunning,
          color: .blue,
          action: { store.send(.toggleContextualPlayback(stopwatch.id)) }
        )
      },
      secondaryButtons: {
        CreateFavoriteButton { store.send(.createNewFavoriteTapped) }
      }
    )
  }
}

// MARK: Non-Favorite Detail: With Favorite
/// Shows when: Viewing non-fav detail, favorite exists.
/// Controls: Play/pause THIS stopwatch, jump to favorite.
private struct NonFavoriteDetailWithFavoriteView: View {
  let store: StoreOf<FloatingStopwatchControls>
  @Shared var viewingStopwatch: StopwatchItem
  @Shared var favoriteStopwatch: StopwatchItem

  var body: some View {
    StopwatchControlBar(
      stopwatch: _viewingStopwatch,
      label: nil,
      accentColor: .blue,
      onTap: nil,  // Already on detail
      primaryButton: {
        PlayPauseButton(
          isRunning: viewingStopwatch.isRunning,
          color: .blue,
          action: { store.send(.toggleContextualPlayback(viewingStopwatch.id)) }
        )
      },
      secondaryButtons: {
        JumpToFavoriteButton(
          favoriteIsRunning: favoriteStopwatch.isRunning,
          action: { store.send(.navigateToFavoriteDetailTapped) }
        )
      }
    )
  }
}

// MARK: - Reusable Components

/// A generic control bar for stopwatch controls.
///
/// This component displays a stopwatch with its elapsed time, title, and configurable buttons.
/// It uses `TimelineView` for smooth animation when the stopwatch is running.
///
/// - Parameter stopwatch: A `Shared` binding to the stopwatch item for live state updates
/// - Parameter label: Optional label displayed above the title (e.g., "Recording", "Playing")
/// - Parameter accentColor: Color for the running indicator dot
/// - Parameter onTap: Optional tap action for the entire bar (used for navigation)
/// - Parameter primaryButton: The main action button (typically play/pause)
/// - Parameter secondaryButtons: Additional buttons (unfavorite, delete, jump, etc.)
private struct StopwatchControlBar<PrimaryButton: View, SecondaryButtons: View>: View {
  @Shared var stopwatch: StopwatchItem
  let label: String?
  let accentColor: Color
  let onTap: (() -> Void)?
  @ViewBuilder let primaryButton: () -> PrimaryButton
  @ViewBuilder let secondaryButtons: () -> SecondaryButtons

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.01, paused: !stopwatch.isRunning)) { context in
      let currentMs = stopwatch.currentElapsedMilliseconds(now: context.date)

      let content = HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 4) {
            if let label {
              Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Text(stopwatch.title.isEmpty ? "Stopwatch" : stopwatch.title)
              .font(.subheadline)
              .fontWeight(.medium)
              .lineLimit(1)
          }

          HStack(spacing: 4) {
            StopwatchWidgetDisplay(milliseconds: currentMs)
            if stopwatch.isRunning {
              Circle()
                .fill(accentColor)
                .frame(width: 6, height: 6)
            }
          }
        }

        Spacer()

        primaryButton()
        secondaryButtons()
      }
      .floatingWidgetStyle()

      if let onTap {
        Button(action: onTap) { content }
          .buttonStyle(.plain)
      } else {
        content
      }
    }
  }
}

/// Play/pause button with configurable color.
private struct PlayPauseButton: View {
  let isRunning: Bool
  let color: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: isRunning ? "pause.fill" : "play.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.white)
        .frame(width: 36, height: 36)
        .background(isRunning ? Color.orange : color)
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
  }
}

/// Button to unfavorite the current favorite.
private struct UnfavoriteButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "star.slash.fill")
        .font(.system(size: 16))
        .foregroundColor(.yellow)
        .frame(width: 36, height: 36)
        .background(Color(.systemGray5))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
  }
}

/// Button to delete a stopwatch.
private struct DeleteButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "trash.fill")
        .font(.system(size: 16))
        .foregroundColor(.red)
        .frame(width: 36, height: 36)
        .background(Color(.systemGray5))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
  }
}

/// Button to create a new favorite stopwatch.
private struct CreateFavoriteButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus.circle.fill")
        .font(.system(size: 16))
        .foregroundColor(.green)
        .frame(width: 36, height: 36)
        .background(Color(.systemGray5))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
  }
}

/// Button to jump to the favorite stopwatch.
private struct JumpToFavoriteButton: View {
  let favoriteIsRunning: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        if favoriteIsRunning {
          Circle()
            .fill(Color.green)
            .frame(width: 6, height: 6)
        }
        Image(systemName: "waveform")
          .font(.system(size: 14))
      }
      .foregroundColor(.green)
      .frame(width: 36, height: 36)
      .background(Color(.systemGray5))
      .clipShape(Circle())
    }
    .buttonStyle(.plain)
  }
}

/// Button to jump to a playing non-favorite stopwatch.
private struct JumpToPlayingButton: View {
  let playingTitle: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "speaker.wave.2.fill")
        .font(.system(size: 14))
        .foregroundColor(.blue)
        .frame(width: 36, height: 36)
        .background(Color(.systemGray5))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Floating Widget Style

extension View {
  func floatingWidgetStyle() -> some View {
    self
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(.ultraThinMaterial)
          .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
      )
      .padding(.horizontal, 16)
      .padding(.bottom, 8)
  }
}

// MARK: - Previews

#Preview("Idle Mode") {
  FloatingStopwatchControlsView(
    store: Store(initialState: FloatingStopwatchControls.State()) {
      FloatingStopwatchControls()
    },
    destination: nil,
    currentlyViewingStopwatchID: nil
  )
  .frame(maxHeight: .infinity, alignment: .bottom)
  .background(Color(.systemBackground))
}

#Preview("List: Favorite Only") {
  @Shared(.stopwatches) var stopwatches = [
    StopwatchItem(id: StopwatchItem.ID(UUID()), title: "Meeting Notes", isRunning: true, lastStartTime: Date())
  ]
  @Shared(.favoriteStopwatchID) var favoriteID = stopwatches.first?.id

  return FloatingStopwatchControlsView(
    store: Store(initialState: FloatingStopwatchControls.State()) {
      FloatingStopwatchControls()
    },
    destination: nil,
    currentlyViewingStopwatchID: nil
  )
  .frame(maxHeight: .infinity, alignment: .bottom)
  .background(Color(.systemBackground))
}

#Preview("Non-Favorite Detail: With Favorite") {
  let favID = StopwatchItem.ID(UUID())
  let nonFavID = StopwatchItem.ID(UUID())
  
  @Shared(.stopwatches) var stopwatches = [
    StopwatchItem(id: favID, title: "Recording", isRunning: true, lastStartTime: Date()),
    StopwatchItem(id: nonFavID, title: "Playback", elapsedMilliseconds: 30000)
  ]
  @Shared(.favoriteStopwatchID) var favoriteStopwatchID = favID

  return FloatingStopwatchControlsView(
    store: Store(initialState: FloatingStopwatchControls.State()) {
      FloatingStopwatchControls()
    },
    destination: nil,
    currentlyViewingStopwatchID: nonFavID
  )
  .frame(maxHeight: .infinity, alignment: .bottom)
  .background(Color(.systemBackground))
}

// MARK: - Animation Test Preview
/// Interactive preview for testing the idle → recording morphing animation.
///
/// This preview provides a toggle button to switch between idle and recording states,
/// allowing you to observe the morphing animation without running the full application.
///
/// ## How to Use
///
/// 1. Open this preview in Xcode's canvas
/// 2. Tap the "Toggle State" button to switch between idle and recording modes
/// 3. Observe the morphing animation:
///    - The red glow circle expands into the frosted glass control bar
///    - The red record button morphs into the green play/pause button
///    - Secondary controls fade in from the right
///
/// ## What to Look For
///
/// - **Smooth interpolation**: The container shape should smoothly transition from circle to rounded rect
/// - **Coordinated timing**: All elements should animate together with the spring animation
/// - **Glow dissipation**: The red glow should fade as the control bar appears
#Preview("Animation Test: Idle ↔ Recording") {
  AnimationTestView()
}

/// A test harness view for previewing the idle → recording animation.
///
/// This view manages its own state to toggle between modes, independent of the
/// actual feature logic. This allows testing the animation in isolation.
private struct AnimationTestView: View {
  @State private var isRecording = false
  
  /// Stable ID for the test stopwatch, created once and reused.
  private let testStopwatchID = StopwatchItem.ID(UUID())
  
  var body: some View {
    // Configure shared state based on toggle
    let _ = configureSharedState()
    
    ZStack {
      Color(.systemBackground)
        .ignoresSafeArea()
      
      VStack {
        Spacer()
        
        // Status indicator
        VStack(spacing: 8) {
          Text(isRecording ? "Recording Mode" : "Idle Mode")
            .font(.headline)
          Text("Tap button below to toggle")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        
        Spacer()
        
        // The floating controls being tested
        FloatingStopwatchControlsView(
          store: Store(initialState: FloatingStopwatchControls.State()) {
            FloatingStopwatchControls()
          },
          destination: nil,
          currentlyViewingStopwatchID: nil
        )
        
        // Toggle button
        Button {
          withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isRecording.toggle()
          }
        } label: {
          Text("Toggle State")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.blue)
            .clipShape(Capsule())
        }
        .padding(.bottom, 32)
      }
    }
  }
  
  /// Configures the shared state based on the current toggle value.
  ///
  /// This is called during view body evaluation to keep shared state in sync
  /// with the local toggle state.
  private func configureSharedState() {
    @Shared(.stopwatches) var stopwatches
    @Shared(.favoriteStopwatchID) var favoriteStopwatchID
    
    if isRecording {
      // Recording mode: ensure we have a favorite stopwatch
      if stopwatches.isEmpty || stopwatches[id: testStopwatchID] == nil {
        $stopwatches.withLock { items in
          items = [
            StopwatchItem(
              id: testStopwatchID,
              title: "Test Recording",
              isRunning: true,
              lastStartTime: Date()
            )
          ]
        }
      }
      if favoriteStopwatchID != testStopwatchID {
        $favoriteStopwatchID.withLock { $0 = testStopwatchID }
      }
    } else {
      // Idle mode: clear favorite and stopwatches
      if favoriteStopwatchID != nil {
        $favoriteStopwatchID.withLock { $0 = nil }
      }
      if !stopwatches.isEmpty {
        $stopwatches.withLock { $0 = [] }
      }
    }
  }
}

