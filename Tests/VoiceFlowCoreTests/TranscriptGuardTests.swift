import Testing
@testable import VoiceFlowCore

@Suite struct TranscriptGuardTests {
    @Test func leavesNormalDictationUntouched() {
        let text = "Call getUserById with the ID from the request params, then run npm run dev."
        let (out, flags) = TranscriptGuard.clean(text, speechSeconds: 4)
        #expect(out == text)
        #expect(flags.isEmpty)
    }

    @Test func keepsCodeLikeBracketsAndParentheses() {
        let text = "Read array[index] and call save(user) before (optionally) logging."
        let (out, flags) = TranscriptGuard.clean(text, speechSeconds: 4)
        #expect(out == text)
        #expect(flags.isEmpty)
    }

    @Test func removesNonSpeechTags() {
        let (out, flags) = TranscriptGuard.clean("[BLANK_AUDIO] Deploy the service (upbeat music) now *laughs*", speechSeconds: 3)
        #expect(out == "Deploy the service now")
        #expect(flags == [.removedNonSpeechTag])
    }

    @Test func collapsesPhraseLoops() {
        let (out, flags) = TranscriptGuard.clean("Run the tests. Run the tests. Run the tests. Run the tests. Then deploy.", speechSeconds: 3)
        #expect(out == "Run the tests. Then deploy.")
        #expect(flags == [.collapsedRepetition])
    }

    @Test func keepsNaturalWordEmphasis() {
        let text = "No, no, no, that's not the right branch."
        let (out, flags) = TranscriptGuard.clean(text, speechSeconds: 3)
        #expect(out == text)
        #expect(flags.isEmpty)
    }

    @Test func keepsTwiceRepeatedPhrase() {
        let text = "Check the logs, check the logs again."
        #expect(TranscriptGuard.clean(text, speechSeconds: 3).text == text)
    }

    @Test func dropsStockPhraseOnlyWhenLittleSpeech() {
        #expect(TranscriptGuard.clean("Thank you.", speechSeconds: 0.3) == ("", [.droppedSilenceHallucination]))
        #expect(TranscriptGuard.clean("Thank you.", speechSeconds: 2.0).text == "Thank you.")
    }
}

@Suite struct STTModelTests {
    @Test func quickStatusChecksPresenceAndSize() {
        let m = STTModel.largeV3TurboQ8
        #expect(STTModelValidation.quickStatus(for: m, fileSize: nil) == .missing)
        #expect(STTModelValidation.quickStatus(for: m, fileSize: m.sizeBytes) == .installed)
        #expect(STTModelValidation.quickStatus(for: m, fileSize: 1000) == .corrupted(reason: "size 1000 bytes, expected \(m.sizeBytes)"))
    }

    @Test func checksumComparisonIsCaseInsensitive() {
        let m = STTModel.mediumEnQ8
        #expect(STTModelValidation.status(for: m, computedSHA256: m.sha256.uppercased()) == .installed)
        #expect(STTModelValidation.status(for: m, computedSHA256: "00") == .corrupted(reason: "checksum mismatch"))
    }

    @Test func verificationRecordInvalidatesOnChange() {
        let m = STTModel.largeV3TurboQ8
        let record = ModelVerificationRecord(modelID: m.id, sizeBytes: m.sizeBytes, modificationTime: 100, sha256: m.sha256)
        #expect(record.matches(m, sizeBytes: m.sizeBytes, modificationTime: 100))
        #expect(!record.matches(m, sizeBytes: m.sizeBytes, modificationTime: 101))
        #expect(!record.matches(.mediumEnQ8, sizeBytes: m.sizeBytes, modificationTime: 100))
    }

    @Test func catalogLookup() {
        #expect(STTModel.model(id: "large-v3-turbo-q8_0") == .largeV3TurboQ8)
        #expect(STTModel.model(id: "nope") == nil)
    }
}
