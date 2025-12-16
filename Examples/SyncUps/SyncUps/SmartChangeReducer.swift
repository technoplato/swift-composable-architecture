//
//  SmartChangeReducer.swift
//  SyncUps
//
//  Created by Michael Lustig on 12/15/25.
//


import Combine
import ComposableArchitecture
import Foundation
import os
import os.lock
@_spi(SharedChangeTracking) import Sharing

// ============================================================================
// MARK: - SMART PRINTER API
// ============================================================================

/// OSLog logger for SmartChangeReducer - use subsystem filter in Console.app or terminal
private let smartLogger = Logger(subsystem: "com.syncups.smartchanges", category: "reducer")

extension Reducer {
    /// Enhances a reducer with "Smart" debug logging.
    ///
    /// Unlike the standard `_printChanges()`, this modifier analyzes the **frequency and regularity**
    /// of your actions in real-time.
    ///
    /// - **Physics Detection**: Automatically mutes high-frequency, low-variance events (e.g., Timer Ticks).
    /// - **Agency Detection**: Highlights user interactions and distinct state changes.
    /// - **Accumulated Diffs**: State changes from muted events (Physics/Bursts) are accumulated and
    ///   printed in the diff of the next Agency event.
    ///
    /// **Viewing Logs:**
    /// ```bash
    /// # Stream logs in terminal:
    /// log stream --predicate 'subsystem == "com.syncups.smartchanges"' --style compact
    ///
    /// # Or with pretty formatting:
    /// log stream --predicate 'subsystem == "com.syncups.smartchanges"' --style json
    /// ```
    ///
    /// ```swift
    /// Reduce { state, action in
    ///    // ...
    /// }
    /// ._printSmartChanges()
    /// ```
    public func _printSmartChanges() -> SmartChangeReducer<Self> {
        SmartChangeReducer(base: self)
    }
}

/// Queue for serializing print output
private let smartPrintQueue = DispatchQueue(label: "smart-change-reducer.printer")

/// Monotonically increasing action counter for log correlation
private let actionCounter = ActionCounter()

private final class ActionCounter: @unchecked Sendable {
    private var count: Int = 0
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    
    init() { lock.initialize(to: os_unfair_lock()) }
    deinit { lock.deinitialize(count: 1); lock.deallocate() }
    
    func next() -> Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        count += 1
        return count
    }
}

// ============================================================================
// MARK: - IMPLEMENTATION
// ============================================================================

public struct SmartChangeReducer<Base: Reducer>: Reducer {
    @usableFromInline let base: Base
    private let analyzer = ActionFrequencyAnalyzer()
    private let stateTracker = StateTracker<Base.State>()
    
    @usableFromInline
    init(base: Base) {
        self.base = base
    }
    
    #if DEBUG
    public func reduce(into state: inout Base.State, action: Base.Action) -> Effect<Base.Action> {
        // Use SharedChangeTracker to detect @Shared state mutations
        let changeTracker = SharedChangeTracker(reportUnassertedChanges: false)
        
        return changeTracker.track {
            // 1. Capture State Before
            let stateBeforeAction = UncheckedSendable(state)
            
            // 2. Run Reducer
            let effect = base.reduce(into: &state, action: action)
            
            // 3. Analyze & Print via deferred effect (like TCA's _printChanges)
            let classification = analyzer.analyze(action: action)
            let baselineState = UncheckedSendable(stateTracker.lastPrintedState ?? stateBeforeAction.wrappedValue)
            let newState = UncheckedSendable(state)
            let actionCopy = UncheckedSendable(action)
            let actionNumber = actionCounter.next()
            
            // Capture stateTracker reference for update
            let tracker = stateTracker
            
            return withEscapedDependencies { continuation in
                effect.merge(
                    with: .publisher {
                        Deferred<Empty<Base.Action, Never>> {
                            smartPrintQueue.async {
                                continuation.yield {
                                    // Use changeTracker.assert to include @Shared changes in diff
                                    changeTracker.assert {
                                        switch classification {
                                        case .agency, .learning:
                                            let output = formatBoxLog(
                                                action: actionCopy.wrappedValue,
                                                oldState: baselineState.wrappedValue,
                                                newState: newState.wrappedValue,
                                                classification: classification,
                                                actionNumber: actionNumber
                                            )
                                            // Log to OSLog only (appears in Xcode console AND can be streamed externally)
                                            smartLogger.info("\(output, privacy: .public)")
                                            
                                            tracker.update(newState.wrappedValue)
                                            
                                        case .physics:
                                            // NOISE: Do not print. Do not update stateTracker.
                                            break
                                            
                                        case let .burst(count):
                                            let burstMsg = "  ⚡ Burst x\(count): \(formatActionCompact(actionCopy.wrappedValue))"
                                            smartLogger.debug("\(burstMsg, privacy: .public)")
                                        }
                                    }
                                }
                            }
                            return Empty()
                        }
                    }
                )
            }
        }
    }
    #else
    @inlinable
    public func reduce(into state: inout Base.State, action: Base.Action) -> Effect<Base.Action> {
        return base.reduce(into: &state, action: action)
    }
    #endif
}

