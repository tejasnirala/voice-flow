import Testing
@testable import VoiceFlowCore

@Suite struct TranscriptNormalizerTests {
    @Test func stripsPunctuationAndCase() {
        #expect(TranscriptNormalizer.words("Hello, this is a TEST.") == ["hello", "this", "is", "a", "test"])
    }

    @Test func convertsNumberWords() {
        #expect(TranscriptNormalizer.words("fifteen minutes") == ["15", "minutes"])
        #expect(TranscriptNormalizer.words("twenty one days, thirty") == ["21", "days", "30"])
        #expect(TranscriptNormalizer.words("three o'clock") == ["3", "oclock"])
    }

    @Test func termKeysAreSeparatorFree() {
        #expect(TranscriptNormalizer.key("Next.js") == "nextjs")
        #expect(TranscriptNormalizer.key("npm run dev") == "npmrundev")
        #expect(TranscriptNormalizer.key(".env.local") == "envlocal")
    }

    @Test(arguments: [
        ("call getUserById now", "getUserById"),
        ("call get user by ID now", "getUserById"),
        ("we use Postgres QL here", "PostgreSQL"),
        ("open dot env dot local", ".env.local"),
        ("the user underscore session table", "user_session"),
    ])
    func mergesSpellingVariants(text: String, term: String) {
        let key = TranscriptNormalizer.key(term)
        #expect(TranscriptNormalizer.mergeTerms(TranscriptNormalizer.words(text), keys: [key]).contains(key))
    }

    @Test func doesNotMergeMisheardTerms() {
        let key = TranscriptNormalizer.key("getUserById")
        #expect(!TranscriptNormalizer.mergeTerms(TranscriptNormalizer.words("get user by eid"), keys: [key]).contains(key))
        let pg = TranscriptNormalizer.key("PostgreSQL")
        #expect(!TranscriptNormalizer.mergeTerms(TranscriptNormalizer.words("post-guessql"), keys: [pg]).contains(pg))
    }

    @Test func doesNotMatchInsideLongerWords() {
        let key = TranscriptNormalizer.key(".env")
        #expect(!TranscriptNormalizer.mergeTerms(TranscriptNormalizer.words("the environment"), keys: [key]).contains(key))
    }
}

@Suite struct AccuracyScorerTests {
    @Test func perfectTranscriptScoresZero() {
        let s = AccuracyScorer.score(reference: "Run npm run dev.", spoken: "Run npm run dev.",
                                     hypothesis: "run NPM run dev", terms: ["npm run dev"])
        #expect(s.words.errors == 0)
        #expect(s.missedTerms.isEmpty)
        #expect(s.exactTerms.isEmpty) // "NPM" casing differs from canonical "npm run dev"
        #expect(s.formatted.errors > 0)
    }

    @Test func countsEditOperations() {
        let c = AccuracyScorer.editCounts(reference: ["a", "b", "c", "d"], hypothesis: ["a", "x", "c", "d", "e"])
        #expect(c == EditCounts(substitutions: 1, deletions: 0, insertions: 1, referenceWords: 4))
        #expect(c.rate == 0.5)
        let d = AccuracyScorer.editCounts(reference: ["a", "b"], hypothesis: [])
        #expect(d.deletions == 2)
    }

    @Test func recognizedIdentifierIsSpellingAgnostic() {
        let s = AccuracyScorer.score(reference: "Call getUserById.", spoken: "call get user by id",
                                     hypothesis: "Call getUserById.", terms: ["getUserById"])
        #expect(s.words.errors == 0)
        #expect(s.recognizedTerms == ["getUserById"])
        #expect(s.exactTerms == ["getUserById"])
    }

    @Test func misheardMultiWordTermIsScoredWordByWord() {
        let s = AccuracyScorer.score(reference: "Do a git rebase main before you push.",
                                     spoken: "Do a git rebase main before you push.",
                                     hypothesis: "Do a get rebasement before you push.", terms: ["git rebase main"])
        #expect(s.missedTerms == ["git rebase main"])
        // git→get, rebase→rebasement, main deleted: 3 errors over 8 spoken words (not inflated).
        #expect(s.words.errors == 3)
        #expect(s.words.referenceWords == 8)
    }

    @Test func misheardTermIsMissedAndCounted() {
        let s = AccuracyScorer.score(reference: "Use Redis for caching.", spoken: "Use Redis for caching.",
                                     hypothesis: "Use radisso for caching.", terms: ["Redis"])
        #expect(s.missedTerms == ["Redis"])
        #expect(s.words.substitutions == 1)
    }

    @Test func spokenVariantsCountAsRecognizedButNotExact() {
        let s = AccuracyScorer.score(reference: "Run kubectl get pods.", spoken: "Run kube control get pods.",
                                     hypothesis: "Run kube control get pods.", terms: ["kubectl get pods|kube control get pods"])
        #expect(s.recognizedTerms == ["kubectl get pods"])
        #expect(s.exactTerms.isEmpty)
        #expect(s.words.errors == 0)
    }

    @Test func separatorWordsDoNotCountTowardWER() {
        let s = AccuracyScorer.score(reference: "Never commit the .env file.", spoken: "Never commit the dot env file.",
                                     hypothesis: "Never commit the .env file.", terms: [".env"])
        #expect(s.words.errors == 0)
        #expect(s.exactTerms == [".env"])
    }

    @Test func exactTermRequiresCanonicalSpelling() {
        let s = AccuracyScorer.score(reference: "Next.js app", spoken: "Next.js app", hypothesis: "Next.js app", terms: ["Next.js"])
        #expect(s.exactTerms == ["Next.js"])
    }
}
