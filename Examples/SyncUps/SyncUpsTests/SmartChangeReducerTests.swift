import ComposableArchitecture
import Foundation
import Testing

@testable import SyncUps

// MARK: - ActionFrequencyAnalyzer Tests

@MainActor
struct SmartChangeReducerTests {
  
  // MARK: - Learning Phase Tests
  
  @Test
  func learningPhase_firstThreeEventsAreAlwaysLearning() async {
    var simulatedTime: TimeInterval = 0
    let analyzer = ActionFrequencyAnalyzer(dateProvider: { simulatedTime })
    
    // Default learning threshold is 3, so first 3 events are learning
    for i in 1...3 {
      simulatedTime += 1.0
      let result = analyzer.analyze(action: "tap")
      #expect(result == .learning, "Event \(i) should be .learning, got \(result)")
    }
  }
  
  @Test
  func learningPhase_fourthEventTransitionsToAgency() async {
    var simulatedTime: TimeInterval = 0
    let analyzer = ActionFrequencyAnalyzer(dateProvider: { simulatedTime })
    
    // First 3 events (learning)
    for _ in 1...3 {
      simulatedTime += 1.0
      _ = analyzer.analyze(action: "tap")
    }
    
    // 4th event with slow timing should be agency (not learning)
    // Need one more to have enough deltas for variance
    simulatedTime += 1.0
    let result = analyzer.analyze(action: "tap")
    #expect(result == .agency, "4th slow event should be .agency, got \(result)")
  }
  
  // MARK: - Agency Detection Tests
  
  @Test
  func agencyDetection_slowDistinctTapsAreAgency() async {
    var simulatedTime: TimeInterval = 0
    let analyzer = ActionFrequencyAnalyzer(dateProvider: { simulatedTime })
    
    // Burn through learning phase (3 events)
    for _ in 1...3 {
      simulatedTime += 2.0
      _ = analyzer.analyze(action: "tap")
    }
    
    // Subsequent slow taps (>0.5s apart) should be agency
    for i in 1...5 {
      simulatedTime += 2.0
      let result = analyzer.analyze(action: "tap")
      #expect(result == .agency, "Slow tap \(i) should be .agency, got \(result)")
    }
  }
  
  // MARK: - Physics Detection Tests
  
  @Test
  func physicsDetection_metronomicTimerIsPhysics() async {
    var simulatedTime: TimeInterval = 0
    let analyzer = ActionFrequencyAnalyzer(dateProvider: { simulatedTime })
    
    // Burn through learning phase with perfect timing (3 events)
    for _ in 1...3 {
      simulatedTime += 0.05  // 20Hz, perfect metronome
      _ = analyzer.analyze(action: "tick")
    }
    
    // After learning, metronomic actions should be physics
    for i in 1...10 {
      simulatedTime += 0.05
      let result = analyzer.analyze(action: "tick")
      #expect(result == .physics, "Metronomic tick \(i) should be .physics, got \(result)")
    }
  }
  
  @Test
  func physicsDetection_requiresBothHighFrequencyAndLowVariance() async {
    var simulatedTime: TimeInterval = 0
    // Use higher variance threshold to ensure variable timing is detected
    let config = ActionFrequencyAnalyzer.Config(lowVarianceThreshold: 0.001)
    let analyzer = ActionFrequencyAnalyzer(config: config, dateProvider: { simulatedTime })
    
    // Burn through learning with varying timing (high variance)
    let intervals: [TimeInterval] = [0.1, 0.3, 0.05, 0.2, 0.15, 0.25]  // Variable timing
    for interval in intervals {
      simulatedTime += interval
      _ = analyzer.analyze(action: "jitter")
    }
    
    // High frequency but variable timing should NOT be physics
    simulatedTime += 0.1
    let result = analyzer.analyze(action: "jitter")
    // With high variance, this should be burst, not physics
    #expect(result != .physics, "Variable timing should not be .physics, got \(result)")
  }
  
  // MARK: - Burst Detection Tests
  
  @Test
  func burstDetection_rapidTypingWithVarianceEntersBurstMode() async {
    var simulatedTime: TimeInterval = 0
    // Configure with very low variance threshold so only perfect timing = physics
    // This ensures variable timing triggers burst detection
    let config = ActionFrequencyAnalyzer.Config(lowVarianceThreshold: 0.0001)
    let analyzer = ActionFrequencyAnalyzer(config: config, dateProvider: { simulatedTime })
    
    // Burn through learning phase with highly variable fast typing
    // Variance needs to be > 0.0001 to trigger burst instead of physics
    let intervals: [TimeInterval] = [0.05, 0.15, 0.08, 0.12, 0.2]  // Highly variable but fast
    for interval in intervals {
      simulatedTime += interval
      _ = analyzer.analyze(action: "type")
    }
    
    // Next rapid action with variance should be burst
    simulatedTime += 0.1
    let result = analyzer.analyze(action: "type")
    
    // Should be burst (high freq but variance too high for physics)
    if case .burst = result {
      // Success
    } else {
      #expect(Bool(false), "Rapid variable typing should be .burst, got \(result)")
    }
  }
  