// ============================================================================
// MARK: - BOX STYLE FORMATTER
// ============================================================================

private let boxWidth = 80

private func formatBoxLog<Action, State>(
    action: Action,
    oldState: State,
    newState: State,
    classification: ActionClassification,
    actionNumber: Int
) -> String {
    var output = ""
    
    // Get timestamp
    let timestamp = ISO8601DateFormatter().string(from: Date())
    
    // Classification info
    let (icon, label) = switch classification {
    case .learning: ("🎓", "LEARNING")
    case .agency: ("👤", "AGENCY")
    case .physics: ("⚙️", "PHYSICS")
    case .burst(let n): ("⚡", "BURST x\(n)")
    }
    
    // ╔═══ TOP BORDER ═══╗
    output += "╔" + String(repeating: "═", count: boxWidth - 2) + "╗\n"
    
    // ║ Header Line ║
    let headerText = "\(icon) \(label) #\(actionNumber)"
    let timeText = timestamp.suffix(15) // Just time portion
    let headerPadding = boxWidth - 4 - headerText.count - timeText.count
    output += "║ \(headerText)" + String(repeating: " ", count: max(1, headerPadding)) + "\(timeText) ║\n"
    
    // ╠═══ SEPARATOR ═══╣
    output += "╠" + String(repeating: "═", count: boxWidth - 2) + "╣\n"
    
    // ║ ACTION ║
    output += "║ ACTION" + String(repeating: " ", count: boxWidth - 10) + "║\n"
    output += "║" + String(repeating: "─", count: boxWidth - 2) + "║\n"
    
    // Format action (compact, single line if possible)
    var actionStr = ""
    CustomDump.customDump(action, to: &actionStr, indent: 0)
    let actionLines = actionStr.split(separator: "\n", omittingEmptySubsequences: false)
    for line in actionLines.prefix(10) { // Limit action lines
        output += boxLine(String(line))
    }
    if actionLines.count > 10 {
        output += boxLine("  ... (\(actionLines.count - 10) more lines)")
    }
    
    // ╠═══ SEPARATOR ═══╣
    output += "╠" + String(repeating: "═", count: boxWidth - 2) + "╣\n"
    
    // ║ STATE CHANGES ║
    output += "║ STATE CHANGES" + String(repeating: " ", count: boxWidth - 17) + "║\n"
    output += "║" + String(repeating: "─", count: boxWidth - 2) + "║\n"
    
    // Format diff
    if let diff = CustomDump.diff(oldState, newState) {
        let diffLines = diff.split(separator: "\n", omittingEmptySubsequences: false)
        for line in diffLines.prefix(30) { // Limit diff lines
            output += boxLine(String(line))
        }
        if diffLines.count > 30 {
            output += boxLine("  ... (\(diffLines.count - 30) more lines)")
        }
    } else {
        output += boxLine("  (No state changes)")
    }
    
    // ╚═══ BOTTOM BORDER ═══╝
    output += "╚" + String(repeating: "═", count: boxWidth - 2) + "╝"
    
    return output
}

/// Format a single line within the box, truncating if needed
private func boxLine(_ content: String) -> String {
    let maxContent = boxWidth - 4 // Account for "║ " and " ║"
    let truncated = content.count > maxContent
        ? String(content.prefix(maxContent - 3)) + "..."
        : content
    let padding = maxContent - truncated.count
    return "║ \(truncated)" + String(repeating: " ", count: max(0, padding)) + " ║\n"
}

/// Compact action format for burst messages
private func formatActionCompact<Action>(_ action: Action) -> String {
    var output = ""
    CustomDump.customDump(action, to: &output)
    // Take first line only, truncate if needed
    let firstLine = output.split(separator: "\n").first.map(String.init) ?? output
    return firstLine.count > 60 ? String(firstLine.prefix(57)) + "..." : firstLine
}

// ============================================================================
// MARK: - HELPERS
// ============================================================================

/// Tracks the last state that was printed to the console, enabling diff accumulation.
final class StateTracker<State>: @unchecked Sendable {
    var lastPrintedState: State?
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    
    init() {
        lock.initialize(to: os_unfair_lock())
    }
    
    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }
    
    func update(_ state: State) {
        os_unfair_lock_lock(lock)
        lastPrintedState = state
        os_unfair_lock_unlock(lock)
    }
}

// ============================================================================
// MARK: - THE BRAIN (ANALYZER)
// ============================================================================

