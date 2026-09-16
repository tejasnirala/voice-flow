import Testing
@testable import VoiceFlowCore

@Test func buildInfoIsPopulated() {
    #expect(BuildInfo.name == "VoiceFlow")
    #expect(!BuildInfo.version.isEmpty)
}
