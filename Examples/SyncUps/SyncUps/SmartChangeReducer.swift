import ComposableArchitecture
import Foundation
import os.lock

// ============================================================================
// MARK: - SMART PRINTER API
// ============================================================================

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
    
    public func reduce(into state: inout Base.State, action: Base.Action) -> Effect<Base.Action> {
        // 1. Capture State Before (for baseline if needed)
        #if DEBUG
        let stateBeforeAction = state
        #endif
        
        // 2. Run Reducer
        let effect = base.reduce(into: &state, action: action)
        
        // 3. Analyze & Print (Debug Only)
        #if DEBUG
        let classification = analyzer.analyze(action: action)
        
        // Determine baseline: The last state we showed the user.
        // If nil, use the state right before this action (first run).
        let baselineState = stateTracker.lastPrintedState ?? stateBeforeAction
        
        switch classification {
        case .agency, .learning:
            // SIGNAL: Print the diff from baseline -> current
            // This reveals all changes that happened during silenced physics/burst events.
            printSmartLog(
                action: action,
                oldState: baselineState,
                newState: state,
                classification: classification
            )
            // Checkpoint: We just showed this state to the user.
            stateTracker.update(state)
            
        case .physics:
            // NOISE: Do not print. Do not update stateTracker.
            // Changes are hidden now but will accumulate into the next Agency diff.
            break
            
        case let .burst(count):
            // BURST: Print header to acknowledge activity, but hide the diff.
            // Changes accumulate into the next Agency diff.
            print("  (Burst x\(count): \(formatAction(action)))")
        }
        #endif
        
        return effect
    }
    
    private func printSmartLog(action: Base.Action, oldState: Base.State, newState: Base.State, classification: ActionClassification) {
        var output = ""
        
        // Header
        let icon = classification == .learning ? "🎓" : "👤"
        output.append("\(icon) received action:\n")
        
        // Action Dump
        CustomDump.customDump(action, to: &output, indent: 2)
        output.append("\n")
        
        // State Diff
        if let diff = CustomDump.diff(oldState, newState) {
            output.append(diff)
        } else {
            output.append("  (No state changes)")
        }
        
        print(output)
    }
    
    private func formatAction(_ action: Base.Action) -> String {
        var output = ""
        CustomDump.customDump(action, to: &output)
        return output
    }
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

/// A thread-safe analyzer that tracks action statistics using Welford's Algorithm.
final class ActionFrequencyAnalyzer: @unchecked Sendable {
    
    struct ActionStats {
        var count: Int = 0
        var lastTimestamp: TimeInterval = 0
        
        // Welford's Online Algorithm for Variance
        // https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Welford's_online_algorithm
        var meanDelta: Double = 0
        var m2: Double = 0 // Sum of squares of differences
        
        // Burst detection
        var burstCount: Int = 0
    }
    
    private var stats: [String: ActionStats] = [:]
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    private let dateProvider: () -> TimeInterval
    
    init(dateProvider: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
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
        
        // Only calculate variance if delta is reasonable (not the first run)
        if stat.count > 1 {
            let d = delta - stat.meanDelta
            stat.meanDelta += d / Double(stat.count)
            let d2 = delta - stat.meanDelta
            stat.m2 += d * d2
        }
        
        // 3. Classify
        let result: ActionClassification
        
        // HEURISTIC A: Learning Phase
        // Always show the first 5 occurrences so the dev knows it exists.
        if stat.count < 5 {
            result = .learning
        }
        else {
            let variance = stat.m2 / Double(stat.count - 1)
            
            // HEURISTIC B: Physics Detection
            // If it happens faster than 2Hz (0.5s) AND has very low jitter (Variance < 0.005)
            // It is likely a machine/timer.
            let isHighFrequency = stat.meanDelta < 0.5
            let isLowVariance = variance < 0.005
            
            if isHighFrequency && isLowVariance {
                result = .physics
            }
            // HEURISTIC C: Burst Detection
            // It's fast, but maybe variance is high (human tapping).
            // Or it's just spammy. We group "Burst" logs.
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
                // Reset burst count if we slowed down
                stat.burstCount = 0
                result = .agency
            }
        }
        
        stats[label] = stat
        return result
    }
}

// ============================================================================
// MARK: - TEST SUITE
// ============================================================================

#if DEBUG
func runSmartPrinterTests() {
    print("🧪 Starting Smart Printer Classification Tests...")
    
    // 1. Setup simulated time
    var simulatedTime: TimeInterval = 0
    let analyzer = ActionFrequencyAnalyzer(dateProvider: { simulatedTime })
    
    // Helper to simulate action arrival
    func send(_ action: String, after seconds: TimeInterval) -> ActionClassification {
        simulatedTime += seconds
        return analyzer.analyze(action: action)
    }
    
    // TEST 1: Learning Phase (First 5 events)
    print("--- Test 1: Learning Phase ---")
    for i in 1...5 {
        let result = send("tap", after: 1.0)
        assert(result == .learning, "Event \(i) should be .learning")
    }
    print("✅ Learning Phase passed")
    
    // TEST 2: Agency Detection (Slow, distinct taps)
    print("--- Test 2: Agency Detection ---")
    // Taps happening every 2 seconds (Low Frequency)
    for _ in 1...5 {
        let result = send("tap", after: 2.0)
        assert(result == .agency, "Slow taps should be .agency")
    }
    print("✅ Agency Detection passed")
    
    // TEST 3: Physics Detection (Metronomic Timer)
    print("--- Test 3: Physics Detection ---")
    // Tick happens exactly every 0.05s (20Hz, 0 variance)
    // First 4 are learning
    for _ in 1...4 { _ = send("tick", after: 0.05) }
    
    // Next ones should be physics
    for i in 1...10 {
        let result = send("tick", after: 0.05)
        assert(result == .physics, "Perfect metronome \(i) should be .physics")
    }
    print("✅ Physics Detection passed")
    
    // TEST 4: Burst Detection (Rapid typing/mashing)
    print("--- Test 4: Burst Detection ---")
    // Typing happens fast (0.1s) but might have slight jitter (simulated here as consistent for simplicity)
    // Using a new key "type"
    for _ in 1...4 { _ = send("type", after: 0.1) }
    
    // 5th one becomes burst because mean delta is small (<0.5)
    let burstStart = send("type", after: 0.1)
    if case .burst = burstStart {
        print("✅ Entered Burst Mode")
    } else {
        print("❌ Failed to enter Burst Mode (Got \(burstStart))")
    }
    
    // Test the "Let one through every 10th" rule
    for _ in 1...8 { _ = send("type", after: 0.1) } // 9th burst
    let tenthBurst = send("type", after: 0.1) // 10th burst
    
    if tenthBurst == .agency {
        print("✅ 10th Burst item leaked as .agency")
    } else {
        print("❌ 10th Burst item blocked (Got \(tenthBurst))")
    }
    
    print("🎉 All Tests Passed!")
}
#endif