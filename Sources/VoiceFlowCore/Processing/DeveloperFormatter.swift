import Foundation

/// Deterministic developer formatting for Developer mode: spoken symbols in unambiguous patterns and canonical casing of
/// product names that aren't also ordinary English words or commands. Conservative by design (spec §13): when a pattern
/// isn't clearly technical, the words are left alone.
public enum DeveloperFormatter {
    /// Extensions and dotted suffixes that make "<word> dot <x>" a file or name ("package dot json", "next dot js").
    static let dotSuffixes: Set<String> = ["json", "js", "ts", "tsx", "jsx", "mjs", "cjs", "yml", "yaml", "env", "local",
                                           "example", "conf", "config", "md", "py", "go", "rs", "swift", "toml", "lock",
                                           "txt", "sh", "zsh", "html", "css", "scss", "sql", "xml", "csv", "log", "ini",
                                           "plist", "dockerignore", "gitignore", "prisma", "graphql", "vue", "svelte", "rb"]

    /// Canonical spellings applied case-insensitively. Excludes words with ordinary meanings or lowercase command forms
    /// (express, react, swift, go, docker, git, node, next, rest, cd).
    static let canonicalTerms: [String: String] = [
        "postgresql": "PostgreSQL", "postgres": "Postgres", "mysql": "MySQL", "mongodb": "MongoDB", "redis": "Redis",
        "rabbitmq": "RabbitMQ", "kafka": "Kafka", "kubernetes": "Kubernetes", "graphql": "GraphQL", "websocket": "WebSocket",
        "websockets": "WebSockets", "oauth": "OAuth", "jwt": "JWT", "json": "JSON", "api": "API", "apis": "APIs", "url": "URL",
        "urls": "URLs", "http": "HTTP", "https": "HTTPS", "aws": "AWS", "gcp": "GCP", "github": "GitHub", "gitlab": "GitLab",
        "nginx": "Nginx", "typescript": "TypeScript", "javascript": "JavaScript", "nestjs": "NestJS", "sql": "SQL",
        "css": "CSS", "html": "HTML", "ci": "CI", "ssh": "SSH", "cli": "CLI", "sdk": "SDK", "ui": "UI", "ux": "UX",
    ]

    /// Multi-word spoken names → canonical (matched on whole words, case-insensitively).
    static let spokenNames: [([String], String)] = [
        (["engine", "x", "dot", "conf"], "nginx.conf"), (["engine", "x.conf"], "nginx.conf"),
        (["ts", "config", "dot", "json"], "tsconfig.json"), (["docker", "compose", "dot", "yaml"], "docker-compose.yaml"),
        (["docker", "compose", "dot", "yml"], "docker-compose.yml"), (["package", "lock", "dot", "json"], "package-lock.json"),
        (["next", "dot", "js"], "Next.js"), (["next", "js"], "Next.js"), (["nextjs"], "Next.js"),
        (["node", "dot", "js"], "Node.js"), (["node", "js"], "Node.js"), (["nodejs"], "Node.js"),
        (["vue", "dot", "js"], "Vue.js"), (["nuxt", "dot", "js"], "Nuxt.js"),
        (["postgres", "q", "l"], "PostgreSQL"), (["postgre", "sql"], "PostgreSQL"), (["my", "sql"], "MySQL"),
        (["graph", "q", "l"], "GraphQL"), (["type", "script"], "TypeScript"), (["java", "script"], "JavaScript"),
        (["web", "socket"], "WebSocket"), (["mongo", "db"], "MongoDB"), (["rabbit", "m", "q"], "RabbitMQ"),
    ]

