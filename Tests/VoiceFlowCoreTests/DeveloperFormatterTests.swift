import Testing
@testable import VoiceFlowCore

@Suite struct DeveloperFormatterTests {
    @Test(arguments: [
        ("Add the script to package dot json.", "Add the script to package.json."),
        ("Never commit the dot env file.", "Never commit the .env file."),
        ("Put the API key in dot env dot local.", "Put the API key in .env.local."),
        ("Enable strict mode in tsconfig dot json.", "Enable strict mode in tsconfig.json."),
        ("Enable strict mode in ts config dot json.", "Enable strict mode in tsconfig.json."),
        ("It is defined in docker compose dot yml.", "It is defined in docker-compose.yml."),
        ("Run npm install dash dash save-dev.", "Run npm install --save-dev."),
        ("Run git checkout dash b feature slash login.", "Run git checkout -b feature/login."),
        ("Set database underscore url in the environment.", "Set DATABASE_URL in the environment."),
        ("Rename it to user underscore session underscore id.", "Rename it to user_session_id."),
        ("We use next js with typescript and postgres q l.", "We use Next.js with TypeScript and PostgreSQL."),
        ("The graphql api uses jwt and oauth.", "The GraphQL API uses JWT and OAuth."),
        ("Store it in redis, not mongodb.", "Store it in Redis, not MongoDB."),
        ("The database is postgreSQL with a redis cache.", "The database is PostgreSQL with a Redis cache."),
    ])
    func formats(input: String, expected: String) {
        #expect(DeveloperFormatter.format(input) == expected)
    }

    @Test(arguments: [
        "I'll express my concerns and react calmly.",       // ordinary English words stay
        "Meet me at the dot on the map.",                    // "dot" without a file suffix
        "It was a hyphen between two words.",                // "hyphen" not followed by a single letter or flag
        "Draw a slash.",                                     // nothing to join
        "Call getUserById with postgresUrl.",                // already-formatted identifiers untouched
        "docker compose up and git rebase main",             // commands keep their lowercase form
        "cd into src and run it",
    ])
    func leavesNonTechnicalOrFormattedTextAlone(input: String) {
        #expect(DeveloperFormatter.format(input) == input)
    }
}

extension DeveloperFormatterTests {
    @Test func leadingDotAfterVerbsAndGrammarWords() {
        #expect(DeveloperFormatter.format("Open dot gitignore and edit dot env.") == "Open .gitignore and edit .env.")
    }
}
