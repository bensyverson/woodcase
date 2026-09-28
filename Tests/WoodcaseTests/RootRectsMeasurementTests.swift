//
//  RootRectsMeasurementTests.swift
//  WoodcaseTests
//

import Foundation
import Synchronization
import Testing
@testable import Woodcase

/// What ``RootOverlap/roots(in:textMeasurer:)`` lays out, and what it leaves alone.
///
/// A write asks where the roots are twice — before and after — to say whether it made
/// two artboards overlap. A root whose width and height are both fixed is exactly its
/// declared size wherever its children end up, so measuring it must not lay out a single
/// descendant; a root sized to its content has to be laid out, but alone. The text
/// measurer is the witness: every text a layout sizes goes through it.
@Suite("Root rects are measured without settling the document")
struct RootRectsMeasurementTests {
    /// A text measurer that counts its calls and answers a fixed size.
    final class CountingMeasurer: Sendable {
        private let calls = Mutex(0)

        /// How many texts have been measured.
        var count: Int {
            calls.withLock { $0 }
        }

        /// The measurer to hand the layout.
        var measurer: TextMeasurer {
            { [self] _, _, _, _, _, _, _, _ in
                calls.withLock { $0 += 1 }
                return (width: 40, height: 10)
            }
        }
    }

    @Test("a fixed-size root is measured without laying out its descendants")
    func fixedRootLaysOutNothing() throws {
        let document = try Self.document("""
        {"version": "2.10", "children": [
          {"type": "frame", "id": "Board", "x": 10, "y": 20, "width": 300, "height": 200,
           "layout": "vertical", "children": [
             {"type": "text", "id": "Lbl01", "content": "Hello"},
             {"type": "frame", "id": "Inner", "layout": "vertical", "children": [
               {"type": "text", "id": "Lbl02", "content": "World"}
             ]}
          ]}
        ]}
        """)
        let counter = CountingMeasurer()

        let roots = RootOverlap.roots(in: document, textMeasurer: counter.measurer)

        #expect(roots.map(\.id) == ["Board"])
        #expect(roots.first?.rect == PenRect(x: 10, y: 20, width: 300, height: 200))
        #expect(counter.count == 0, "a fixed-size root's texts were measured")
    }

    @Test("a fixed size bound to a variable resolves without a layout")
    func variableSizedRootResolves() throws {
        let document = try Self.document("""
        {"version": "2.10",
         "variables": {"board-width": {"type": "number", "value": 480}},
         "children": [
          {"type": "frame", "id": "Board", "width": "$board-width", "height": 200,
           "children": [{"type": "text", "id": "Lbl01", "content": "Hello"}]}
        ]}
        """)
        let counter = CountingMeasurer()

        let roots = RootOverlap.roots(in: document, textMeasurer: counter.measurer)

        #expect(roots.first?.rect == PenRect(x: 0, y: 0, width: 480, height: 200))
        #expect(counter.count == 0)
    }

    @Test("a content-sized root lays out its own subtree and no other root's")
    func contentSizedRootLaysOutAlone() throws {
        let document = try Self.document("""
        {"version": "2.10", "children": [
          {"type": "frame", "id": "Fixed", "width": 300, "height": 200, "layout": "vertical",
           "children": [{"type": "text", "id": "Lbl01", "content": "Not me"}]},
          {"type": "frame", "id": "Hug01", "x": 400, "layout": "vertical", "gap": 5,
           "children": [
             {"type": "text", "id": "Lbl02", "content": "One"},
             {"type": "text", "id": "Lbl03", "content": "Two"}
          ]}
        ]}
        """)
        let counter = CountingMeasurer()

        let roots = RootOverlap.roots(in: document, textMeasurer: counter.measurer)
        let settled = SettledTree(document: document, theme: [:], textMeasurer: CountingMeasurer().measurer)

        #expect(roots.map(\.id) == ["Fixed", "Hug01"])
        #expect(roots.last?.rect == PenRect(x: 400, y: 0, width: 40, height: 25))
        #expect(roots.last?.rect == settled.rects["Hug01"])
        #expect(counter.count == 2, "only the content-sized root's two texts should be measured")
    }

    @Test("a root that is a component instance is measured at the component's settled size")
    func instanceRootIsMeasured() throws {
        let document = try Self.document("""
        {"version": "2.10", "children": [
          {"type": "frame", "id": "Card1", "reusable": true, "width": 120, "height": 80},
          {"type": "ref", "id": "Inst1", "ref": "Card1", "x": 300, "y": 40}
        ]}
        """)

        let roots = RootOverlap.roots(in: document)

        #expect(roots.map(\.id) == ["Card1", "Inst1"])
        #expect(roots.last?.rect == PenRect(x: 300, y: 40, width: 120, height: 80))
    }

    /// Parses a document from JSON.
    private static func document(_ json: String) throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(json.utf8)))
    }
}
