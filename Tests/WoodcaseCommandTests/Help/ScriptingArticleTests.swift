//
//  ScriptingArticleTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `WoodcaseScripting.md` ships the same declaration and the same worked scripts as
/// `woodcase help js`, and must not drift from either.
///
/// The article is the long form of the topic: an agent reads one in a terminal and the
/// other on a documentation site, and a `.d.ts` that disagrees with the shipped one
/// teaches a call that throws. `JsDeclarationTests` holds the *topic's* declaration to
/// the running prelude; this suite holds the *article's* to the topic's, so the chain
/// runs from the prelude through the help text to the page, and a member that changes
/// shape breaks a test rather than a reader's script.
///
/// The scripts get `JsTopicTests`' treatment for the same reason: each one that names
/// its command in a leading comment is written to a file and run through the real binary
/// against a fresh copy of the fixture that comment names.
@Suite("The scripting article stays true")
struct ScriptingArticleTests {
    /// The article, read from the DocC catalog beside this file rather than from the
    /// working directory, so the test does not depend on where `swift test` was invoked.
    static let article: String = {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = packageRoot
            .appendingPathComponent(
                "Sources/Woodcase/Documentation.docc/WoodcaseScripting.md",
                isDirectory: false
            )
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    // MARK: - The declaration

    @Test("The article's TypeScript declaration is the one `woodcase help js` prints")
    func theDeclarationMatchesTheTopic() {
        let topic = JsTopicText.declaration(in: HelpTopic.js.body)
        #expect(!topic.isEmpty, "the js topic carries no declaration to compare against")

        let article = JsTopicText.declaration(in: Self.article)
        #expect(
            !article.isEmpty,
            "WoodcaseScripting.md carries no `\(JsTopicText.docOpener)` block"
        )
        #expect(
            article == topic,
            """
            the article's declaration has drifted from `woodcase help js`. \
            First difference: \(Self.firstDifference(article, topic))
            """
        )
    }

    // MARK: - The scripts

    @Test("Every script in the article exits 0 against the fixture it names")
    func everyScriptExitsZero() throws {
        let scripts = JsTopicText.extractScripts(from: Self.indentedFences(of: "javascript"))
        #expect(scripts.count >= 2, "the article shows \(scripts.count) runnable scripts")

        for script in scripts {
            let fixture = try CommandFixture(fixture: script.fixture)
            let path = fixture.root.appendingPathComponent(script.name)
            try Data(script.source.utf8).write(to: path)

            let run = try fixture.run("js", fixture.file.path, "-F", path.path, "--as", "ana")

            #expect(
                run.status == 0,
                "the \(script.name) block exited \(run.status): \(run.stderr)"
            )
        }
    }

    // MARK: - Reading the article

    /// Every fenced block of one language in the article, its lines indented by four
    /// spaces and the blocks separated by a line that is not.
    ///
    /// Markdown fences carry no indentation, and ``JsTopicText/extractScripts(from:)``
    /// reads the help topic's four-space blocks. Re-indenting is what lets one extractor
    /// read both, rather than a second one that could disagree with it; the separator is
    /// what ends a block, since a blank line does not.
    ///
    /// - Parameter language: The fence's info string, `javascript` or `bash`.
    /// - Returns: The blocks, in the order the article prints them.
    static func indentedFences(of language: String) -> String {
        var blocks: [String] = []
        var current: [String]?
        for line in Self.article.components(separatedBy: "\n") {
            if let body = current {
                if line.hasPrefix("```") {
                    blocks.append(body.map { $0.isEmpty ? "" : "    " + $0 }.joined(separator: "\n"))
                    current = nil
                } else {
                    current = body + [line]
                }
            } else if line.trimmingCharacters(in: .whitespaces) == "```" + language {
                current = []
            }
        }
        return blocks.joined(separator: "\n---\n")
    }

    /// The first line the two declarations disagree on, as a sentence for a failure.
    private static func firstDifference(_ article: [String], _ topic: [String]) -> String {
        for (index, line) in article.enumerated() {
            guard index < topic.count else { return "line \(index + 1): the article has \(line)" }
            if line != topic[index] {
                return "line \(index + 1): the article has \(line), the topic \(topic[index])"
            }
        }
        return article.count < topic.count
            ? "line \(article.count + 1): the topic has \(topic[article.count]) and the article ends"
            : "none — the two are equal"
    }
}