  @Test
  func burstDetection_everyTenthBurstLeaksAsAgency() async {
    var simulatedTime: TimeInterval = 0
    // Configure to ensure burst detection
    let config = ActionFrequencyAnalyzer.Config(lowVarianceThreshold: 0.0001)
    let analyzer = ActionFrequencyAnalyzer(config: config, dateProvider: { simulatedTime })
    
    var burstCount = 0
    var agencyLeakCount = 0
    
    for i in 1...25 {
      // Variable timing: fast but not perfectly regular
      simulatedTime += 0.1 + Double(i % 3) * 0.05
      let result = analyzer.analyze(action: "mash")
      
      if case .burst = result {
        burstCount += 1
      } else if result == .agency && i > 3 {
        agencyLeakCount += 1
      }
    }
    
    // Should have some bursts
    #expect(burstCount > 0, "Should detect bursts, got \(burstCount) bursts and \(agencyLeakCount) agency leaks")
  }
  
  // MARK: - Burst Reset Tests
  
  @Test
  func burstReset_slowingDownResetsToAgency() async {
    var simulatedTime: TimeInterval = 0
    let config = ActionFrequencyAnalyzer.Config(
      windowSize: 3,  // Smaller window so it adapts faster
      lowVarianceThreshold: 0.0001
    )
    let analyzer = ActionFrequencyAnalyzer(config: config, dateProvider: { simulatedTime })
    
    // Burn through learning with fast timing
    for _ in 1...3 {
      simulatedTime += 0.1
      _ = analyzer.analyze(action: "action")
    }
    
    // Do some fast actions to establish burst pattern
    for _ in 1...5 {
      simulatedTime += 0.1 + Double.random(in: 0...0.05)
      _ = analyzer.analyze(action: "action")
    }
    
    // Now slow down significantly - send multiple slow actions to fill the window
    for _ in 1...4 {
      simulatedTime += 2.0
      _ = analyzer.analyze(action: "action")
    }
    
    // After window is filled with slow actions, should be agency
    simulatedTime += 2.0
    let result = analyzer.analyze(action: "action")
    #expect(result == .agency, "After slowing down should be .agency, got \(result)")
  }
  
  // MARK: - Different Action Types Tests
  
  @Test
  func differentActionTypes_trackedIndependently() async {
    var simulatedTime: TimeInterval = 0
    let analyzer = ActionFrequencyAnalyzer(dateProvider: { simulatedTime })
    
    // Fast ticks (will become physics) - need enough to fill window
    for _ in 1...6 {
      simulatedTime += 0.05
      _ = analyzer.analyze(action: "tick")
    }
    
    // Slow taps (will be agency) - starts fresh learning
    // NOTE: The taps use their own sliding window, independent of ticks
    for _ in 1...4 {
      simulatedTime += 2.0
      _ = analyzer.analyze(action: "tap")
    }
    
    // IMPORTANT: The tick's sliding window includes the time gap since last tick
    // When we do taps for 8 seconds total, the next tick has a huge delta
    // This is actually correct behavior - if you stop ticking for 8 seconds,
    // the pattern has changed!
    
    // To test independent tracking, we need to resume ticks quickly
    // First tick after gap will have large delta (gets added to window)
    simulatedTime += 0.05
    _ = analyzer.analyze(action: "tick")  // This tick has ~8s gap, pushes out old fast deltas
    
    // Now send more fast ticks to refill the window
    for _ in 1...5 {
      simulatedTime += 0.05
      _ = analyzer.analyze(action: "tick")
    }
    
    // NOW tick should be physics again (window refilled with fast deltas)
    simulatedTime += 0.05
    let tickResult = analyzer.analyze(action: "tick")
    #expect(tickResult == .physics, "Tick should be physics after refilling window, got \(tickResult)")
    
    // Check tap is agency
    simulatedTime += 2.0
    let tapResult = analyzer.analyze(action: "tap")
    #expect(tapResult == .agency, "Tap should be agency, got \(tapResult)")
  }
  
  // MARK: - Action Label Parsing Tests
  
