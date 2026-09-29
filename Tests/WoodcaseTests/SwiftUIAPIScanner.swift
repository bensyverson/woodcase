//
//  SwiftUIAPIScanner.swift
//  WoodcaseTests
//

/// Reads emitted Swift for the names it uses that may be SDK APIs.
///
/// A lexer, not a parser: it knows comments, string literals, argument lists and a few
/// declaration keywords, and nothing about types. So it finds every name an emitted file
/// calls or reaches, with the labels of each call, but cannot say whose member a name is —
/// ``SwiftUIVocabulary`` matches a member by its name and labels, whatever its owner.
enum SwiftUIAPIScanner {
    /// Words that are never an API name when written bare.
    static let keywords: Set<String> = [
        "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue", "default",
        "defer", "didSet", "do", "else", "enum", "escaping", "extension", "fallthrough", "false", "fileprivate",
        "final", "for", "func", "get", "guard", "if", "import", "in", "indirect", "init", "inout", "internal",
        "is", "lazy", "let", "mutating", "nil", "nonisolated", "open", "operator", "private", "protocol",
        "public", "repeat", "rethrows", "return", "self", "Self", "set", "some", "any", "static", "struct",
        "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while",
        "willSet", "available", "unavailable",
    ]

    /// Words after which a capitalized name is a type in a declaration, not a call, even
    /// when a `{` follows it (`-> some View {`, `extension View {`, `: Shape {`).
    private static let typePositions: Set<String> = ["->", ":", ",", "&", "some", "any", "extension", "where"]

    /// Every use in `code` (the output of ``code(_:)``). With `callsOnly`, only calls: in a
    /// fragment of generated code, a name without its argument list is as likely a file name
    /// (`"\\(name).swift"`) or prose as an API.
    static func uses(in code: String, callsOnly: Bool = false) -> [SwiftUIAPIUse] {
        let chars = Array(code)
        var uses: [SwiftUIAPIUse] = []
        var index = 0
        while index < chars.count {
            let c = chars[index]
            guard isIdentifierHead(c), index == 0 || !isIdentifierBody(chars[index - 1]) else {
                index += 1
                continue
            }
            var end = index
            while end < chars.count, isIdentifierBody(chars[end]) {
                end += 1
            }
            defer { index = end }
            let name = String(chars[index ..< end])
            guard let access = access(chars, at: index) else { continue }
            // Swift allows no trailing closure in a condition, so there a `{` opens the body.
            let closures = !isControlLine(chars, at: index)
            if access == .bare {
                if keywords.contains(name) || isDeclared(chars, at: index) || isLabel(chars, after: end, name: name) {
                    continue
                }
                let isConstant = name.count > 2 && name.hasPrefix("k") && name.dropFirst().first!.isUppercase
                let isCalled = (end < chars.count && chars[end] == "(") || (closures && hasTrailingClosure(chars, after: end - 1))
                if !name.first!.isUppercase, !isConstant, !isCalled { continue }
            } else if name == "self" || name == "Type" || (access == .macro || access == .attribute) && !name.first!.isUppercase {
                // `\.self`, `T.Type`; `#available`, `@escaping`: the language's, not an API.
                continue
            }
            var use = SwiftUIAPIUse(name: name, access: access)
            if access == .qualified, index > 1, isIdentifierBody(chars[index - 2]) {
                use.receiver = previousToken(chars, before: index - 1)
            }
            if end < chars.count, chars[end] == "(" {
                let (labels, close) = arguments(chars, openingAt: end)
                use.labels = labels
                use.trailingClosures = closures && hasTrailingClosure(chars, after: close) ? 1 : 0
            } else if closures, hasTrailingClosure(chars, after: end - 1), !isTypePosition(chars, before: index, use: use) {
                use.labels = []
                use.trailingClosures = 1
            }
            if callsOnly, use.labels == nil { continue }
            uses.append(use)
        }
        return uses
    }

    // MARK: - Reading around a name

    /// How the name at `index` is reached, or `nil` when it is a number's fraction.
    private static func access(_ chars: [Character], at index: Int) -> SwiftUIAPIUse.Access? {
        guard index > 0 else { return .bare }
        switch chars[index - 1] {
        case "#": return .macro
        case "@": return .attribute
        case ".":
            guard index > 1 else { return .implicit }
            let before = chars[index - 2]
            if before.isNumber { return nil }
            if before == "\\" { return .keyPath }
            if isIdentifierBody(before) || ")]?!".contains(before) { return .qualified }
            // A modifier on its own line continues the chain above it.
            var previous = index - 2
            var crossedLine = false
            while previous >= 0, chars[previous].isWhitespace {
                crossedLine = crossedLine || chars[previous] == "\n"
                previous -= 1
            }
            let continues = previous >= 0 && (isIdentifierBody(chars[previous]) || ")]}".contains(chars[previous]))
            return crossedLine && continues ? .qualified : .implicit
        default: return .bare
        }
    }

