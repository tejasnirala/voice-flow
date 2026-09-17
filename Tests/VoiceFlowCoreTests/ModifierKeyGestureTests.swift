import Testing
@testable import VoiceFlowCore

@Suite struct ModifierKeyGestureTests {
    @Test func holdRecordsUntilRelease() {
        var g = ModifierKeyGesture()
        #expect(g.handle(.keyDown, at: 10) == [.startRecording])
        #expect(g.handle(.keyUp, at: 12.5) == [.finishRecording])
        #expect(g.phase == .idle)
    }

    @Test func singleQuickTapIsDiscardedAfterWindow() {
        var g = ModifierKeyGesture()
        #expect(g.handle(.keyDown, at: 10) == [.startRecording])
        #expect(g.handle(.keyUp, at: 10.1) == [.scheduleDoubleTapTimeout(seconds: 0.4)])
        #expect(g.handle(.doubleTapTimeout, at: 10.5) == [.cancelRecording])
        #expect(g.phase == .idle)
    }

    @Test func doubleTapEntersHandsFreeAndNextPressFinishes() {
        var g = ModifierKeyGesture()
        _ = g.handle(.keyDown, at: 10)
        _ = g.handle(.keyUp, at: 10.1)
        #expect(g.handle(.keyDown, at: 10.3) == [.enteredHandsFree])
        #expect(g.isHandsFree)
        #expect(g.handle(.keyUp, at: 10.4) == [])
        #expect(g.handle(.doubleTapTimeout, at: 10.5) == []) // late timer is ignored
        #expect(g.isHandsFree)
        #expect(g.handle(.keyDown, at: 40) == [.finishRecording])
        #expect(!g.isHandsFree)
        #expect(g.handle(.keyUp, at: 40.1) == [])
        #expect(g.phase == .idle)
    }

    @Test func chordWhileHoldingCancels() {
        var g = ModifierKeyGesture()
        _ = g.handle(.keyDown, at: 10)
        #expect(g.handle(.chord, at: 10.05) == [.cancelRecording])
        #expect(g.handle(.keyUp, at: 10.3) == []) // release after a chord does nothing
        #expect(g.phase == .idle)
    }

    @Test func chordInHandsFreeModeIsIgnored() {
        var g = ModifierKeyGesture()
        _ = g.handle(.keyDown, at: 10); _ = g.handle(.keyUp, at: 10.1)
        _ = g.handle(.keyDown, at: 10.2); _ = g.handle(.keyUp, at: 10.3)
        #expect(g.handle(.chord, at: 12) == [])
        #expect(g.isHandsFree)
    }

    @Test func holdThresholdBoundary() {
        var g = ModifierKeyGesture()
        _ = g.handle(.keyDown, at: 0)
        #expect(g.handle(.keyUp, at: ModifierKeyGesture.tapMaxSeconds) == [.finishRecording])
    }

    @Test func secondPressAfterWindowStartsANewDictation() {
        var g = ModifierKeyGesture()
        _ = g.handle(.keyDown, at: 10); _ = g.handle(.keyUp, at: 10.1)
        #expect(g.handle(.keyDown, at: 10.6) == [.cancelRecording, .startRecording])
        #expect(g.handle(.keyUp, at: 11.5) == [.finishRecording])
    }

    @Test func tripleTapLocksThenFinishes() {
        var g = ModifierKeyGesture()
        _ = g.handle(.keyDown, at: 10); _ = g.handle(.keyUp, at: 10.1)
        _ = g.handle(.keyDown, at: 10.2); _ = g.handle(.keyUp, at: 10.3)
        #expect(g.handle(.keyDown, at: 10.4) == [.finishRecording])
    }

    @Test func resetReturnsToIdle() {
        var g = ModifierKeyGesture()
        _ = g.handle(.keyDown, at: 10); _ = g.handle(.keyUp, at: 10.1); _ = g.handle(.keyDown, at: 10.2)
        g.reset()
        #expect(g.phase == .idle)
        #expect(g.handle(.keyDown, at: 20) == [.startRecording])
    }
}
