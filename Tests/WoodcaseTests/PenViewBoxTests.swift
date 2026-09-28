//
//  PenViewBoxTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct PenViewBoxTests {
    // MARK: - PenViewBox coding

    @Test("PenViewBox decodes from a four-element JSON array")
    func decodesFromArray() throws {
        let json = Data("[25, 25, 50, 50]".utf8)
        let viewBox = try JSONDecoder().decode(PenViewBox.self, from: json)
        #expect(viewBox.x == 25)
        #expect(viewBox.y == 25)
        #expect(viewBox.width == 50)
        #expect(viewBox.height == 50)
    }

    @Test("PenViewBox encodes back to a four-element JSON array")
    func encodesToArray() throws {
        let viewBox = PenViewBox(x: 0, y: -10, width: 200, height: 100)
        let data = try JSONEncoder().encode(viewBox)
        let string = try #require(String(data: data, encoding: .utf8))
        #expect(string == "[0,-10,200,100]")
    }

    @Test("PenViewBox rejects an array that is not four numbers long")
    func rejectsWrongLength() {
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(PenViewBox.self, from: Data("[0, 0, 100]".utf8))
        }
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(PenViewBox.self, from: Data("[0, 0, 100, 100, 5]".utf8))
        }
    }

    @Test("PenViewBox renders whole numbers without a decimal point for SVG")
    func svgValueFormatting() {
        #expect(PenViewBox(x: 0, y: 0, width: 200, height: 200).svgValue == "0 0 200 200")
        #expect(PenViewBox(x: 25.5, y: -3, width: 50, height: 50.25).svgValue == "25.5 -3 50 50.25")
    }

    @Test("PenViewBox renders a value too large for Int without trapping")
    func svgValueHugeComponent() {
        let huge = PenViewBox(x: 0, y: 0, width: 1e18, height: 200)
        #expect(huge.svgValue.hasPrefix("0 0 "))
        #expect(huge.svgValue.hasSuffix(" 200"))
    }

    // MARK: - PathData

    @Test("PathData decodes the viewBox key")
    func pathDataDecodesViewBox() throws {
        let json = Data("""
        {"width": 200, "height": 200, "geometry": "M10 10l80 0-40 80z", "viewBox": [25, 25, 50, 50]}
        """.utf8)
        let data = try JSONDecoder().decode(PenNode.PathData.self, from: json)
        #expect(data.viewBox == PenViewBox(x: 25, y: 25, width: 50, height: 50))
    }

    @Test("PathData without a viewBox key decodes to nil")
    func pathDataViewBoxAbsent() throws {
        let json = Data(#"{"width": 200, "height": 200, "geometry": "M10 10l80 0-40 80z"}"#.utf8)
        let data = try JSONDecoder().decode(PenNode.PathData.self, from: json)
        #expect(data.viewBox == nil)
    }

    @Test("PathData round-trips the viewBox through encode and decode")
    func pathDataRoundTripsViewBox() throws {
        let original = PenNode.PathData(
            width: .fixed(200),
            height: .fixed(100),
            geometry: "M10 10l80 0-40 80z",
            viewBox: PenViewBox(x: 0, y: 0, width: 100, height: 100)
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PenNode.PathData.self, from: encoded)
        #expect(decoded.viewBox == original.viewBox)
    }

    // MARK: - PropertyDiff

    @Test("PropertyDiff reports a changed viewBox")
    func propertyDiffViewBoxChanged() {
        let old = PenNode.PathData(geometry: "M0 0L10 10")
        let new = PenNode.PathData(
            geometry: "M0 0L10 10",
            viewBox: PenViewBox(x: 0, y: 0, width: 10, height: 10)
        )
        let diff = PropertyDiff.diffKind(old: .path(old), new: .path(new))
        #expect(diff.contains("kind.viewBox"))
    }

    @Test("PropertyDiff lists viewBox among a path node's properties")
    func propertyDiffViewBoxInAllKeys() {
        let keys = PropertyDiff.allKindKeys(.path(PenNode.PathData()))
        #expect(keys.contains("kind.viewBox"))
    }

    // MARK: - CRDT codec

    @Test("viewBox round-trips through the CRDT property codec")
    func viewBoxCRDTCodec() throws {
        let doc = PenDocument(children: [
            PenNode(id: "p1", common: PenNodeCommon(), kind: .path(PenNode.PathData())),
        ])
        let editable = EditableDocument(from: doc, peerID: PeerID(rawValue: "test-peer"))
        let crdt = try #require(editable.crdtDocument)

        let kind = PenNode.Kind.path(PenNode.PathData(
            viewBox: PenViewBox(x: 25, y: 25, width: 50, height: 50)
        ))
        let extracted = crdt.extractKindValue(property: "kind.viewBox", from: kind)
        let applied = crdt.applyKindProperty(
            property: "kind.viewBox",
            value: extracted,
            to: .path(PenNode.PathData())
        )

        if case let .path(data) = applied {
            #expect(data.viewBox == PenViewBox(x: 25, y: 25, width: 50, height: 50))
        } else {
            Issue.record("Expected path kind")
        }
    }
}
