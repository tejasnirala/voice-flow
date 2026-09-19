import Foundation

/// Context-gated developer corrections (Phase 9, spec §13). Each rule fires only when neighbouring words make the technical
/// reading unambiguous; otherwise the words are left alone ("we don't need help for now" stays, "help chart" → "Helm chart").
/// Rules come from errors measured on the owner's recordings (docs/ACCURACY.md §8).
public enum DeveloperCorrections {
    // MARK: Vocabulary

    static let kubectlSubcommands: Set<String> = ["get", "apply", "describe", "logs", "delete", "exec", "rollout", "create",
                                                  "edit", "scale", "port-forward", "config", "top", "run", "expose", "label",
                                                  "patch", "cp", "auth", "drain", "cordon", "set", "wait", "version", "explain"]
    static let gitSubcommands: Set<String> = ["rebase", "checkout", "stash", "cherry-pick", "clone", "commit", "push", "pull",
                                              "merge", "fetch", "switch", "restore", "bisect", "blame", "reflog"]
    /// Words after which a command starts ("run git …", "then git …").
    static let commandLeadIns: Set<String> = ["run", "do", "a", "then", "and", "just", "please", "you", "i", "we", "to", "first"]
    static let reactHooks: [String: String] = [
        "state": "useState", "effect": "useEffect", "memo": "useMemo", "callback": "useCallback", "ref": "useRef",
        "context": "useContext", "reducer": "useReducer", "layout effect": "useLayoutEffect", "transition": "useTransition",
        "id": "useId", "query": "useQuery", "mutation": "useMutation", "router": "useRouter", "navigate": "useNavigate",
        "params": "useParams", "selector": "useSelector", "dispatch": "useDispatch", "form": "useForm",
    ]
    static let hookNouns: Set<String> = ["hook", "hooks"]
    static let events: Set<String> = ["click", "submit", "change", "blur", "focus", "key down", "key up", "key press",
                                      "mouse enter", "mouse leave", "mouse down", "mouse up", "load", "error", "press",
                                      "scroll", "input", "select", "close", "open", "drag", "drop", "success", "cancel"]
    static let handlerNouns: Set<String> = ["prop", "props", "handler", "handlers", "callback", "event", "listener", "attribute"]
    /// First words of function names ("refresh access token", "fetch orders").
    static let identifierVerbs: Set<String> = ["get", "set", "fetch", "create", "update", "delete", "remove", "handle",
                                               "validate", "send", "check", "load", "save", "parse", "build", "compute",
                                               "calculate", "refresh", "reset", "format", "render", "init", "initialize",
                                               "generate", "find", "is", "has", "convert", "process", "sync", "register",
                                               "normalize", "serialize", "sanitize", "map", "filter", "sort", "upload",
                                               "download", "verify", "sign", "login", "logout", "open", "close", "toggle",
                                               "apply", "merge", "resolve", "subscribe", "unsubscribe", "emit", "dispatch"]
    static let functionNouns: Set<String> = ["function", "functions", "method", "methods", "helper", "util", "utility"]
    /// Words that can't be part of a spoken identifier.
    static let identifierStops: Set<String> = ["the", "a", "an", "this", "that", "these", "those", "to", "of", "in", "for",
                                               "with", "and", "or", "but", "my", "your", "our", "their", "its", "it", "on",
                                               "at", "from", "into", "as", "so", "then", "when", "if", "not", "no", "we",
                                               "i", "you", "they", "he", "she", "be", "was", "were", "are", "will", "would",
                                               "should", "can", "could", "do", "does", "did", "which", "who", "what"]
    /// Spoken symbol words: they end a spoken identifier ("camel case user id equals" stops before "equals").
    static let symbolWords: Set<String> = ["equals", "equal", "open", "close", "left", "right", "comma", "colon", "semicolon",
                                           "quote", "dot", "slash", "dash", "hyphen", "underscore", "paren", "parenthesis",
                                           "bracket", "brace", "curly", "plus", "minus", "pipe", "ampersand", "arrow",
                                           "greater", "less", "backtick", "tilde", "asterisk", "backslash", "double", "triple",
                                           "single", "not", "at", "hash", "pound", "dollar", "exclamation", "fat"]
    static let domainSuffixes: Set<String> = ["com", "io", "dev", "org", "net", "app", "ai", "co", "sh", "cloud", "tech"]

