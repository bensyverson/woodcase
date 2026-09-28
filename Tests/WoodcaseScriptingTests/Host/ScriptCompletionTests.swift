//
//  ScriptCompletionTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// What comes back as ``ScriptRun/result``, and what happens when nothing can.
///
/// The rule the plan sets: never a silent `[object Object]`. A value that cannot cross
/// gets a `nil` result *and* a warning event saying which kind of value it was, so a
/// caller reading a transcript knows the run succeeded and the answer was lost, rather
/// than guessing.
@Suite("a script's completion value")
struct ScriptCompletionTests {
    /// Runs one expression over the fixture.
    private func result(of expression: String) throws -> ScriptRun {
        let document = try ScriptFixture.document("batch.pen")
        return ScriptHost.run([.text(expression, name: "<argv>")], over: document)
    }

    @Test("an object crosses as itself")
    func anObjectCrosses() throws {
        let run = try result(of: "({ rows: 2, names: ['a', 'b'] })")
        #expect(run.error == nil)
        #expect(run.result == .dictionary([
            "rows": .int(2),
            "names": .array([.string("a"), .string("b")]),
        ]))
        #expect(run.events.isEmpty)
    }

    @Test("an integer crosses as an integer, not as a double")
    func anIntegerStaysAnInteger() throws {
        #expect(try result(of: "10").result == .int(10))
    }

    @Test("a function yields no result and a warning naming it")
    func aFunctionCannotCross() throws {
        let run = try result(of: "(function named() {})")
        #expect(run.error == nil)
        #expect(run.result == nil)
        let warning = try #require(run.events.first)
        guard case let .warning(text) = warning else {
            Issue.record("expected a warning event, got \(warning)")
            return
        }
        #expect(text.contains("function"))
    }

    @Test("a Promise yields no result and a warning saying scripts are synchronous")
    func aPromiseCannotCross() throws {
        let run = try result(of: "Promise.resolve(1)")
        #expect(run.error == nil)
        #expect(run.result == nil)
        guard case let .warning(text) = try #require(run.events.first) else {
            Issue.record("expected a warning event")
            return
        }
        #expect(text.contains("Promise"))
        #expect(text.contains("no event loop"))
    }

    @Test("a cycle yields no result and a warning naming the cycle")
    func aCycleCannotCross() throws {
        let run = try result(of: "(() => { const a = {}; a.self = a; return a; })()")
        #expect(run.error == nil)
        #expect(run.result == nil)
        guard case let .warning(text) = try #require(run.events.first) else {
            Issue.record("expected a warning event")
            return
        }
        #expect(text.contains("cycle"))
    }

    @Test("a symbol yields no result and a warning")
    func aSymbolCannotCross() throws {
        let run = try result(of: "Symbol('x')")
        #expect(run.result == nil)
        guard case let .warning(text) = try #require(run.events.first) else {
            Issue.record("expected a warning event")
            return
        }
        #expect(text.contains("symbol"))
    }

    @Test("the completion value is the last source's, not the first's")
    func theLastSourceAnswers() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [.text("41", name: "first.js"), .text("42", name: "second.js")],
            over: document
        )
        #expect(run.result == .int(42))
    }
}
