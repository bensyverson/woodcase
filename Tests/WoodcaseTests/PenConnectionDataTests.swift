//
//  PenConnectionDataTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Covers the `connection` node: a connector from an anchor on one node to an anchor on
/// another. The keys are the ones Pen's validator accepts on a connection — `source` and
/// `target`, each `{path, anchor}` with both required, plus the five stroke keys and the
/// properties every node has — and nothing else: no fill, no size, no effects.
struct PenConnectionDataTests {
    // MARK: - Helpers

    private func node(_ json: String) throws -> PenNode {
        try JSONDecoder().decode(PenNode.self, from: Data(json.utf8))
    }

    private func authored(_ json: String) throws -> PenNode {
        let decoder = JSONDecoder()
        decoder.userInfo[PenDecodingMode.userInfoKey] = PenDecodingMode.authoring
        return try decoder.decode(PenNode.self, from: Data(json.utf8))
    }

    private func connection(_ node: PenNode) throws -> PenNode.ConnectionData {
        guard case let .connection(data) = node.kind else {
            Issue.record("\(node.id) is not a connection")
            throw CancellationError()
        }
        return data
    }

    private let json = #"""
    {"id":"C1","type":"connection","name":"a-to-b",
     "source":{"path":"A","anchor":"right"},"target":{"path":"I/K","anchor":"left"},
     "stroke":"#FF0000","strokeWidth":2,"strokeLinecap":"round"}
    """#

    // MARK: - Decoding

    @Test("A connection decodes its endpoints and its stroke")
    func decodes() throws {
        let node = try node(json)
        let data = try connection(node)
        #expect(data.source == PenNode.ConnectionData.Endpoint(path: "A", anchor: .right))
        #expect(data.target == PenNode.ConnectionData.Endpoint(path: "I/K", anchor: .left))
        let red = try JSONDecoder().decode(PenFills.self, from: Data(##""#FF0000""##.utf8))
        #expect(data.stroke == red)
        #expect(data.strokeWidth == .uniform(.literal(2)))
        #expect(data.strokeLinecap == .round)
        #expect(node.common.name == "a-to-b")
        #expect(node.extras.isEmpty)
    }

    @Test("Every anchor Pen takes decodes", arguments: PenNode.ConnectionData.Anchor.allCases)
    func anchors(anchor: PenNode.ConnectionData.Anchor) throws {
        let node = try node(#"""
        {"id":"C","type":"connection","source":{"path":"A","anchor":"\#(anchor.rawValue)"},
         "target":{"path":"B","anchor":"center"}}
        """#)
        #expect(try connection(node).source.anchor == anchor)
    }

    @Test("The anchors are exactly Pen's five")
    func anchorVocabulary() {
        #expect(PenNode.ConnectionData.Anchor.allCases.map(\.rawValue) == ["center", "top", "left", "bottom", "right"])
    }

    @Test("A connection with no source, or an endpoint with no anchor, is refused")
    func requiredKeys() {
        #expect(throws: DecodingError.self) {
            _ = try node(#"{"id":"C","type":"connection","target":{"path":"B","anchor":"left"}}"#)
        }
        #expect(throws: DecodingError.self) {
            _ = try node(#"{"id":"C","type":"connection","source":{"path":"A"},"target":{"path":"B","anchor":"left"}}"#)
        }
    }

    @Test("An anchor Pen does not take is refused")
    func unknownAnchor() {
        #expect(throws: DecodingError.self) {
            _ = try node(#"""
            {"id":"C","type":"connection","source":{"path":"A","anchor":"auto"},"target":{"path":"B","anchor":"left"}}
            """#)
        }
    }

    // MARK: - Encoding

    @Test("A connection encodes back to the keys it was read from")
    func roundTrip() throws {
        let written = try JSONEncoder().encode(node(json))
        let original = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
        #expect(try JSONSerialization.jsonObject(with: written) as? NSDictionary == original)
    }

    // MARK: - Keys a connection does not take

    @Test("A key a connection does not take is an extra in a file and refused when authored")
    func fillIsNotAConnectionKey() throws {
        let withFill = #"""
        {"id":"C","type":"connection","fill":"#FFFFFF",
         "source":{"path":"A","anchor":"right"},"target":{"path":"B","anchor":"left"}}
        """#
        #expect(try node(withFill).extras["fill"] == "#FFFFFF")
        #expect(throws: DecodingError.self) { _ = try authored(withFill) }
    }

    // MARK: - Geometry

    @Test("Each anchor names a point on its node's box", arguments: [
        (PenNode.ConnectionData.Anchor.center, 60.0, 40.0),
        (.top, 60, 20), (.bottom, 60, 60), (.left, 10, 40), (.right, 110, 40),
    ])
    func anchorPoint(anchor: PenNode.ConnectionData.Anchor, x: Double, y: Double) {
        let point = anchor.point(on: PenRect(x: 10, y: 20, width: 100, height: 40))
        #expect(point == PenNode.ConnectionData.AnchorPoint(x: x, y: y))
    }

    @Test("A segment runs from the source's anchor to the target's, in the rects given")
    func segment() throws {
        let data = try connection(node(json))
        let rects = ["A": PenRect(x: 0, y: 0, width: 40, height: 20), "I/K": PenRect(x: 100, y: 60, width: 40, height: 20)]
        let segment = try #require(data.segment(in: rects))
        #expect(segment.from == PenNode.ConnectionData.AnchorPoint(x: 40, y: 10))
        #expect(segment.to == PenNode.ConnectionData.AnchorPoint(x: 100, y: 70))
    }

    @Test("A segment whose endpoint names no node is nil")
    func segmentWithMissingNode() throws {
        let data = try connection(node(json))
        #expect(data.segment(in: ["A": PenRect(x: 0, y: 0, width: 40, height: 20)]) == nil)
    }

    // MARK: - The vocabulary

    @Test("connection is a node type, described, with its endpoints and stroke keys")
    func nodeType() {
        #expect(PenNode.NodeType(rawValue: "connection") == .connection)
        #expect(PenNode.NodeType.connection.summary.contains("two nodes"))
        #expect(PropertyDiff.allKindKeys(.connection) == [
            "kind.source", "kind.target",
            "kind.stroke", "kind.strokeWidth", "kind.strokeLinecap", "kind.strokeLinejoin", "kind.strokeAlignment",
        ])
    }
}
