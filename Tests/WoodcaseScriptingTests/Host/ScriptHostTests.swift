//
//  ScriptHostTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// The shape of a run: sources in one context, the timeline, the sink, and where it runs.
@Suite("the script host")
struct ScriptHostTests {
    @Test("a one-liner's completion value is the run's result")
    func aOneLinerAnswers() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run([.text("1 + 1", name: "<argv>")], over: document)
        #expect(run.error == nil)
        #expect(run.result == .int(2))
        #expect(run.commit == .unchanged)
        #expect(run.documentRevision == document.documentRevision)
    }

    @Test("a script that ends in a statement reports no result and no warning")
    func aStatementAnswersNothing() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run([.text("const answer = 1;", name: "<argv>")], over: document)
        #expect(run.error == nil)
        #expect(run.result == nil)
        #expect(run.events.isEmpty)
    }

    @Test("doc.rev is the document's own revision")
    func revIsLive() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run([.text("doc.rev", name: "<argv>")], over: document)
        #expect(run.result == .string(document.documentRevision))
    }

    // MARK: - One context

    @Test("a file source and a text source share one context")
    func sourcesShareOneContext() throws {
        let document = try ScriptFixture.document("batch.pen")
        let scratch = try ScriptFixture.file("const rows = doc.tree().length;", named: "helpers.js")
        let helpers = try #require(scratch.file)

        let run = ScriptHost.run(
            [.file(helpers), .text("rows", name: "<argv>")],
            over: document
        )
        #expect(run.error == nil)
        #expect(run.result == .int(9), "the second source should see the first's top-level const")
    }

    @Test("an error in the file source names that file")
    func anErrorInTheFirstSourceNamesIt() throws {
        let document = try ScriptFixture.document("batch.pen")
        let scratch = try ScriptFixture.file("throw new Error('from helpers');", named: "helpers.js")
        let helpers = try #require(scratch.file)

        let run = ScriptHost.run(
            [.file(helpers), .text("1", name: "<argv>")],
            over: document
        )
        let error = try #require(run.error)
        #expect(error.source == helpers.path)
        #expect(error.message.contains("from helpers"))
    }

    @Test("an error in the text source names the name it was given")
    func anErrorInTheTextSourceNamesIt() throws {
        let document = try ScriptFixture.document("batch.pen")
        let scratch = try ScriptFixture.file("const ok = 1;", named: "helpers.js")
        let helpers = try #require(scratch.file)

        let run = ScriptHost.run(
            [.file(helpers), .text("throw new Error('from argv');", name: "<argv>")],
            over: document
        )
        let error = try #require(run.error)
        #expect(error.source == "<argv>")
        #expect(error.message.contains("from argv"))
        #expect(run.commit == .rolledBack)
    }

    @Test("a source that cannot be read is refused by name")
    func anUnreadableSourceIsRefused() throws {
        let document = try ScriptFixture.document("batch.pen")
        let missing = ScriptFixture.url("no-such-script.js")
        let run = ScriptHost.run([.file(missing)], over: document)
        let error = try #require(run.error)
        #expect(error.code == ScriptErrorCode.sourceUnreadable)
        #expect(error.message.contains(missing.path))
    }

    // MARK: - The sink

    @Test("the sink sees every event, in the order the timeline records it")
    func theSinkSeesTheTimeline() throws {
        let document = try ScriptFixture.document("batch.pen")
        let collector = EventCollector()
        let run = ScriptHost.run(
            [.text(
                """
                console.log('one');
                console.warn('two');
                console.error('three');
                ({ done: true })
                """,
                name: "<argv>"
            )],
            over: document,
            sink: { collector.append($0) }
        )
        #expect(run.error == nil)
        #expect(run.events.count == 3)
        #expect(collector.events == run.events)
        #expect(run.events.first == .log(level: .log, text: "one"))
        #expect(run.events.last == .log(level: .error, text: "three"))
    }

    @Test("console joins arguments with spaces and renders objects as JSON")
    func consoleRendersLikeAModelExpects() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [.text("console.log('rows', 3, { a: 1 }, null, undefined)", name: "<argv>")],
            over: document
        )
        #expect(run.events == [.log(level: .log, text: #"rows 3 {"a":1} null undefined"#)])
    }

    @Test("console.info and console.debug report at the log level")
    func consoleHasTheAliasesAModelReachesFor() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [.text("console.info('a'); console.debug('b');", name: "<argv>")],
            over: document
        )
        #expect(run.events == [.log(level: .log, text: "a"), .log(level: .log, text: "b")])
    }

    // MARK: - Isolation

    /// An actor that is emphatically not the main actor, to run a script from.
    private actor Owner {
        /// Runs a script over a document this actor owns, and reports where it ran.
        ///
        /// - Parameter url: The .pen file to read.
        /// - Returns: The run, and whether the sink was called on the main thread.
        func run(_ url: URL) throws -> (result: AnyCodable?, onMain: Bool, events: [ScriptRun.Event]) {
            let document = try EditableDocument(from: PenParser.parse(contentsOf: url))
            var onMain = true
            var seen: [ScriptRun.Event] = []
            let run = ScriptHost.run(
                [.text("console.log('hello'); doc.tree().length", name: "<argv>")],
                over: document,
                sink: { event in
                    onMain = Thread.isMainThread
                    seen.append(event)
                }
            )
            return (run.result, onMain, seen)
        }
    }

    @Test("a run from a non-main actor works, and its sink runs there too")
    func aRunFromAnotherActorWorks() async throws {
        let outcome = try await Owner().run(ScriptFixture.url("batch.pen"))
        #expect(outcome.result == .int(9))
        #expect(outcome.onMain == false, "the run hopped to the main actor instead of staying put")
        #expect(outcome.events == [.log(level: .log, text: "hello")])
    }

    /// Collects the sink's events without needing a mutable capture.
    private final class EventCollector {
        /// What the sink was handed, in order.
        private(set) var events: [ScriptRun.Event] = []

        /// Records one event.
        ///
        /// - Parameter event: What the sink was handed.
        func append(_ event: ScriptRun.Event) {
            events.append(event)
        }
    }
}
