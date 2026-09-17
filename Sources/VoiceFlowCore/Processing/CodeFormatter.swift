/// Code mode (Phase 9): text for terminals and editors. Spoken symbols become symbols ("open paren", "equals", "dash rf"),
/// explicit case cues become identifiers ("camel case get user by id" → getUserById), and there is no sentence
/// capitalization or final period. Nothing is removed except hesitations and stutters; unknown words stay as spoken.
public enum CodeFormatter {
    struct Piece { var text: String; var glueLeft = false; var glueRight = false }

    enum Kind { case glueBoth, attachLeft, attachRight, spaced, quote, openCall }

    /// Commands after which a path starts with a space ("cd ../src", "ls /tmp").
    static let pathCommands: Set<String> = ["cd", "ls", "cat", "rm", "mv", "cp", "mkdir", "touch", "open", "code", "vim", "nano",
                                            "less", "tail", "head", "chmod", "chown", "source", "echo", "curl", "wget", "find",
                                            "grep", "tree", "du", "stat", "add", "import", "from", "require", "include"]
    /// Words after which "(" or "[" keeps a space ("if (", "return [").
    static let spacedBeforeParen: Set<String> = ["if", "for", "while", "switch", "return", "await", "catch", "and", "or", "not",
                                                 "in", "of", "else", "with", "as", "yield", "typeof", "new"]

    static let symbols: [([String], String, Kind)] = [
        (["triple", "equals"], "===", .spaced), (["double", "equals"], "==", .spaced), (["not", "equals"], "!=", .spaced),
        (["fat", "arrow"], "=>", .spaced), (["arrow", "function"], "=>", .spaced), (["equals", "sign"], "=", .spaced),
        (["equal", "sign"], "=", .spaced), (["equals"], "=", .spaced),
        (["plus", "sign"], "+", .spaced), (["minus", "sign"], "-", .spaced), (["asterisk"], "*", .spaced),
        (["greater", "than"], ">", .spaced), (["less", "than"], "<", .spaced), (["double", "pipe"], "||", .spaced),
        (["pipe"], "|", .spaced), (["double", "ampersand"], "&&", .spaced), (["ampersand"], "&", .spaced),
        (["open", "parenthesis"], "(", .openCall), (["open", "paren"], "(", .openCall), (["left", "paren"], "(", .openCall),
        (["close", "parenthesis"], ")", .attachLeft), (["close", "paren"], ")", .attachLeft), (["right", "paren"], ")", .attachLeft),
        (["open", "bracket"], "[", .openCall), (["close", "bracket"], "]", .attachLeft),
        (["open", "curly", "brace"], "{", .attachRight), (["open", "curly"], "{", .attachRight), (["open", "brace"], "{", .attachRight),
        (["close", "curly", "brace"], "}", .attachLeft), (["close", "curly"], "}", .attachLeft), (["close", "brace"], "}", .attachLeft),
        (["comma"], ",", .attachLeft), (["semicolon"], ";", .attachLeft), (["colon"], ":", .attachLeft),
        (["at", "sign"], "@", .attachRight), (["hash", "sign"], "#", .attachRight), (["pound", "sign"], "#", .attachRight),
        (["dollar", "sign"], "$", .attachRight), (["tilde"], "~", .attachRight), (["exclamation", "mark"], "!", .attachRight),
        (["backslash"], "\\", .glueBoth), (["forward", "slash"], "/", .glueBoth), (["slash"], "/", .glueBoth),
        (["dot", "dot"], "..", .glueBoth), (["dot"], ".", .glueBoth), (["underscore"], "_", .glueBoth),
        (["double", "quote"], "\"", .quote), (["quote"], "\"", .quote), (["single", "quote"], "'", .quote),
        (["backtick"], "`", .quote),
    ]

    public static func format(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { formatLine(String($0)) }.joined(separator: "\n")
    }

    static func formatLine(_ line: String) -> String {
        var tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return line }
        // Undo sentence styling from speech recognition: a final period, and a capitalized plain first word ("Git status.").
        if let last = tokens.last, last.hasSuffix("."), !last.hasSuffix("..") { tokens[tokens.count - 1] = String(last.dropLast()) }
        let (lead, first, trail) = DeveloperFormatter.split(tokens[0])
        if first.count > 1, first.first!.isUppercase, first.dropFirst().allSatisfy({ $0.isLowercase }),
           DeveloperFormatter.canonicalTerms[first.lowercased()] == nil {
            tokens[0] = lead + first.lowercased() + trail
        }
        tokens = DeveloperFormatter.applySpokenNames(tokens)
        tokens = DeveloperCorrections.apply(tokens, explicitCaseCues: true)
        return render(pieces(tokens))
    }

    static func pieces(_ t: [String]) -> [Piece] {
        var out: [Piece] = []
        var openQuotes: Set<String> = []
        var i = 0
        func plain(_ k: Int) -> String? {
            guard k < t.count else { return nil }
            let (lead, c, trail) = DeveloperFormatter.split(t[k])
            return lead.isEmpty && trail.isEmpty && !c.isEmpty ? c.lowercased() : nil
        }
        outer: while i < t.count {
            // "dash dash force" → "--force"; "dash rf" → "-rf" after a command word; "my dash app" → "my-app".
            if plain(i) == "dash" || plain(i) == "hyphen" {
                if plain(i + 1) == "dash" || plain(i + 1) == "hyphen" {
                    out.append(Piece(text: "--", glueRight: true)); i += 2; continue
                }
                let next = i + 1 < t.count ? DeveloperFormatter.split(t[i + 1]).1 : ""
                if !next.isEmpty, next.count <= 3, next.allSatisfy(\.isLetter) {
                    out.append(Piece(text: "-", glueRight: true))
                } else {
                    out.append(Piece(text: "-", glueLeft: !out.isEmpty, glueRight: true))
                }
                i += 1; continue
            }
            for (words, symbol, kind) in symbols where (0..<words.count).allSatisfy({ plain(i + $0) == words[$0] }) {
                switch kind {
                case .glueBoth:
                    let afterCommand = out.last.map { !$0.glueRight && pathCommands.contains($0.text.lowercased()) } ?? true
                    out.append(Piece(text: symbol, glueLeft: !afterCommand, glueRight: true))
                case .openCall:
                    let afterWord = out.last.map { piece in
                        !piece.glueRight && piece.text.last.map { $0.isLetter || $0.isNumber || $0 == ")" || $0 == "]" } == true
                            && !spacedBeforeParen.contains(piece.text.lowercased())
                    } ?? false
                    out.append(Piece(text: symbol, glueLeft: afterWord, glueRight: true))
                case .attachLeft: out.append(Piece(text: symbol, glueLeft: true))
                case .attachRight: out.append(Piece(text: symbol, glueRight: true))
                case .spaced: out.append(Piece(text: symbol))
                case .quote:
                    if openQuotes.remove(symbol) != nil { out.append(Piece(text: symbol, glueLeft: true)) }
                    else { openQuotes.insert(symbol); out.append(Piece(text: symbol, glueRight: true)) }
                }
                i += words.count
                continue outer
            }
            out.append(Piece(text: t[i]))
            i += 1
        }
        return out
    }

    static func render(_ pieces: [Piece]) -> String {
        var result = ""
        for (index, piece) in pieces.enumerated() {
            if index > 0, !pieces[index - 1].glueRight, !piece.glueLeft { result += " " }
            result += piece.text
        }
        return result
    }
}
