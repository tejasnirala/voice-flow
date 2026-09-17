import Testing
@testable import VoiceFlowCore

@Suite struct TextModeTests {
    let transcript = "um we need to update the the package dot json and dash dash save the next js dependency"

    @Test func rawKeepsTheTranscript() {
        #expect(TextProcessingPlan.prepare(transcript, mode: .raw) == transcript)
    }

    @Test func cleanRemovesHesitationsAndStuttersOnly() {
        #expect(TextProcessingPlan.prepare(transcript, mode: .clean)
                == "We need to update the package dot json and dash dash save the next js dependency.")
    }

    @Test func developerAlsoFormatsSymbolsAndTerms() {
        #expect(TextProcessingPlan.prepare(transcript, mode: .developer)
                == "We need to update the package.json and --save the Next.js dependency.")
    }

    @Test func modelUseFollowsModeAndSmartSetting() {
        #expect(!TextMode.raw.usesModel(processing: .smart))
        #expect(!TextMode.clean.usesModel(processing: .fast))
        #expect(TextMode.clean.usesModel(processing: .smart))
        #expect(TextMode.developer.usesModel(processing: .smart))
        #expect(TextMode.prompt.usesModel(processing: .fast))
        #expect(TextMode.writing.usesModel(processing: .fast))
    }

    @Test func developerRewriteIsReformattedAfterTheGuard() {
        let prepared = "Rename it to user_id in package.json."
        let (text, verdict) = TextProcessingPlan.finalText(prepared: prepared, rewrite: "Rename it to user_id in package.json.",
                                                           terms: [], mode: .developer)
        #expect(verdict == .accept)
        #expect(text == prepared)
    }

    @Test func rejectedRewriteFallsBackToPreparedText() {
        let prepared = "Write a function that returns the active users."
        let (text, verdict) = TextProcessingPlan.finalText(prepared: prepared,
                                                           rewrite: "```ts\nconst active = users.filter(u => u.active)\n```",
                                                           terms: [], mode: .prompt)
        #expect(verdict != .accept)
        #expect(text == prepared)
    }
}

@Suite struct ContentPreservingGuardTests {
    let terms = RewriteGuard.terms(fromVocabulary: "Next.js, React, PostgreSQL, Redis, JWT")

    @Test(arguments: [
        ("so I want you to write a function that returns the active users and it should handle an empty array",
         "I want you to write a function that returns the active users.\n- It should handle an empty array."),
        ("thanks for the update I will review it tomorrow", "Thanks for the update. I will review it tomorrow."),
        ("we deploy to AWS but the analytics team uses Azure and GCP",
         "We deploy to AWS, but the analytics team uses Azure.\nThe analytics team uses GCP."),
        ("okay so I looked at the PR and it looks good", "Okay, I looked at the PR. It looks good."),
        ("so we move the token validation into a service and then we add an index",
         "Move the token validation into a service.\n- Then add an index."),
    ])
    func acceptsRestructuringWithTheSameContent(input: String, output: String) {
        #expect(RewriteGuard.evaluate(input: input, output: output, terms: terms, policy: .contentPreserving) == .accept)
    }

    @Test(arguments: [
        // answers the request / adds content
        ("explain why my Next.js page renders twice", "Your Next.js page renders twice because React strict mode double-invokes effects."),
        // synonym substitution
        ("we need to update the migration", "We must change the migration."),
        // dropped content
        ("add tests for expired tokens and invalid signatures", "Add tests for expired tokens."),
        // dropped term
        ("store the JWT in Redis", "Store the token in the cache."),
        // negation removed
        ("do not merge the PR yet", "Merge the PR yet."),
        // same words, swapped meaning
        ("move sessions from PostgreSQL to Redis", "Move sessions from Redis to PostgreSQL."),
        ("the deploy failed after the Redis upgrade can you share the logs", "Can you share the logs? The deploy failed after the Redis upgrade."),
        ("move the sessions from PostgreSQL to Redis", "Move the sessions to PostgreSQL from Redis."),
        // swapped logic, modality, quantity, person
        ("cache it in Redis or in memory", "Cache it in Redis and in memory."),
        ("deploy if the tests pass", "Deploy when the tests pass."),
        ("we should add retries", "We can add retries."),
        ("check all the pods", "Check some pods."),
        ("I will review the design doc", "We will review the design doc."),
        ("we deploy to AWS but the analytics team uses Azure", "We deploy to AWS. The analytics team uses Azure."),
        ("I want you to write a function", "I want to write a function."),
        ("update the migration before we merge it", "Update the migration before we merge."),
        ("can you send me the document", "Can you send the document?"),
        ("the first release failed so we shipped a second one", "The first release failed. We shipped a second one."),
    ])
    func rejectsContentChanges(input: String, output: String) {
        #expect(RewriteGuard.evaluate(input: input, output: output, terms: terms, policy: .contentPreserving) != .accept)
    }

