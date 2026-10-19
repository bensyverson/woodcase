//
//  ScaleGeometryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Where a proportional scale puts things (``ScaleCapture``): each member's position is
/// scaled about the anchor in its parent's own coordinates, so every node of the selection
/// is drawn as its old quad scaled about the anchor on the canvas — under turned and flipped
/// parents too — and a member a stack places only grows in its slot.
@MainActor
struct ScaleGeometryTests {
    @Test("Each of the nine anchors stays put while the box scales about it", arguments: ScaleAnchor.allCases)
    func anchors(anchor: ScaleAnchor) throws {
        let document = try ScaleFixture.document()
        let box = PenRect(x: 400, y: 300, width: 50, height: 30)
        let pivot = anchor.point(in: box)
        try ScaleFixture.scale(["Dashed"], by: 2, anchor: anchor, in: document)

        #expect(try ScaleFixture.value("common.x", of: "Dashed", in: document) == AnyCodable.number(pivot.x + 2 * (400 - pivot.x)))
        #expect(try ScaleFixture.value("common.y", of: "Dashed", in: document) == AnyCodable.number(pivot.y + 2 * (300 - pivot.y)))
    }

    @Test("The nine anchors are the box's corners, edge midpoints and center")
    func anchorPoints() {
        let box = PenRect(x: 10, y: 20, width: 100, height: 50)
        #expect(ScaleAnchor.topLeft.point(in: box) == PenPoint(x: 10, y: 20))
        #expect(ScaleAnchor.top.point(in: box) == PenPoint(x: 60, y: 20))
        #expect(ScaleAnchor.topRight.point(in: box) == PenPoint(x: 110, y: 20))
        #expect(ScaleAnchor.left.point(in: box) == PenPoint(x: 10, y: 45))
        #expect(ScaleAnchor.center.point(in: box) == PenPoint(x: 60, y: 45))
        #expect(ScaleAnchor.right.point(in: box) == PenPoint(x: 110, y: 45))
        #expect(ScaleAnchor.bottomLeft.point(in: box) == PenPoint(x: 10, y: 70))
        #expect(ScaleAnchor.bottom.point(in: box) == PenPoint(x: 60, y: 70))
        #expect(ScaleAnchor.bottomRight.point(in: box) == PenPoint(x: 110, y: 70))
    }

    @Test("The capture's bounds are the members' union on the canvas")
    func bounds() throws {
        let document = try ScaleFixture.document()
        let capture = try ScaleCapture(
            nodeIDs: ["Dashed", "Wave"], in: document, layout: ScaleFixture.layout(of: document)
        )
        #expect(capture.bounds == PenRect(x: 400, y: 100, width: 110, height: 230))
    }

    @Test("A turned, flipped group and its turned, flipped children are drawn scaled about the anchor", arguments: [0.5, 2.5])
    func turnedGroup(factor: Double) throws {
        let document = try ScaleFixture.document()
        let before = ["T1", "T2", "T3"].map { ScaleFixture.corners(ofExpanded: $0, in: document) }
        let anchor = PenPoint(x: 640, y: 260)
        let capture = try ScaleCapture(nodeIDs: ["Turned"], in: document, layout: ScaleFixture.layout(of: document))
        for operation in try capture.plan(factor: factor, around: anchor, in: document).operations {
            try document.apply(operation)
        }
        let after = ["T1", "T2", "T3"].map { ScaleFixture.corners(ofExpanded: $0, in: document) }

        for (old, new) in zip(before, after) {
            #expect(ScaleFixture.isScaled(old, to: new, by: factor, about: anchor), "\(String(describing: old)) → \(String(describing: new))")
        }
        #expect(document.node(id: "T2")?.common.rotation == .literal(-20))
        #expect(document.node(id: "Turned")?.common.rotation == .literal(30))
    }

    @Test("A member inside a turned group is scaled about the anchor on the canvas, not in the group")
    func memberUnderTurnedParent() throws {
        let document = try ScaleFixture.document()
        let before = ScaleFixture.corners(ofExpanded: "T3", in: document)
        let anchor = PenPoint(x: 600, y: 200)
        let capture = try ScaleCapture(nodeIDs: ["T3"], in: document, layout: ScaleFixture.layout(of: document))
        for operation in try capture.plan(factor: 2, around: anchor, in: document).operations {
            try document.apply(operation)
        }
        #expect(ScaleFixture.isScaled(before, to: ScaleFixture.corners(ofExpanded: "T3", in: document), by: 2, about: anchor))
    }

    @Test("A member its stack places grows in its slot and writes no position")
    func inFlowMember() throws {
        let document = try ScaleFixture.document()
        let plan = try ScaleFixture.plan(["Body"], by: 2, anchor: .center, in: document)

        let written = plan.operations.flatMap { operation -> [String] in
            guard case let .setProperties(set) = operation else { return [] }
            return Array(set.properties.keys)
        }
        #expect(!written.contains("common.x") && !written.contains("common.y"))
        #expect(written.contains("kind.width"))
    }

    @Test("A member inside another member is scaled once, as part of it")
    func topMostMembers() throws {
        let document = try ScaleFixture.document()
        try ScaleFixture.scale(["Title", "Card"], by: 2, in: document)

        #expect(try ScaleFixture.value("kind.fontSize", of: "Title", in: document) == 40)
    }

    @Test("Planning again from the capture never compounds: the last factor is all that counts")
    func repeatedPlansFromTheStart() throws {
        let document = try ScaleFixture.document()
        let ids = ["Card", "Turned", "Chip", "Sticky", "Dashed"]
        let capture = try ScaleCapture(nodeIDs: ids, in: document, layout: ScaleFixture.layout(of: document))
        for factor in [1.1, 1.4, 0.7, 1.9] {
            _ = try capture.plan(factor: factor, anchor: .center, in: document)
        }
        let last = try capture.plan(factor: 2, anchor: .center, in: document)
        let once = try ScaleFixture.plan(ids, by: 2, anchor: .center, in: document)

        #expect(last == once)
        #expect(!last.operations.isEmpty)
    }

    @Test("The one-off planner plans what a capture plans")
    func oneOff() throws {
        let document = try ScaleFixture.document()
        let ids = ["Card", "Chip"]
        let plan = try EditPlanner.planScale(
            nodeIDs: ids, by: 0.75, anchor: .bottomRight, in: document, layout: ScaleFixture.layout(of: document)
        )

        #expect(try plan == (ScaleFixture.plan(ids, by: 0.75, anchor: .bottomRight, in: document)))
        #expect(!plan.operations.isEmpty)
    }

    @Test("Previewing a step shows what committing it would store")
    func preview() throws {
        let document = try ScaleFixture.document()
        let ids = ["Card", "Turned", "Chip", "Sticky"]
        let plan = try ScaleFixture.plan(ids, by: 1.5, anchor: .center, in: document)
        let preview = try document.previewNodes(for: plan.operations)
        for operation in plan.operations {
            try document.apply(operation)
        }
        for (id, node) in preview {
            var stored = try #require(document.node(id: id))
            stored.kind = stored.kind.withEmptyChildren()
            #expect(node == stored, "\(id)")
        }
        #expect(!preview.isEmpty)
    }
}

private extension AnyCodable {
    /// A number as the codec reads one back: whole numbers as `.int`.
    static func number(_ value: Double) -> AnyCodable {
        value == value.rounded() ? .int(Int(value)) : .double(value)
    }
}
