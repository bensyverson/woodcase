//
//  JsTopicText.swift
//  WoodcaseCommandTests
//

import Foundation

/// The readings of `woodcase help js`' text that more than one suite needs.
///
/// `JsTopicTests` runs the topic's own snippets through the binary; `JsDeclarationTests`
/// parses its `declare const doc` block; `ScriptingArticleTests` does both against
/// `WoodcaseScripting.md`, which ships the same declaration and the same scripts. A
/// second copy of either reading is a second thing to keep true, so both live here.
enum JsTopicText {
    // MARK: - Snippets

    /// One script a topic or an article shows: which fixture it runs against, what to
    /// call the file, and its source.
    struct Snippet {
        /// The fixture the snippet's own first line names.
        let fixture: String

        /// The file name the snippet's own `-F` names, used for the file it is written to.
        let name: String

        /// The JavaScript, comment line included — it is a comment, so it runs.
        let source: String
    }

    /// One question shown as a shell pipeline.
    struct OneLiner {
        /// The fixture the command names.
        let fixture: String

        /// The script `echo` feeds to standard input.
        let stdin: String

        /// The command line, tokenized, with the leading `woodcase` dropped.
        let arguments: [String]
    }

    /// Pulls every script out of a topic's own text.
    ///
    /// A script is a block indented by four spaces whose first line is the comment naming
    /// the command that runs it — `// woodcase js batch.pen -F fan-out.js --as ana` — and
    /// it ends at the first line that is neither blank nor indented as far. The comment is
    /// part of the file that gets written, because a reader pasting the block should get
    /// the command with it.
    ///
    /// Markdown fences carry no indentation of their own, so an article's blocks are
    /// indented to this shape before they are passed in — see
    /// `ScriptingArticleTests.indentedFences(of:in:)`.
    ///
    /// - Parameter text: The topic body, verbatim.
    /// - Returns: Every script, in the order the text prints them.
    static func extractScripts(from text: String) -> [Snippet] {
        let lines = text.components(separatedBy: "\n")
        var snippets: [Snippet] = []
        var index = 0
        while index < lines.count {
            guard let match = lines[index]
                .firstMatch(of: /^ {4}\/\/ woodcase js (?<fixture>\S+\.pen) -F (?<name>\S+\.js)/)
            else {
                index += 1
                continue
            }
            var body: [String] = []
            while index < lines.count, belongs(lines[index]) {
                let line = lines[index]
                body.append(line.hasPrefix("    ") ? String(line.dropFirst(4)) : "")
                index += 1
            }
            snippets.append(Snippet(
                fixture: String(match.output.fixture),
                name: String(match.output.name),
                source: body.joined(separator: "\n") + "\n"
            ))
        }
        return snippets
    }

    /// Pulls every `echo … | woodcase …` one-liner out of a topic's own text.
    ///
    /// - Parameter text: The topic body, verbatim.
    /// - Returns: Every one-liner, in the order the text prints them.
    static func extractOneLiners(from text: String) -> [OneLiner] {
        text.components(separatedBy: "\n").compactMap { line in
            guard let match = line.firstMatch(
                of: /^ {4}\$ echo '(?<script>[^']*)' \| woodcase (?<command>.+)$/
            ) else { return nil }
            let arguments = String(match.output.command)
                .split(separator: " ")
                .map(String.init)
            guard let fixture = arguments.first(where: { $0.hasSuffix(".pen") }) else { return nil }
            return OneLiner(
                fixture: fixture,
                stdin: String(match.output.script),
                arguments: arguments
            )
        }
    }

    /// Whether a line is part of the snippet block that has begun: indented at least as
    /// far as the marker, or blank.
    private static func belongs(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("    ")
    }

    // MARK: - The declaration

    /// The line that opens the declaration of `doc`.
    static let docOpener = "declare const doc: {"

    /// The line that opens the declaration of the error every member throws — the last
    /// block of the declaration, and so the one that ends it.
    static let errorOpener = "declare class WoodcaseError extends Error {"

    /// The body of the block `opener` opens: every line between it and the line at its
    /// own indentation that reads `closer`.
    ///
    /// The indentation is what makes the boundary unambiguous — a namespace nested inside
    /// `doc` closes with the same `};` two levels in — and it is why the same reading
    /// works on the help topic, where the whole declaration is indented by six spaces,
    /// and on the article, where the fence puts it at column zero.
    ///
    /// - Parameters:
    ///   - lines: The text, split into lines.
    ///   - opener: What the opening line reads once trimmed.
    ///   - closer: What the closing line reads once trimmed.
    /// - Returns: The lines between the two, or empty when there is no such block.
    static func blockBody(
        in lines: [String],
        openedBy opener: String,
        closedBy closer: String = "};"
    ) -> ArraySlice<String> {
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == opener
        }) else { return [] }
        guard let end = closingIndex(after: start, in: lines, closer: closer) else {
            return lines[(start + 1)...]
        }
        return lines[(start + 1) ..< end]
    }

    /// The whole TypeScript declaration: `declare const doc` through the brace that closes
    /// `declare class WoodcaseError`, dedented by whatever indentation they share.
    ///
    /// The article ships this block verbatim inside a `typescript` fence, and
    /// `ScriptingArticleTests` holds the two to each other — so a member that changes
    /// shape breaks a test rather than teaching a call that throws.
    ///
    /// - Parameter text: A help topic body or an article, verbatim.
    /// - Returns: The declaration's lines, dedented and with trailing spaces removed.
    ///   Empty when the text carries no declaration.
    static func declaration(in text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == docOpener
        }) else { return [] }
        guard let errorStart = lines[start...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == errorOpener
        }) else { return [] }
        guard let end = closingIndex(after: errorStart, in: lines, closer: "}") else { return [] }
        return dedented(lines[start ... end])
    }

    /// The index of the first line after `index` that reads `closer` at the indentation
    /// of `lines[index]`.
    private static func closingIndex(
        after index: Int,
        in lines: [String],
        closer: String
    ) -> Int? {
        let indent = lines[index].prefix { $0 == " " }.count
        let wanted = String(repeating: " ", count: indent) + closer
        return lines[(index + 1)...].firstIndex { $0 == wanted }
    }

    /// The lines with the indentation every non-blank one shares removed, and trailing
    /// whitespace dropped — the only normalization the declaration comparison allows.
    private static func dedented(_ lines: ArraySlice<String>) -> [String] {
        let indent = lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix { $0 == " " }.count }
            .min() ?? 0
        return lines.map { line in
            let dropped = line.hasPrefix(String(repeating: " ", count: indent))
                ? String(line.dropFirst(indent))
                : line
            return String(dropped.reversed().drop { $0 == " " }.reversed())
        }
    }
}