    @Test func strictPolicyStillRejectsRestructuring() {
        let input = "the deploy failed after the Redis upgrade can you share the logs"
        #expect(RewriteGuard.evaluate(input: input, output: "Can you share the logs? The deploy failed after the Redis upgrade.",
                                      terms: terms, policy: .strict) != .accept)
    }

    @Test func acceptedRewriteLayoutIsTidied() {
        let prepared = "Call getUserById with the id."
        #expect(TextProcessingPlan.finalText(prepared: prepared, rewrite: "- Call getUserById with the id.  ", terms: [], mode: .prompt).text
                == "Call getUserById with the id.")
        let list = TextProcessingPlan.finalText(prepared: "Refactor it and keep the errors and add tests.",
                                                rewrite: "Refactor it.   \n\n\n- Keep the errors.\n- Add tests.", terms: [], mode: .prompt)
        #expect(list.verdict == .accept)
        #expect(list.text == "Refactor it.\n\n- Keep the errors.\n- Add tests.")
    }

    @Test func cleanKeepsLineBreaksOnlyAroundLists() {
        let prepared = "Hey, quick update. The review went well. We need two things first tests and second docs. Thanks."
        let rewrite = "Hey, quick update.\nThe review went well.\n\nWe need two things:\n- Tests.\n- Docs.\nThanks."
        let clean = TextProcessingPlan.finalText(prepared: prepared, rewrite: rewrite, terms: [], mode: .clean)
        #expect(clean.verdict == .accept)
        #expect(clean.text == "Hey, quick update. The review went well. We need two things:\n- Tests.\n- Docs.\nThanks.")
        let writing = TextProcessingPlan.finalText(prepared: prepared, rewrite: rewrite, terms: [], mode: .writing)
        #expect(writing.text == "Hey, quick update.\nThe review went well.\n\nWe need two things:\n- Tests.\n- Docs.\nThanks.")
    }
}

@Suite struct GrammarFixTests {
    @Test func rewriteCannotLoseATranscriptApostrophe() {
        let prepared = "I have opened the Apple's Notes application and the users' files."
        let (text, verdict) = TextProcessingPlan.finalText(prepared: prepared,
                                                           rewrite: "I have opened the Apples Notes application, and the users files.",
                                                           terms: [], mode: .writing)
        #expect(verdict == .accept)
        #expect(text == "I have opened the Apple's Notes application, and the users' files.")
        // "it's" → "its" is a different word, so the guard rejects it outright.
        #expect(RewriteGuard.evaluate(input: "and it's slow", output: "And its slow.", terms: [], policy: .contentPreserving) != .accept)
        // A word the transcript also wrote without an apostrophe is ambiguous: left as the rewrite has it.
        #expect(TextProcessingPlan.restoreApostrophes(from: "its tail and it's here", in: "its tail and its here") == "its tail and its here")
        #expect(TextProcessingPlan.restoreApostrophes(from: "the users' files", in: "The users files") == "The users' files")
    }

    @Test func modelMayAddPossessiveApostrophes() {
        let (text, verdict) = TextProcessingPlan.finalText(prepared: "I have opened the apples notes application.",
                                                           rewrite: "I have opened Apple's Notes application.", terms: [], mode: .clean)
        #expect(verdict == .accept)
        #expect(text == "I have opened Apple's Notes application.")
    }

    @Test(arguments: [
        ("i dont think it works", "I don't think it works."),
        ("Im not sure whats wrong but theyre looking", "I'm not sure what's wrong but they're looking."),
        ("we cant go and its tail wont move", "We cant go and its tail wont move."),
        ("Dont merge yet", "Don't merge yet."),
    ])
    func missingContractionApostrophes(input: String, expected: String) {
        #expect(RuleBasedCleanup.clean(input) == expected)
    }

    @Test func strictAllowsAgreementAndSentenceOpeners() {
        #expect(RewriteGuard.evaluate(input: "Okay, so the tests is failing. So we fix it.",
                                      output: "The tests are failing. We fix it.", terms: []) == .accept)
        // "so" meaning "therefore" mid-sentence is still content, and agreement swaps stay within their group.
        #expect(RewriteGuard.evaluate(input: "It failed so we fixed it.", output: "It failed. We fixed it.", terms: []) != .accept)
        #expect(RewriteGuard.evaluate(input: "The test is failing.", output: "The test was failing.", terms: []) != .accept)
    }
}