    /// Hindi/Hinglish verbs that follow "call" when an identifier is being called ("getUserById call करो").
    static let hindiCallVerbs: Set<String> = ["करो", "कर", "करना", "करके", "करें", "करते", "हो", "होता", "होती", "होगा", "किया",
                                              "karo", "kar", "karna", "karke", "karen", "karte", "ho", "hota", "hoti", "hoga", "kiya"]

    /// Hindi and Hinglish only: "get user by id call करो" → "getUserById call करो" (2–4 words starting with a common verb,
    /// directly followed by "call" and a Hindi verb). English uses the "… function" rule instead.
    public static func applyHindiCallIdentifiers(_ tokens: [String]) -> [String] {
        var t = tokens
        var i = 0
        while i < t.count {
            if identifierVerbs.contains(core(t, i)), i == 0 || !identifierVerbs.contains(core(t, i - 1)) {
                for n in stride(from: 4, through: 2, by: -1) where clean(t, i, n) && core(t, i + n) == "call"
                    && hindiCallVerbs.contains(core(t, i + n + 1)) {
                    let ws = (0..<n).map { core(t, i + $0) }
                    guard ws.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isLetter) && $0.unicodeScalars.allSatisfy(\.isASCII) }),
                          ws.dropFirst().allSatisfy({ !identifierStops.contains($0) }) else { continue }
                    t.replaceSubrange(i..<i + n, with: wrap(t, i, n, camel(ws)))
                    break
                }
            }
            i += 1
        }
        return t
    }

    // MARK: Entry point

    /// Applies the corrections to whitespace tokens (punctuation attached). `explicitCaseCues` honors "camel case get user
    /// by id" anywhere (Code mode); otherwise only after naming words ("named", "called", "to", "as").
    public static func apply(_ tokens: [String], explicitCaseCues: Bool = false) -> [String] {
        var t = tokens
        var i = 0
        while i < t.count {
            if let (length, replacement) = match(t, at: i, explicitCaseCues: explicitCaseCues) {
                t.replaceSubrange(i..<i + length, with: replacement)
                i += replacement.count
            } else {
                i += 1
            }
        }
        return t
    }

    // MARK: Helpers

    typealias Match = (length: Int, replacement: [String])

    static func core(_ t: [String], _ i: Int) -> String { i >= 0 && i < t.count ? DeveloperFormatter.split(t[i]).1.lowercased() : "" }

    /// Words i..<i+n with punctuation only before the first and after the last.
    static func clean(_ t: [String], _ i: Int, _ n: Int) -> Bool {
        guard n > 0, i >= 0, i + n <= t.count else { return false }
        for k in i..<i + n {
            let (lead, c, trail) = DeveloperFormatter.split(t[k])
            if c.isEmpty || (k > i && !lead.isEmpty) || (k < i + n - 1 && !trail.isEmpty) { return false }
        }
        return true
    }

    /// Whether word i starts a clause (first token, or the previous token ends with sentence punctuation or a comma).
    static func startsClause(_ t: [String], _ i: Int) -> Bool {
        i == 0 || (DeveloperFormatter.split(t[i - 1]).2.last.map { ".!?,:;".contains($0) } ?? false)
    }

    static func wrap(_ t: [String], _ i: Int, _ n: Int, _ word: String) -> [String] {
        [DeveloperFormatter.split(t[i]).0 + word + DeveloperFormatter.split(t[i + n - 1]).2]
    }

    static func camel(_ words: [String]) -> String {
        words.enumerated().map { $0.offset == 0 ? $0.element.lowercased() : $0.element.lowercased().capitalizedFirst }.joined()
    }

    static func words(_ phrase: String) -> [String] { phrase.split(separator: " ").map(String.init) }

    // MARK: Rules

    static func match(_ t: [String], at i: Int, explicitCaseCues: Bool) -> Match? {
        kubectl(t, i) ?? git(t, i) ?? helm(t, i) ?? nginxConf(t, i) ?? reactHook(t, i) ?? eventHandler(t, i)
            ?? caseCue(t, i, anywhere: explicitCaseCues) ?? functionName(t, i) ?? envVar(t, i) ?? host(t, i)
    }

    /// "kube control get pods" → "kubectl get pods".
    static func kubectl(_ t: [String], _ i: Int) -> Match? {
        guard ["kube", "cube", "koob"].contains(core(t, i)), ["control", "ctl", "cuttle", "cuddle", "c-t-l"].contains(core(t, i + 1)),
              clean(t, i, 2), kubectlSubcommands.contains(core(t, i + 2)) else { return nil }
        return (2, wrap(t, i, 2, "kubectl"))
    }

    /// "gate rebase main" → "git rebase main", only where a command can start.
    static func git(_ t: [String], _ i: Int) -> Match? {
        guard core(t, i) == "gate", clean(t, i, 1), gitSubcommands.contains(core(t, i + 1)),
              startsClause(t, i) || commandLeadIns.contains(core(t, i - 1)) else { return nil }
        return (1, wrap(t, i, 1, "git"))
    }

    /// "help chart" → "Helm chart"; "help install --…" → "helm install --…".
    static func helm(_ t: [String], _ i: Int) -> Match? {
        guard core(t, i) == "help", clean(t, i, 1) else { return nil }
        if ["chart", "charts"].contains(core(t, i + 1)) { return (1, wrap(t, i, 1, "Helm")) }
        if ["install", "upgrade", "template", "uninstall", "rollback"].contains(core(t, i + 1)), i + 3 < t.count,
           t[(i + 2)...min(i + 4, t.count - 1)].contains(where: { $0.hasPrefix("--") }) {
            return (1, wrap(t, i, 1, "helm"))
        }
        return nil
    }

    /// "in nginx.com" / "the nginx.com file" → nginx.conf (a real domain elsewhere: "go to nginx.com" stays).
    static func nginxConf(_ t: [String], _ i: Int) -> Match? {
        guard core(t, i) == "nginx.com" else { return nil }
        let fileContext = ["in", "edit", "update", "change", "modify", "inside"].contains(core(t, i - 1))
            || (clean(t, i, 1) && ["file", "config", "configuration"].contains(core(t, i + 1)))
        return fileContext ? (1, wrap(t, i, 1, "nginx.conf")) : nil
    }

    /// "use effect hook" → "useEffect hook".
    static func reactHook(_ t: [String], _ i: Int) -> Match? {
        guard core(t, i) == "use" else { return nil }
        for n in [2, 1] {
            let name = (1...n).map { core(t, i + $0) }.joined(separator: " ")
            if let hook = reactHooks[name], clean(t, i, n + 1), hookNouns.contains(core(t, i + n + 1)) {
                return (n + 1, wrap(t, i, n + 1, hook))
            }
        }
        return nil
    }

    /// "on submit prop" → "onSubmit prop".
    static func eventHandler(_ t: [String], _ i: Int) -> Match? {
        guard core(t, i) == "on" else { return nil }
        for n in [2, 1] {
            let name = (1...n).map { core(t, i + $0) }
            if events.contains(name.joined(separator: " ")), clean(t, i, n + 1), handlerNouns.contains(core(t, i + n + 1)) {
                return (n + 1, wrap(t, i, n + 1, camel(["on"] + name)))
            }
        }
        return nil
    }

    /// "the refresh access token function" → "the refreshAccessToken function" (2–4 words starting with a verb).
    static func functionName(_ t: [String], _ i: Int) -> Match? {
        guard identifierVerbs.contains(core(t, i)), !identifierStops.contains(core(t, i - 1)) || ["the", "a", "an", "this", "call", "to"].contains(core(t, i - 1)) else { return nil }
        for n in stride(from: 4, through: 2, by: -1) where clean(t, i, n) && functionNouns.contains(core(t, i + n)) {
            let ws = (0..<n).map { core(t, i + $0) }
            guard ws.dropFirst().allSatisfy({ !identifierStops.contains($0) && $0.allSatisfy(\.isLetter) }) else { continue }
            return (n, wrap(t, i, n, camel(ws)))
        }
        return nil
    }

    /// "camel case get user by id" → "getUserById"; also snake, pascal, kebab, constant/screaming snake case.
    static func caseCue(_ t: [String], _ i: Int, anywhere: Bool) -> Match? {
        let cues: [([String], String)] = [(["camel", "case"], "camel"), (["camelcase"], "camel"), (["snake", "case"], "snake"),
                                          (["snake_case"], "snake"), (["pascal", "case"], "pascal"), (["pascalcase"], "pascal"),
                                          (["kebab", "case"], "kebab"), (["kebab-case"], "kebab"), (["constant", "case"], "constant"),
                                          (["screaming", "snake", "case"], "constant")]
        let naming = ["named", "called", "to", "as", "name", "call"].contains(core(t, i - 1))
            || (core(t, i - 1) == "it" && ["call", "name"].contains(core(t, i - 2)))
        guard anywhere || naming else { return nil }
        for (cue, style) in cues where (0..<cue.count).allSatisfy({ core(t, i + $0) == cue[$0] }) && clean(t, i, cue.count)
            && DeveloperFormatter.split(t[i + cue.count - 1]).2.isEmpty {
            var ws: [String] = []
            var k = i + cue.count
            while k < t.count, ws.count < 6 {
                let (lead, c, trail) = DeveloperFormatter.split(t[k])
                guard lead.isEmpty, !c.isEmpty, c.allSatisfy({ $0.isLetter || $0.isNumber }), !identifierStops.contains(c.lowercased()),
                      !symbolWords.contains(c.lowercased()) else { break }
                ws.append(c.lowercased())
                k += 1
                if !trail.isEmpty { break }
            }
            guard ws.count >= 2 else { return nil }
            // Outside Code mode the identifier must end the clause ("rename it to camel case get user by id."), so
            // "to camelCase enable strict mode in tsconfig.json" isn't read as a name.
            let endsClause = k == t.count || !DeveloperFormatter.split(t[k - 1]).2.isEmpty
            guard anywhere || endsClause else { return nil }
            let name: String
            switch style {
            case "snake": name = ws.joined(separator: "_")
            case "kebab": name = ws.joined(separator: "-")
            case "constant": name = ws.joined(separator: "_").uppercased()
            case "pascal": name = ws.map(\.capitalizedFirst).joined()
            default: name = camel(ws)
            }
            let consumed = k - i
            return (consumed, [DeveloperFormatter.split(t[i]).0 + name + DeveloperFormatter.split(t[k - 1]).2])
        }
        return nil
    }

    /// "database_url in the environment" → "DATABASE_URL in the environment".
    static func envVar(_ t: [String], _ i: Int) -> Match? {
        let (lead, c, trail) = DeveloperFormatter.split(t[i])
        guard c.contains("_"), c == c.lowercased(), c.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              c.first?.isLetter == true else { return nil }
        let after = (1...4).map { core(t, i + $0) }
        let before = [core(t, i - 2), core(t, i - 1)]
        let envAfter = [["environment", "variable"], ["env", "var"], ["env", "variable"], ["in", "the", "environment"],
                        ["in", ".env"], ["in", "the", ".env"], ["as", "an", "environment", "variable"], ["as", "an", "env", "var"]].contains { Array(after.prefix($0.count)) == $0 }
        let envBefore = before[1] == "export" || before == ["environment", "variable"] || before == ["env", "var"]
        guard (envAfter && trail.isEmpty) || envBefore || (envAfter && trail == ",") else { return nil }
        return (1, [lead + c.uppercased() + trail])
    }

    /// "example dot com" → "example.com"; "localhost colon 3000" → "localhost:3000".
    static func host(_ t: [String], _ i: Int) -> Match? {
        let word = core(t, i)
        if word == "localhost", core(t, i + 1) == "colon", clean(t, i, 3),
           DeveloperFormatter.split(t[i + 2]).1.allSatisfy(\.isNumber) {
            return (3, [DeveloperFormatter.split(t[i]).0 + "localhost:" + DeveloperFormatter.split(t[i + 2]).1 + DeveloperFormatter.split(t[i + 2]).2])
        }
        guard !word.isEmpty, word.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }), !identifierStops.contains(word),
              !RewriteGuard.functionWords.contains(word), core(t, i + 1) == "dot", domainSuffixes.contains(core(t, i + 2)),
              clean(t, i, 3),
              // Only where an address is expected ("on vercel dot com", "visit example dot io"), not "local host dot com event".
              startsClause(t, i) || ["on", "at", "to", "from", "visit", "open", "via", "see", "use", "into", "is", "and", "or"].contains(core(t, i - 1))
        else { return nil }
        return (3, wrap(t, i, 3, word + "." + core(t, i + 2)))
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
