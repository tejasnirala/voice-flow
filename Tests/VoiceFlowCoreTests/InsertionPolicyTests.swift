import Testing
@testable import VoiceFlowCore

@Suite struct InsertionPolicyTests {
    @Test func pastesWhenSameAppAndPermitted() {
        #expect(InsertionPolicy.decide(accessibilityGranted: true, dictationAppPID: 10, dictationAppName: "Code",
                                       currentAppPID: 10, currentAppName: "Code") == .paste)
    }

    @Test func focusChangeLeavesTextOnClipboard() {
        #expect(InsertionPolicy.decide(accessibilityGranted: true, dictationAppPID: 10, dictationAppName: "Code",
                                       currentAppPID: 11, currentAppName: "Slack")
                == .leaveOnClipboard(.focusChanged(from: "Code", to: "Slack")))
    }

    @Test func focusChangeIsReportedBeforeMissingPermission() {
        #expect(InsertionPolicy.decide(accessibilityGranted: false, dictationAppPID: 10, dictationAppName: "Code",
                                       currentAppPID: 11, currentAppName: "Slack")
                == .leaveOnClipboard(.focusChanged(from: "Code", to: "Slack")))
    }

    @Test func missingPermissionLeavesTextOnClipboard() {
        #expect(InsertionPolicy.decide(accessibilityGranted: false, dictationAppPID: 10, dictationAppName: "Code",
                                       currentAppPID: 10, currentAppName: "Code") == .leaveOnClipboard(.accessibilityNotGranted))
    }

    @Test func noFocusedApp() {
        #expect(InsertionPolicy.decide(accessibilityGranted: true, dictationAppPID: nil, dictationAppName: nil,
                                       currentAppPID: nil, currentAppName: nil) == .leaveOnClipboard(.noFocusedApp))
    }

    @Test func unknownDictationAppStillPastes() {
        #expect(InsertionPolicy.decide(accessibilityGranted: true, dictationAppPID: nil, dictationAppName: nil,
                                       currentAppPID: 10, currentAppName: "Code") == .paste)
    }

    @Test func restoresOnlyIfClipboardUnchangedSinceWrite() {
        #expect(InsertionPolicy.shouldRestoreClipboard(changeCountAfterWrite: 42, currentChangeCount: 42))
        #expect(!InsertionPolicy.shouldRestoreClipboard(changeCountAfterWrite: 42, currentChangeCount: 43))
    }
}