    /// Formats each line separately, keeping line breaks and list markers.
    public static func format(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let body = line.dropFirst(indent.count)
            for marker in ["- ", "* ", "• "] where body.hasPrefix(marker) {
                return indent + marker + formatLine(String(body.dropFirst(marker.count)))
            }
            return indent + formatLine(String(body))
        }.joined(separator: "\n")
    }

    /// Hindi/Hinglish identifier rule, line by line (see `DeveloperCorrections.applyHindiCallIdentifiers`).
    public static func formatHindiIdentifiers(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            DeveloperCorrections.applyHindiCallIdentifiers(line.split(separator: " ", omittingEmptySubsequences: false).map(String.init))
                .joined(separator: " ")
        }.joined(separator: "\n")
    }

    static func formatLine(_ text: String) -> String {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        tokens = applySpokenNames(tokens)
        tokens = applySymbols(tokens)
        tokens = DeveloperCorrections.apply(tokens)
        tokens = tokens.map(applyCasing)
        return tokens.joined(separator: " ")
    }

    // MARK: Pieces

    /// Splits a token into (leading punctuation, core, trailing punctuation) so "json," keeps its comma.
    static func split(_ token: String) -> (String, String, String) {
        let leadEnd = token.firstIndex { !"\"'(“‘[".contains($0) } ?? token.endIndex
        let trailStart = token[leadEnd...].lastIndex { !".,;:!?\"')”’]".contains($0) }.map { token.index(after: $0) } ?? leadEnd
        return (String(token[..<leadEnd]), String(token[leadEnd..<trailStart]), String(token[trailStart...]))
    }

    /// Only whole tokens are recased ("postgreSQL" → "PostgreSQL"); identifiers like "postgresUrl" aren't dictionary terms.
    static func applyCasing(_ token: String) -> String {
        let (lead, core, trail) = split(token)
        guard let canonical = canonicalTerms[core.lowercased()] else { return token }
        return lead + canonical + trail
    }

    static func applySpokenNames(_ tokens: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        outer: while i < tokens.count {
            for (words, canonical) in spokenNames where i + words.count <= tokens.count {
                let run = tokens[i..<i + words.count].map { split($0) }
                // Only the last word may carry trailing punctuation, and only the first leading punctuation.
                guard run.dropLast().allSatisfy({ $0.2.isEmpty }), run.dropFirst().allSatisfy({ $0.0.isEmpty }) else { continue }
                if run.map({ $0.1.lowercased() }) == words {
                    out.append(run.first!.0 + canonical + run.last!.2)
                    i += words.count
                    continue outer
                }
            }
            out.append(tokens[i])
            i += 1
        }
        return out
    }

    /// Joins spoken symbols: "a dot json" → "a.json", "dot env" → ".env", "dash dash save" → "--save",
    /// "dash b" → "-b", "user underscore id" → "user_id", "feature slash login" → "feature/login".
    static func applySymbols(_ tokens: [String]) -> [String] {
        var t = tokens
        func core(_ i: Int) -> String { split(t[i]).1.lowercased() }
        func plain(_ i: Int) -> Bool { let (l, c, r) = split(t[i]); return l.isEmpty && r.isEmpty && !c.isEmpty }
        var changed = true
        while changed {
            changed = false
            var i = 0
            while i < t.count {
                let word = core(i)
                // dash dash <flag>  /  dash <single letter>
                if (word == "dash" || word == "hyphen"), plain(i), i + 1 < t.count {
                    if (core(i + 1) == "dash" || core(i + 1) == "hyphen"), plain(i + 1), i + 2 < t.count {
                        let (_, c, r) = split(t[i + 2])
                        if c.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }), !c.isEmpty {
                            t.replaceSubrange(i...(i + 2), with: ["--" + c.lowercased() + r]); changed = true; break
                        }
                    }
                    let (_, c, r) = split(t[i + 1])
                    if c.count == 1, c.first!.isLetter, i > 0 {
                        t.replaceSubrange(i...(i + 1), with: ["-" + c + r]); changed = true; break
                    }
                }
                // <word> dot <suffix>  /  dot <suffix> at a word start
                if word == "dot", plain(i), i + 1 < t.count {
                    let (_, next, trail) = split(t[i + 1])
                    let suffixOK = dotSuffixes.contains(next.lowercased())
                    // Joined to the previous word unless that's a grammar word ("the dot env" → "the .env").
                    if suffixOK, i > 0, split(t[i - 1]).2.isEmpty, !split(t[i - 1]).1.isEmpty,
                       !RewriteGuard.functionWords.contains(split(t[i - 1]).1.lowercased()),
                       !["commit", "edit", "open", "update", "add", "create", "check", "read", "copy", "delete"].contains(split(t[i - 1]).1.lowercased()) {
                        let (lead, prev, _) = split(t[i - 1])
                        t.replaceSubrange((i - 1)...(i + 1), with: [lead + prev + "." + next.lowercased() + trail]); changed = true; break
                    }
                    if suffixOK {
                        t.replaceSubrange(i...(i + 1), with: ["." + next.lowercased() + trail]); changed = true; break
                    }
                }
                // <a> underscore <b>  /  <a> slash <b>
                if (word == "underscore" || word == "slash"), plain(i), i > 0, i + 1 < t.count,
                   split(t[i - 1]).2.isEmpty, !split(t[i - 1]).1.isEmpty, split(t[i + 1]).0.isEmpty, !split(t[i + 1]).1.isEmpty {
                    let symbol = word == "underscore" ? "_" : "/"
                    let (lead, prev, _) = split(t[i - 1])
                    let (_, next, trail) = split(t[i + 1])
                    t.replaceSubrange((i - 1)...(i + 1), with: [lead + prev + symbol + next + trail]); changed = true; break
                }
                i += 1
            }
        }
        return t
    }
}
