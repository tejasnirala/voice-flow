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

@Suite struct MultilingualScoringTests {
    @Test func devanagariWordsStayWhole() {
        #expect(TranscriptNormalizer.words("कल की meeting को postpone कर देते हैं।") == ["कल", "की", "meeting", "को", "postpone", "कर", "देते", "हैं"])
    }

    @Test func germanUmlautsAndEszett() {
        #expect(TranscriptNormalizer.words("Füge das Skript zur package.json hinzu, draußen!") == ["füge", "das", "skript", "zur", "package", "json", "hinzu", "draußen"])
    }

    @Test func hinglishSpellingVariantsShareAKey() {
        func keys(_ text: String) -> [String] { TranscriptNormalizer.words(text).map(TranscriptNormalizer.romanizedHindiKey) }
        #expect(keys("Baarish nahin ho rahi, main thodi der se aaunga") == keys("barish nahi ho rahi mein thodi der se aunga"))
        #expect(keys("kal") != keys("aaj"))
        #expect(TranscriptNormalizer.romanizedHindiKey("हैं") == "हैं")
    }
}