enum ActionClassification: Equatable {
    /// Initial phase: We don't have enough data yet, so we log it to be safe.
    case learning
    /// Low frequency or high variance (User actions, Network responses).
    case agency
    /// High frequency AND low variance (Timers, Spinners).
    case physics
    /// High frequency BUT identical action type (Typing, Dragging).
    case burst(count: Int)
}

/// A thread-safe analyzer that tracks action statistics using a sliding window.
///
/// Uses a fixed-size window of recent time deltas to calculate frequency and variance.
/// This allows the analyzer to adapt quickly when action patterns change.
final class ActionFrequencyAnalyzer: @unchecked Sendable {
    
    /// Configuration for the analyzer
    struct Config {
        /// Number of events before classification begins (first N are always "learning")
        var learningThreshold: Int = 3
        /// Size of the sliding window for variance calculation
        var windowSize: Int = 5
        /// Actions faster than this (in seconds) are considered "high frequency"
        var highFrequencyThreshold: TimeInterval = 0.5
        /// Variance below this threshold indicates machine-like regularity
        var lowVarianceThreshold: Double = 0.01
    }
    
    struct ActionStats {
        var count: Int = 0
        var lastTimestamp: TimeInterval = 0
        
        /// Sliding window of recent time deltas
        var recentDeltas: [TimeInterval] = []
        
        /// Burst detection counter
        var burstCount: Int = 0
        
        /// Calculate mean of recent deltas
        var recentMean: TimeInterval {
            guard !recentDeltas.isEmpty else { return 0 }
            return recentDeltas.reduce(0, +) / Double(recentDeltas.count)
        }
        
        /// Calculate variance of recent deltas
        var recentVariance: Double {
            guard recentDeltas.count > 1 else { return 0 }
            let mean = recentMean
            let squaredDiffs = recentDeltas.map { ($0 - mean) * ($0 - mean) }
            return squaredDiffs.reduce(0, +) / Double(recentDeltas.count - 1)
        }
        
        mutating func addDelta(_ delta: TimeInterval, windowSize: Int) {
            recentDeltas.append(delta)
            // Keep only the most recent N deltas
            if recentDeltas.count > windowSize {
                recentDeltas.removeFirst()
            }
        }
    }
    
    private var stats: [String: ActionStats] = [:]
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    private let dateProvider: () -> TimeInterval
    private let config: Config
    
    init(
        config: Config = Config(),
        dateProvider: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.config = config
        self.dateProvider = dateProvider
        lock.initialize(to: os_unfair_lock())
    }
    
    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }
    
    func analyze<Action>(action: Action) -> ActionClassification {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        
        let now = dateProvider()
        
        // 1. Identify Action Type (Naive Grouping)
        // We strip the payload to identify the "Case".
        // e.g. "tick(1)" -> "tick"
        let label = String(describing: action)
            .components(separatedBy: "(")
            .first ?? String(describing: action)
        
        var stat = stats[label] ?? ActionStats(lastTimestamp: now)
        let delta = now - stat.lastTimestamp
        
        // 2. Update Statistics
        stat.count += 1
        stat.lastTimestamp = now
        
        // Add delta to sliding window (skip first event which has no meaningful delta)
        if stat.count > 1 {
            stat.addDelta(delta, windowSize: config.windowSize)
        }
        
        // 3. Classify
        let result: ActionClassification
        
        // HEURISTIC A: Learning Phase
        // Always show the first N occurrences so the dev knows it exists.
        if stat.count <= config.learningThreshold {
            result = .learning
        }
        // Need at least 2 deltas to calculate variance
        else if stat.recentDeltas.count < 2 {
            result = .learning
        }
        else {
            let meanDelta = stat.recentMean
            let variance = stat.recentVariance
            
            // HEURISTIC B: Physics Detection
            // If recent actions happen faster than threshold AND have very low jitter
            // It is likely a machine/timer.
            let isHighFrequency = meanDelta < config.highFrequencyThreshold
            let isLowVariance = variance < config.lowVarianceThreshold
            
            if isHighFrequency && isLowVariance {
                // Reset burst count when entering physics mode
                stat.burstCount = 0
                result = .physics
            }
            // HEURISTIC C: Burst Detection
            // It's fast, but variance is high (human tapping/typing).
            else if isHighFrequency {
                stat.burstCount += 1
                // Log every 10th burst item to keep console alive but not flooded
                if stat.burstCount % 10 == 0 {
                    result = .agency // Let one through occasionally
                } else {
                    result = .burst(count: stat.burstCount)
                }
            }
            else {
                // Reset burst count when slowing down
                stat.burstCount = 0
                result = .agency
            }
        }
        
        stats[label] = stat
        return result
    }
}

// ============================================================================
// MARK: - TEST SUITE (Deprecated - Use SmartChangeReducerTests.swift)
// ============================================================================

// Tests have been moved to SyncUpsTests/SmartChangeReducerTests.swift
// Run with: xcodebuild test -scheme SyncUps -destination 'platform=iOS Simulator,name=iPhone 16'
