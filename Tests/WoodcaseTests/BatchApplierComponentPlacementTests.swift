//
//  BatchApplierComponentPlacementTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A component definition is a root like any other: it sits on the canvas, it is drawn
/// there, and two of them at the same coordinates hide each other. So auto-placement
/// and the overlap check both have to see it — the expansion under
/// ``EditableDocument/computeLayout(textMeasurer:)`` strips reusable definitions, which
/// left every added component at the origin and every collision unreported.
@MainActor
@Suite("placing component definitions at the root")
struct BatchApplierComponentPlacementTests {
    /// A named frame of a fixed size, reusable or not, at the coordinates given.
    private func frame(
        id: String,
        name: String,
        reusable: Bool,
        x: Double? = nil,
        y: Double? = nil
    ) -> PenNode {
        var common = PenNodeCommon(name: name)
        common.reusable = reusable ? true : nil
        common.x = x.map { .literal($0) }
        common.y = y.map { .literal($0) }
        return PenNode(
            id: id,
            common: common,
            kind: .frame(PenNode.FrameData(width: .fixed(200), height: .fixed(100)))
        )
    }

    /// The `x` a root settled at, or `nil` when the document has no such node.
    private func x(of id: String, in document: EditableDocument) -> Double? {
        guard case let .literal(value)? = document.nodes[id]?.common.x else { return nil }
        return value
    }

    // MARK: - Placement

    @Test("A component added at the root is placed clear of an existing component")
    func componentIsPlacedClearOfAComponent() {
        let document = EditableDocument(from: PenDocument(children: [
            frame(id: "cmp01", name: "First", reusable: true, x: 0, y: 0),
        ]))

        let report = BatchApplier.apply([
            .add(BatchOperation.AddOp(node: frame(id: "cmp02", name: "Second", reusable: true))),
        ], to: document)

        #expect(report.lines.allSatisfy { $0.status == .applied })
        #expect(x(of: "cmp02", in: document) == 300)
    }

    @Test("Every component in a batch of adds lands clear of the ones before it")
    func aBatchOfComponentsFansOut() {
        let document = EditableDocument(from: PenDocument(children: [
            frame(id: "art01", name: "Artboard", reusable: false, x: 0, y: 0),
        ]))

        let report = BatchApplier.apply([
            .add(BatchOperation.AddOp(node: frame(id: "cmp01", name: "One", reusable: true))),
            .add(BatchOperation.AddOp(node: frame(id: "cmp02", name: "Two", reusable: true))),
            .add(BatchOperation.AddOp(node: frame(id: "cmp03", name: "Three", reusable: true))),
        ], to: document)

        #expect(report.lines.allSatisfy { $0.status == .applied })
        #expect(x(of: "cmp01", in: document) == 300)
        #expect(x(of: "cmp02", in: document) == 600)
        #expect(x(of: "cmp03", in: document) == 900)
    }

    @Test("An ordinary artboard is placed clear of a component, not on top of it")
    func artboardIsPlacedClearOfAComponent() {
        let document = EditableDocument(from: PenDocument(children: [
            frame(id: "cmp01", name: "Kit", reusable: true, x: 0, y: 0),
        ]))

        let report = BatchApplier.apply([
            .add(BatchOperation.AddOp(node: frame(id: "art01", name: "Home", reusable: false))),
        ], to: document)

        #expect(report.lines.allSatisfy { $0.status == .applied })
        #expect(x(of: "art01", in: document) == 300)
    }

    // MARK: - The overlap check

    @Test("Two components sitting on each other are reported as an overlap")
    func overlappingComponentsAreFound() {
        let document = EditableDocument(from: PenDocument(children: [
            frame(id: "cmp01", name: "First", reusable: true, x: 0, y: 0),
            frame(id: "cmp02", name: "Second", reusable: true, x: 50, y: 0),
        ]))

        let overlaps = RootOverlap.overlaps(in: document)

        #expect(overlaps.count == 1)
        #expect(overlaps.first?.earlier.id == "cmp01")
        #expect(overlaps.first?.later.id == "cmp02")
    }

    @Test("Components laid clear of each other are not reported")
    func separatedComponentsAreClean() {
        let document = EditableDocument(from: PenDocument(children: [
            frame(id: "cmp01", name: "First", reusable: true, x: 0, y: 0),
            frame(id: "cmp02", name: "Second", reusable: true, x: 300, y: 0),
        ]))

        #expect(RootOverlap.overlaps(in: document).isEmpty)
    }
}
