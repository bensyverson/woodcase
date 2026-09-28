//
//  SettledTreeCacheTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// One settle per theme per run, an invalidation hook every write calls, and a read after
/// a write that lays out only the roots the write could have moved.
///
/// ``SettledTreeCache/settleCount`` counts trees built, whole or brought up to date;
/// ``SettledTreeCache/rootSettleCount`` counts the roots those settles laid out, which
/// is the number incremental settling exists to keep small. `SettledTreeReuseTests` and
/// `IncrementalSettleEquivalenceTests` hold the library's reuse rule to a settle from
/// nothing.
@Suite("the settled-tree cache")
struct SettledTreeCacheTests {
    @Test("a second read for the same theme settles nothing again")
    func oneSettlePerTheme() throws {
        let document = try ScriptFixture.document("batch.pen")
        let cache = SettledTreeCache()
        _ = cache.tree(for: [:], of: document)
        _ = cache.tree(for: [:], of: document)
        #expect(cache.settleCount == 1)
    }

    @Test("a different theme is its own tree")
    func themesAreKeptApart() throws {
        let document = try ScriptFixture.document("batch.pen")
        let cache = SettledTreeCache()
        _ = cache.tree(for: [:], of: document)
        _ = cache.tree(for: ["mode": "dark"], of: document)
        _ = cache.tree(for: ["mode": "dark"], of: document)
        #expect(cache.settleCount == 2)
    }

    @Test("axis order does not make a second tree")
    func theKeyIsOrderIndependent() throws {
        let document = try ScriptFixture.document("batch.pen")
        let cache = SettledTreeCache()
        _ = cache.tree(for: ["mode": "dark", "density": "tight"], of: document)
        _ = cache.tree(for: ["density": "tight", "mode": "dark"], of: document)
        #expect(cache.settleCount == 1)
    }

    @Test("invalidating drops every tree, so the next read settles again")
    func invalidationDropsEverything() throws {
        let document = try ScriptFixture.document("batch.pen")
        let cache = SettledTreeCache()
        _ = cache.tree(for: [:], of: document)
        cache.invalidate()
        _ = cache.tree(for: [:], of: document)
        #expect(cache.settleCount == 2)
    }

    @Test("two reads in one script settle the document once")
    func aScriptPaysOnce() throws {
        let document = try ScriptFixture.document("batch.pen")
        let runner = ScriptRunner(
            document: document,
            remedy: .batch,
            diagnostics: [],
            recorder: nil,
            deadline: nil,
            sink: nil
        )
        let run = runner.run([.text("doc.tree().length + doc.lint().length", name: "<argv>")])
        #expect(run.error == nil)
        #expect(runner.settled.settleCount == 1, "tree and lint should share one settled tree")
    }

    @Test("a script that only writes never settles the whole document")
    func writesAloneSettleNothing() throws {
        let document = try ScriptFixture.document("batch.pen")
        let runner = ScriptRunner(
            document: document,
            remedy: .batch,
            diagnostics: [],
            recorder: nil,
            deadline: nil,
            sink: nil
        )
        let run = runner.run([.text("doc.set('Ttl01', { 'kind.content': 'Hello' })", name: "<argv>")])
        #expect(run.error == nil)
        #expect(
            runner.settled.settleCount == 0,
            "the overlap baseline and check need the roots' rects, not a settled tree"
        )
    }

    // MARK: - Incremental settling

    /// A cache whose font set never moves, so a registration by a suite running in
    /// parallel cannot turn an exact count into a flake.
    private static func steadyCache() -> SettledTreeCache {
        SettledTreeCache(textSizes: TextSizeCache(fontGeneration: { 0 }))
    }

    /// A runner over `document` whose settles use `settled`.
    private static func runner(over document: EditableDocument, settled: SettledTreeCache) -> ScriptRunner {
        ScriptRunner(
            document: document,
            remedy: .batch,
            diagnostics: [],
            recorder: nil,
            deadline: nil,
            sink: nil,
            settled: settled
        )
    }

    @Test("a read after a write lays out only the root the write touched")
    func aWriteReSettlesItsRootAlone() throws {
        let document = try ScriptFixture.document("batch.pen")
        let runner = Self.runner(over: document, settled: Self.steadyCache())
        let run = runner.run([.text(
            """
            doc.tree();
            doc.set('Ttl01', { 'kind.content': 'A title long enough to measure again' });
            doc.tree().find(r => r.id === 'Ttl01').name;
            """,
            name: "<argv>"
        )])
        #expect(run.error == nil)
        // Cnv01, Brd01 and Cmp01 on the first read; Cnv01 alone after the write.
        #expect(runner.settled.rootSettleCount == 4)
    }

    @Test("a read after a write to a component re-lays out the roots that draw it")
    func aDefinitionWriteReSettlesItsInstances() throws {
        let document = try ScriptFixture.document("batch.pen")
        let cache = Self.steadyCache()
        _ = cache.tree(for: [:], of: document)
        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Lbl01", properties: ["kind.content": .string("A longer chip label")]
        )))
        cache.invalidate()
        let settled = cache.tree(for: [:], of: document)
        // Brd01 holds Chi01, an instance of Cmp01; Cnv01 draws no chip.
        #expect(settled.ledger?.laidOut == ["Brd01", "Cmp01"])
        #expect(cache.rootSettleCount == 5)
    }

    @Test("invalidating without a write lays out no root again")
    func invalidationWithoutAWriteReusesEverything() throws {
        let document = try ScriptFixture.document("batch.pen")
        let cache = Self.steadyCache()
        _ = cache.tree(for: [:], of: document)
        cache.invalidate()
        _ = cache.tree(for: [:], of: document)
        #expect(cache.rootSettleCount == 3)
    }

    @Test("every settle in a run measures a text once")
    func textSizesAreShared() throws {
        let document = try ScriptFixture.document("batch.pen")
        let cache = Self.steadyCache()
        _ = cache.tree(for: [:], of: document)
        let measured = cache.textSizes.measuredCount
        // Another theme settles every root again, over the same texts in the same fonts.
        _ = cache.tree(for: ["mode": "dark"], of: document)
        #expect(measured > 0)
        #expect(cache.textSizes.measuredCount == measured)
    }

    @Test("the run's overlap check measures its texts in the run's text sizes")
    func theOverlapCheckSharesTextSizes() throws {
        let document = try EditableDocument(from: PenParser.parse(Data("""
        {"version": "2.10", "children": [
          {"type": "frame", "id": "Hug01", "layout": "vertical",
           "children": [{"type": "text", "id": "Lbl01", "content": "Hello"}]},
          {"type": "frame", "id": "Fix01", "x": 400, "width": 100, "height": 100}
        ]}
        """.utf8)))
        let runner = Self.runner(over: document, settled: Self.steadyCache())
        // The check lays out the content-sized Hug01 at the start of the run and again
        // at its end; the second finds its label already measured.
        let run = runner.run([.text("doc.set('Fix01', { 'common.x': 900 })", name: "<argv>")])
        #expect(run.error == nil)
        #expect(runner.settled.textSizes.measuredCount == 1, "the check at the end measured the label again")
    }

    @Test("the runner's invalidation hook reaches the cache")
    func theRunnerExposesTheHook() throws {
        let document = try ScriptFixture.document("batch.pen")
        let runner = ScriptRunner(
            document: document,
            remedy: .batch,
            diagnostics: [],
            recorder: nil,
            deadline: nil,
            sink: nil
        )
        _ = runner.settled.tree(for: [:], of: document)
        runner.invalidate()
        _ = runner.settled.tree(for: [:], of: document)
        #expect(runner.settled.settleCount == 2)
    }
}
