//
//  PenNodeOverlayTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Holds ``PenNodePatcher/patched(_:with:)`` through ``PenNodeOverlay`` to the JSON round
/// trip, one kind of override at a time: same node when both accept, both refuse when
/// either does.
///
/// `PenNodePatcherEquivalenceTests` proves the same over every fixture; these name the
/// cases, so a failure says which one broke.
struct PenNodeOverlayTests {
    /// One node and one patch to lay over it.
    struct Case: CustomTestStringConvertible {
        let label: String
        let node: PenNode
        let patch: [String: AnyCodable]

        var testDescription: String {
            label
        }
    }

    static let frame = PenNode(
        id: "f",
        common: PenNodeCommon(name: "Frame", x: .literal(10)),
        kind: .frame(PenNode.FrameData(
            width: .fixed(200), fills: .single(.shorthand("red")),
            children: [PenNode(id: "t", common: PenNodeCommon(), kind: .text(PenNode.TextData(content: .literal("Hi"))))]
        )),
        extras: PenExtras(["layoutIncludeStroke": .bool(true)])
    )

    static let text = PenNode(
        id: "t", common: PenNodeCommon(name: "Label"),
        kind: .text(PenNode.TextData(content: .literal("Before")))
    )

    static let ref = PenNode(
        id: "i", common: PenNodeCommon(name: "Instance"),
        kind: .ref(PenNode.RefData(
            ref: "Card", descendants: ["t": PenDescendantOverride(properties: ["content": .string("A")])],
            rootOverrides: ["width": .int(40)]
        ))
    )

    static let unknown = PenNode(
        id: "u", common: PenNodeCommon(name: "Future"),
        kind: .unknown(typeName: "hologram", properties: ["depth": .int(3)])
    )

    static let cases: [Case] = [
        Case(label: "rename", node: frame, patch: ["name": .string("Renamed")]),
        Case(label: "fill", node: frame, patch: ["fill": .string("#00ff00")]),
        Case(label: "clear with null", node: frame, patch: ["width": .null, "x": .null]),
        Case(label: "integral double to a double property", node: frame, patch: ["opacity": .double(1.0)]),
        Case(label: "slot fill replaces children", node: frame, patch: ["children": .array([
            .dictionary(["id": .string("n"), "type": .string("rectangle"), "width": .int(5)]),
        ])]),
        Case(label: "children cleared with null", node: frame, patch: ["children": .null]),
        Case(label: "unclaimed key becomes an extra", node: frame, patch: ["futureKey": .double(2.0)]),
        Case(label: "extra overwritten", node: frame, patch: ["layoutIncludeStroke": .bool(false)]),
        Case(label: "id rewritten", node: frame, patch: ["id": .string("other")]),
        Case(label: "wrong shape is refused", node: frame, patch: ["width": .bool(true)]),
        Case(label: "one bad key refuses the whole patch", node: frame, patch: ["name": .string("X"), "gap": .string("wide")]),
        Case(label: "text content", node: text, patch: ["content": .string("After"), "fontSize": .int(14)]),
        Case(label: "children on a leaf is an extra", node: text, patch: ["children": .array([])]),
        Case(label: "ref repointed", node: ref, patch: ["ref": .string("Other")]),
        Case(label: "ref null ref is refused", node: ref, patch: ["ref": .null]),
        Case(label: "ref root override added", node: ref, patch: ["fill": .string("#000"), "height": .double(8.0)]),
        Case(label: "ref descendants replaced", node: ref, patch: ["descendants": .dictionary([
            "x/y": .dictionary(["enabled": .bool(false)]),
        ])]),
        Case(label: "ref common property", node: ref, patch: ["opacity": .double(0.5)]),
        Case(label: "unknown type property", node: unknown, patch: ["depth": .double(4.0), "name": .string("N")]),
    ]

    /// The patch's outcome: the node, or `nil` when it was refused.
    private static func outcome(_ route: PenNodePatcher.Route, _ testCase: Case) -> PenNode? {
        PenNodePatcher.$route.withValue(route) { try? PenNodePatcher.patched(testCase.node, with: testCase.patch) }
    }

    @Test("the overlay answers what the JSON round trip answers", arguments: cases)
    func agrees(testCase: Case) {
        let viaJSON = Self.outcome(.jsonRoundTrip, testCase)
        let overlay = Self.outcome(.overlayOnly, testCase)
        #expect(overlay == viaJSON)
    }
}