    /// Whether the bare name at `index` is the one a declaration introduces (`func name`).
    private static func isDeclared(_ chars: [Character], at index: Int) -> Bool {
        let word = previousToken(chars, before: index)
        return ["func", "var", "let", "case", "struct", "enum", "class", "protocol", "typealias", "actor",
                "associatedtype"].contains(word)
    }

    /// Whether the bare name ending at `end` is an argument label or a parameter name
    /// (`radius: 4`, `size: CGFloat`), which a Core Text constant used as a dictionary key
    /// is not.
    private static func isLabel(_ chars: [Character], after end: Int, name: String) -> Bool {
        guard end < chars.count, chars[end] == ":", end + 1 >= chars.count || chars[end + 1] != ":" else {
            return false
        }
        return !(name.hasPrefix("kCT") || name.hasPrefix("kCG"))
    }

    /// Whether the line holding `index` is an `if`, `guard`, `for`, `while` or `switch`
    /// statement's head, `} else if` included.
    private static func isControlLine(_ chars: [Character], at index: Int) -> Bool {
        var start = index
        while start > 0, chars[start - 1] != "\n" {
            start -= 1
        }
        let line = String(chars[start ..< index]).drop { $0 == " " || $0 == "\t" || $0 == "}" }
            .drop { $0 == " " }
        return ["if ", "else if ", "guard ", "for ", "while ", "switch "].contains { line.hasPrefix($0) }
    }

    /// Whether a `{` follows `index` on the same line.
    private static func hasTrailingClosure(_ chars: [Character], after index: Int) -> Bool {
        var next = index + 1
        while next < chars.count, chars[next] == " " || chars[next] == "\t" {
            next += 1
        }
        return next < chars.count && chars[next] == "{"
    }

    /// Whether the capitalized bare name at `index` sits where a declaration names a type.
    private static func isTypePosition(_ chars: [Character], before index: Int, use: SwiftUIAPIUse) -> Bool {
        use.access == .bare && use.isCapitalized && typePositions.contains(previousToken(chars, before: index))
    }

    /// The word or punctuation before `index`, whitespace skipped: `func`, `->`, `:`.
    private static func previousToken(_ chars: [Character], before index: Int) -> String {
        var end = index
        while end > 0, chars[end - 1].isWhitespace {
            end -= 1
        }
        guard end > 0 else { return "" }
        if end > 1, chars[end - 2] == "-", chars[end - 1] == ">" { return "->" }
        guard isIdentifierBody(chars[end - 1]) else { return String(chars[end - 1]) }
        var start = end
        while start > 0, isIdentifierBody(chars[start - 1]) {
            start -= 1
        }
        return String(chars[start ..< end])
    }

    /// The labels of the argument list opening at `open` (`_` for an unlabeled argument),
    /// and the index of its closing parenthesis.
    static func arguments(_ chars: [Character], openingAt open: Int) -> (labels: [String], close: Int) {
        var depth = 0
        var segments: [String] = []
        var segment = ""
        var index = open
        while index < chars.count {
            let c = chars[index]
            if "([{".contains(c) {
                depth += 1
                if depth > 1 { segment.append(c) }
            } else if ")]}".contains(c) {
                depth -= 1
                if depth == 0 { break }
                segment.append(c)
            } else if c == ",", depth == 1 {
                segments.append(segment)
                segment = ""
            } else {
                segment.append(c)
            }
            index += 1
        }
        segments.append(segment)
        let labels: [String] = segments.compactMap { segment in
            let trimmed = segment.drop(while: \.isWhitespace)
            guard !trimmed.isEmpty else { return nil }
            let word = trimmed.prefix { isIdentifierBody($0) }
            let rest = trimmed.dropFirst(word.count).drop { $0 == " " }
            let isLabel = !word.isEmpty && isIdentifierHead(word.first!) && rest.first == ":" && !rest.dropFirst().hasPrefix(":")
            return isLabel ? String(word) : "_"
        }
        return (labels, index)
    }

    /// Whether `c` can start an identifier.
    static func isIdentifierHead(_ c: Character) -> Bool {
        c.isLetter || c == "_"
    }

    /// Whether `c` can continue an identifier.
    static func isIdentifierBody(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }
}
