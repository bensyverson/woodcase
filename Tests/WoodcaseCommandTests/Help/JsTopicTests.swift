//
//  JsTopicTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `woodcase help js` must not rot: every program it shows has to still run.
///
/// The same bar `RecipesTests` holds the recipes topic to, one language over. Each
/// snippet is pulled straight out of ``HelpTopic/js``' own text, written to a file, and
/// run through the real binary against a fresh copy of the fixture its own first line
/// names — so a member that changes shape breaks this file's test rather than teaching a
/// call that throws.
///
/// Every snippet gets its own copy of the fixture, unlike the recipes' one scratch file:
/// a primer's snippets are things to paste on their own, not a sequence.
@Suite("`help js` stays runnable")
struct JsTopicTests {
    // MARK: - The snippets

    @Test("Every script in the js topic exits 0 against the fixture it names")
    func everyScriptExitsZero() throws {
        let scripts = JsTopicText.extractScripts(from: HelpTopic.js.body)
        #expect(scripts.count >= 3, "the js topic shows \(scripts.count) scripts")

        for script in scripts {
            let fixture = try CommandFixture(fixture: script.fixture)
            let path = fixture.root.appendingPathComponent(script.name)
            try Data(script.source.utf8).write(to: path)

            let run = try fixture.run("js", fixture.file.path, "-F", path.path, "--as", "ana")

            #expect(
                run.status == 0,
                "the \(script.name) snippet exited \(run.status): \(run.stderr)"
            )
        }
    }

    @Test("Every one-liner in the js topic exits 0, reading its script from standard input")
    func everyOneLinerExitsZero() throws {
        let oneLiners = JsTopicText.extractOneLiners(from: HelpTopic.js.body)
        #expect(!oneLiners.isEmpty, "the js topic shows no one-line question")

        for oneLiner in oneLiners {
            let fixture = try CommandFixture(fixture: oneLiner.fixture)
            let arguments = oneLiner.arguments.map {
                $0 == oneLiner.fixture ? fixture.file.path : $0
            }

            let run = try fixture.run(arguments, stdin: Data(oneLiner.stdin.utf8))

            #expect(
                run.status == 0,
                "`\(oneLiner.stdin)` exited \(run.status): \(run.stderr)"
            )
        }
    }

    // MARK: - The screen

    /// The topic's budget. Above the design primer's on purpose, and for the codegen
    /// topic's reason: this one carries a whole API's declaration, and there is no honest
    /// way to teach the transaction rules, the four worked shapes and the type of every
    /// member in a hundred and forty lines. It is still a budget — a section that will
    /// not fit belongs in `js --help` or in the sentence a refusal already prints.
    private static let topicLineBudget = 210

    @Test("`woodcase help js` needs no file, and fits one screen's width")
    func theTopicPrints() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("help", "js")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let lines = run.stdoutLines
        #expect(
            lines.count <= Self.topicLineBudget,
            "the js topic is \(lines.count) lines; the budget is \(Self.topicLineBudget)"
        )
        let widest = lines.map(\.count).max() ?? 0
        #expect(widest <= 100, "the js topic is \(widest) columns wide; one screen is 100")
    }

    @Test("The topic teaches the contract a script runs under")
    func theTopicTeachesTheContract() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("help", "js")
        let expectations: [(String, String)] = [
            ("one transaction", "Nothing is written until the script ends without an uncaught"),
            ("atomic calls", "a call that threw has"),
            ("settled reads", "READS SEE SETTLED LAYOUT"),
            ("no session", "Nothing persists between runs"),
            ("the repeated -F pattern", "-F helpers.js -F run.js"),
            ("shared top-level declarations", "Top-level const and let are shared"),
            ("no event loop", "There is no event loop"),
            ("when a verb is enough", "cp --each"),
            ("find as the question", "exits 1 when the answer is"),
            ("why find exits 2 and js exits 1", "the predicate IS the invocation"),
            ("the sentences the host throws", "doc.setProps"),
            ("the promise a rollback keeps", "is byte for byte what it was."),
            ("the declaration", "declare const doc: {"),
        ]
        for (rule, evidence) in expectations {
            #expect(run.stdout.contains(evidence), "the js topic does not teach \(rule)")
        }
    }
}
