import Testing
@testable import VoiceFlowCore

@Suite struct PackagingTests {
    @Test func coreMLEncoderInstallCommandMatchesFetchScript() {
        #expect(STTModel.mediumEnQ8.coreMLEncoderInstallCommand == "scripts/fetch-models.sh whisper-coreml medium.en")
        #expect(STTModel.largeV3TurboQ8.coreMLEncoderInstallCommand == "scripts/fetch-models.sh whisper-coreml large-v3-turbo")
        #expect(STTModel.mediumEnQ8.installCommand == "scripts/fetch-models.sh whisper medium.en-q8_0")
    }

    @Test func versionFallsBackOutsideTheBundle() {
        #expect(!BuildInfo.version.isEmpty)
        #expect(BuildInfo.defaultVersion == "1.0.0")
    }
}
