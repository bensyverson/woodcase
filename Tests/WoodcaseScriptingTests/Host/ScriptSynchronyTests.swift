//
//  ScriptSynchronyTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// There is no event loop, and the script is told so in one sentence.
///
/// `setTimeout`, `fetch` and `require` are the mistakes a model makes on day one.
/// Undefined, each is a bare `TypeError` naming nothing; defined to throw, each teaches
/// the same fact once.
@Suite("scripts are synchronous")
struct ScriptSynchronyTests {
    /// Runs one expression and returns the failure it produced.
    private func failure(of expression: String) throws -> ScriptError {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run([.text(expression, name: "<argv>")], over: document)
        return try #require(run.error, "\(expression) should have thrown")
    }

    @Test(
        "setTimeout, setInterval, fetch and require each say a script runs in one pass",
        arguments: [
            "setTimeout(() => {}, 10)",
            "setInterval(() => {}, 10)",
            "fetch('https://example.com')",
            "require('fs')",
        ]
    )
    func theGuardsShareOneSentence(expression: String) throws {
        let error = try failure(of: expression)
        #expect(error.code == ScriptErrorCode.synchronousOnly)
        #expect(
            error.message.contains("runs to completion in one pass, with no event loop"),
            "got: \(error.message)"
        )
    }

    @Test("require points at the repeated -F pattern instead of modules")
    func requirePointsAtTheAlternative() throws {
        #expect(try failure(of: "require('./helpers')").message.contains("-F helpers.js -F run.js"))
    }

    @Test("a top-level import is refused with the sentence, not a bare syntax error")
    func aTopLevelImportIsRefusedWithASentence() throws {
        let error = try failure(of: "import fs from 'fs';\ndoc.rev")
        #expect(error.code == ScriptErrorCode.synchronousOnly)
        #expect(error.message.contains("is not a module"))
        #expect(error.message.contains("-F helpers.js -F run.js"))
    }

    @Test("a plain syntax error keeps its own message and its line")
    func aSyntaxErrorIsLocated() throws {
        let error = try failure(of: "const x = 1;\nconst y = (;\n")
        #expect(error.code == ScriptErrorCode.syntaxError)
        #expect(error.line == 2)
        #expect(error.sourceLine == "const y = (;")
    }

    // MARK: - Per-source locations

    @Test("an error in the second of two sources reports that source's name and line")
    func theSecondSourceReportsItsOwnLine() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [
                .text("const a = 1;\nconst b = 2;\nconst c = 3;\n", name: "helpers.js"),
                .text("const d = 4;\nthrow new Error('here');\n", name: "run.js"),
            ],
            over: document
        )
        let error = try #require(run.error)
        #expect(error.source == "run.js")
        #expect(error.line == 2, "the line should be the second source's, not the concatenation's")
        #expect(error.sourceLine == "throw new Error('here');")
    }

    @Test("a throw from a helper called by a later source quotes the helper's line")
    func aThrowInsideAHelperQuotesTheHelper() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [
                .text("function boom() {\n  throw new Error('inside');\n}\n", name: "helpers.js"),
                .text("boom();\n", name: "run.js"),
            ],
            over: document
        )
        let error = try #require(run.error)
        #expect(error.source == "helpers.js")
        #expect(error.line == 2)
        #expect(error.sourceLine == "  throw new Error('inside');")
    }

    @Test("a refusal raised inside the prelude reports no line, rather than the prelude's")
    func apreludeRefusalIsNotLocatedInTheScript() throws {
        let error = try failure(of: "doc.setProps('a', {})")

        #expect(error.code == ScriptErrorCode.unknownMember)
        #expect(error.source == "<argv>")
        // The throw happened in the prelude, whose lines are not the script's: a one-line
        // source located at line 19 sends a reader to a line that does not exist.
        #expect(error.line == nil)
        #expect(error.column == nil)
        #expect(error.sourceLine == nil)
    }

    @Test("an uncaught error reports its line, column and the source line")
    func anUncaughtErrorIsFullyLocated() throws {
        let error = try failure(of: "const a = 1;\nconst b = a.missing.deeper;\n")
        #expect(error.line == 2)
        #expect(try #require(error.column) > 0)
        #expect(error.sourceLine == "const b = a.missing.deeper;")
        #expect(error.code == ScriptErrorCode.scriptError)
    }
}
