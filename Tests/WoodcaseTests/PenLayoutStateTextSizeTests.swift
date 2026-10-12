//
//  PenLayoutStateTextSizeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A ``PenLayoutState`` owns a bounded ``TextSizeCache`` (design decision 4, leaf
/// `df281f`): a text it has typeset is not typeset again for the same request, and a
/// font registration lays the document out afresh, since every size remembered before
/// it may be wrong.
@MainActor
struct PenLayoutStateTextSizeTests {
    private func resolved(_ document: EditableDocument) -> PenDocument {
        PenVariableResolver.resolve(document.expandedDocument().0)
    }

    private func makeDocument() throws -> EditableDocument {
        let document = try EditableDocument(from: PenParser.parse(PenLayoutStateTests.json))
        document.primeLayoutCache(with: [:])
        return document
    }

    @Test("A full re-layout typesets no text it has typeset before")
    func fullRelayoutAnswersFromTheTextCache() throws {
        let document = try makeDocument()
        let counter = TextSizeCacheTests.RecordingMeasurer()
        var state = PenLayoutState(document: resolved(document), textMeasurer: counter.measurer)
        let first = counter.count
        #expect(first > 0)

        let change = state.update(to: resolved(document), invalidation: PenLayoutInvalidation(everything: true))
        #expect(counter.count == first)
        #expect(change.isEmpty)
        #expect(state.textSizes.count > 0)
    }

    @Test("A font registration lays everything out again, even with nothing dirty")
    func fontRegistrationLaysOutAfresh() throws {
        let document = try makeDocument()
        let counter = TextSizeCacheTests.RecordingMeasurer()
        let generation = TextSizeCacheTests.Generation()
        let sizes = TextSizeCache(measuring: counter.measurer, fontGeneration: { generation.current })
        var state = PenLayoutState(document: resolved(document), textSizes: sizes)
        let first = counter.count

        generation.advance()
        let change = state.update(to: resolved(document), invalidation: PenLayoutInvalidation())
        #expect(counter.count == 2 * first)
        #expect(change.affectedRoots == ["B", "Other"])
    }

    @Test("Without a font registration, nothing dirty lays nothing out")
    func noRegistrationNoWork() throws {
        let document = try makeDocument()
        let counter = TextSizeCacheTests.RecordingMeasurer()
        let generation = TextSizeCacheTests.Generation()
        let sizes = TextSizeCache(measuring: counter.measurer, fontGeneration: { generation.current })
        var state = PenLayoutState(document: resolved(document), textSizes: sizes)

        let change = state.update(to: resolved(document), invalidation: PenLayoutInvalidation())
        #expect(change.affectedRoots.isEmpty)
        #expect(change.stats.containersLaidOut.isEmpty)
    }
}
