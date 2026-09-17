import AppKit
import Testing
@testable import VoiceFlow
import VoiceFlowCore

@MainActor
@Suite struct IndicatorPositionTests {
    @Test func savedPositionOnAScreenIsUsed() throws {
        let screen = try #require(NSScreen.screens.first)
        let saved = VoiceFlowCore.Settings.IndicatorPosition(x: screen.frame.minX + 100, y: screen.frame.minY + 100)
        #expect(IndicatorController.origin(for: saved) == NSPoint(x: saved.x, y: saved.y))
    }

    @Test func offScreenOrMissingPositionFallsBackToBottomCenter() throws {
        let offScreen = VoiceFlowCore.Settings.IndicatorPosition(x: -50_000, y: -50_000)
        #expect(IndicatorController.origin(for: offScreen) == IndicatorController.defaultOrigin())
        #expect(IndicatorController.origin(for: nil) == IndicatorController.defaultOrigin())
        let origin = IndicatorController.defaultOrigin()
        #expect(NSScreen.screens.contains { $0.visibleFrame.contains(NSPoint(x: origin.x + 10, y: origin.y + 10)) })
    }
}