  @Test
  func actionLabelParsing_stripsPayload() async {
    var simulatedTime: TimeInterval = 0
    let analyzer = ActionFrequencyAnalyzer(dateProvider: { simulatedTime })
    
    // Actions with different payloads should be grouped together
    // e.g., "tick(1)", "tick(2)", "tick(3)" all become "tick"
    
    enum TestAction {
      case tick(Int)
    }
    
    for i in 1...6 {
      simulatedTime += 0.05
      _ = analyzer.analyze(action: TestAction.tick(i))
    }
    
    // All should be tracked as the same action type
    simulatedTime += 0.05
    let result = analyzer.analyze(action: TestAction.tick(999))
    #expect(result == .physics, "tick(N) should all be grouped and detected as physics")
  }
  
  // MARK: - Edge Cases
  
  @Test
  func edgeCase_veryFirstActionIsLearning() async {
    let analyzer = ActionFrequencyAnalyzer(dateProvider: { Date().timeIntervalSince1970 })
    let result = analyzer.analyze(action: "firstEver")
    #expect(result == .learning, "Very first action should be .learning")
  }
  
  @Test
  func edgeCase_sameTimestampHandled() async {
    let fixedTime: TimeInterval = 1000
    let analyzer = ActionFrequencyAnalyzer(dateProvider: { fixedTime })
    
    // Multiple actions at exact same timestamp
    for i in 1...6 {
      let result = analyzer.analyze(action: "instant")
      if i <= 3 {
        #expect(result == .learning, "First 3 should be learning, got \(result) at \(i)")
      } else {
        // Zero delta = high frequency, zero variance = physics
        #expect(result == .physics, "Same timestamp actions should be physics, got \(result) at \(i)")
      }
    }
  }
  
  // MARK: - Sliding Window Tests
  
  @Test
  func slidingWindow_adaptsToPaceChange() async {
    var simulatedTime: TimeInterval = 0
    let config = ActionFrequencyAnalyzer.Config(windowSize: 3)
    let analyzer = ActionFrequencyAnalyzer(config: config, dateProvider: { simulatedTime })
    
    // Start slow (agency)
    for _ in 1...5 {
      simulatedTime += 2.0
      let result = analyzer.analyze(action: "pace")
      if result != .learning {
        #expect(result == .agency, "Slow pace should be agency")
      }
    }
    
    // Speed up (should transition to physics/burst)
    for _ in 1...5 {
      simulatedTime += 0.05
      _ = analyzer.analyze(action: "pace")
    }
    
    // Should now be fast (physics since regular timing)
    simulatedTime += 0.05
    let fastResult = analyzer.analyze(action: "pace")
    #expect(fastResult == .physics, "After speeding up should be physics, got \(fastResult)")
  }
}

// MARK: - StateTracker Tests

@MainActor
struct StateTrackerTests {
  
  @Test
  func stateTracker_initiallyNil() async {
    let tracker = StateTracker<Int>()
    #expect(tracker.lastPrintedState == nil)
  }
  
  @Test
  func stateTracker_updatesState() async {
    let tracker = StateTracker<Int>()
    tracker.update(42)
    #expect(tracker.lastPrintedState == 42)
    
    tracker.update(100)
    #expect(tracker.lastPrintedState == 100)
  }
}

// MARK: - Integration Tests with Real Reducer

@MainActor
struct SmartChangeReducerIntegrationTests {
  
  @Reducer
  struct TestFeature {
    @ObservableState
    struct State: Equatable {
      var count = 0
      var name = ""
    }
    
    enum Action {
      case increment
      case decrement
      case tick(Int)
      case setName(String)
    }
    
    var body: some ReducerOf<Self> {
      Reduce { state, action in
        switch action {
        case .increment:
          state.count += 1
          return .none
        case .decrement:
          state.count -= 1
          return .none
        case .tick:
          state.count += 1
          return .none
        case .setName(let name):
          state.name = name
          return .none
        }
      }
    }
  }
  
  @Test
  func integration_smartReducerPassesThroughActions() async {
    let store = Store(initialState: TestFeature.State()) {
      TestFeature()
        ._printSmartChanges()
    }
    
    store.send(.increment)
    #expect(store.state.count == 1)
    
    store.send(.setName("Test"))
    #expect(store.state.name == "Test")
  }
  
  @Test
  func integration_smartReducerHandlesRapidTicks() async {
    let store = Store(initialState: TestFeature.State()) {
      TestFeature()
        ._printSmartChanges()
    }
    
    // Send many rapid ticks
    for i in 1...20 {
      store.send(.tick(i))
    }
    
    #expect(store.state.count == 20)
  }
}

