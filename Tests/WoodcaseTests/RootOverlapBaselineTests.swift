//
//  RootOverlapBaselineTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A write's overlap check measures the roots twice — before the edit and after it — and
/// the second measurement typesets only the texts the edit changed.
///
/// ``RootOverlap/Baseline`` carries the ``TextSizeCache`` the first measurement filled
/// into the second, which is what makes that so; the pairs it holds are exactly
/// ``RootOverlap/pairs(in:)``'s.
@MainActor
struct RootOverlapBaselineTests {
    /// Two content-sized roots of two labels each, clear of one another.
    private func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data("""
        {"version": "2.10", "children": [
          {"type": "frame", "id": "Hug01", "layout": "vertical", "children": [
            {"type": "text", "id": "Lbl01", "content": "One"},
            {"type": "text", "id": "Lbl02", "content": "Two"}
          ]},
          {"type": "frame", "id": "Hug02", "x": 500, "layout": "vertical", "children": [
            {"type": "text", "id": "Lbl03", "content": "Three"},
            {"type": "text", "id": "Lbl04", "content": "Four"}
          ]}
        ]}
        """.utf8)))
    }

    @Test("the second measurement typesets only the text the edit changed")
    func theSecondMeasurementReusesSizes() throws {
        let document = try document()
        let counter = TextSizeCacheTests.RecordingMeasurer()
        let sizes = TextSizeCache(measuring: counter.measurer, fontGeneration: { 0 })

        let baseline = RootOverlap.baseline(in: document, textSizes: sizes)
        let before = counter.count
        #expect(before > 0)

        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Lbl03", properties: ["kind.content": .string("Three, and a much longer text")]
        )))
        _ = RootOverlap.introduced(since: baseline, in: document)
        let again = counter.count - before

        // What measuring the edited document from nothing costs, for comparison.
        let fresh = TextSizeCacheTests.RecordingMeasurer()
        _ = RootOverlap.baseline(
            in: document, textSizes: TextSizeCache(measuring: fresh.measurer, fontGeneration: { 0 })
        )
        #expect(again > 0, "the edited label was not measured")
        #expect(again < fresh.count, "the unchanged labels were typeset again")
    }

    @Test("a baseline holds the pairs, and reports the overlap a write introduced")
    func theBaselineFindsWhatAWriteIntroduced() throws {
        let document = try document()
        let baseline = RootOverlap.baseline(in: document)
        #expect(baseline.pairs == RootOverlap.pairs(in: document))

        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Hug02", properties: ["common.x": .double(0)]
        )))
        let introduced = RootOverlap.introduced(since: baseline, in: document)
        #expect(introduced.map(\.pair) == [RootOverlap.Pair("Hug01", "Hug02")])
    }
}
