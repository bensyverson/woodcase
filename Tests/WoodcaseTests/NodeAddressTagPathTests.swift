//
//  NodeAddressTagPathTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A tag names a node an earlier line created; a path walks down from a node. They
/// compose: `@row1/Title` is the tag's node, then one step. Without that a batch that
/// creates an instance and dresses its descendants has to run twice — create, read the
/// ids back, then override.
@MainActor
@Suite("@tag composed with a path")
struct NodeAddressTagPathTests {
    /// frame(row1) > [text(ttl01)], and a component cmp01 > [text(lbl01)] with an
    /// instance ref01 of it.
    private func document() -> EditableDocument {
        let title = PenNode(id: "ttl01", common: PenNodeCommon(name: "Title"), kind: .text(PenNode.TextData()))
        let row = PenNode(
            id: "row01",
            common: PenNodeCommon(name: "Row"),
            kind: .frame(PenNode.FrameData(children: [title]))
        )
        let label = PenNode(id: "lbl01", common: PenNodeCommon(name: "Label"), kind: .text(PenNode.TextData()))
        var componentCommon = PenNodeCommon(name: "Chip")
        componentCommon.reusable = true
        let component = PenNode(
            id: "cmp01",
            common: componentCommon,
            kind: .frame(PenNode.FrameData(children: [label]))
        )
        let instance = PenNode(
            id: "ref01",
            common: PenNodeCommon(name: "Chip 1"),
            kind: .ref(PenNode.RefData(ref: "cmp01"))
        )
        return EditableDocument(from: PenDocument(children: [row, component, instance]))
    }

    // MARK: - Parsing

    @Test("A tag followed by a path parses to the tag and the remaining segments")
    func tagWithPathParses() throws {
        let address = try #require(NodeAddress("@row1/Uiko4"))
        #expect(address == .tag(name: "row1", path: ["Uiko4"]))
        #expect(address.tagName == "row1")
        #expect(address.segments == nil)
    }

    @Test("A bare tag parses with an empty path")
    func bareTagParses() throws {
        let address = try #require(NodeAddress("@hero"))
        #expect(address == .tag(name: "hero", path: []))
    }

    @Test("A tag address round-trips through its written form")
    func tagWithPathRoundTrips() throws {
        let address = try #require(NodeAddress("@row1/Header/Title"))
        #expect(address.description == "@row1/Header/Title")
        #expect(NodeAddress(address.description) == address)
    }

    @Test(
        "A tag with an empty segment does not parse",
        arguments: ["@", "@/Title", "@hero/", "@hero//Title", "@hero/#"]
    )
    func malformedTagPaths(raw: String) {
        #expect(NodeAddress(raw) == nil)
    }

    // MARK: - Resolving

    @Test("A tag with a path resolves to the node one step below the tagged node")
    func resolvesOneStepBelowTheTag() throws {
        let address = try #require(NodeAddress("@row/Title"))
        #expect(try document().resolve(address, tags: ["row": "row01"]) == .node(id: "ttl01"))
    }

    @Test("A tag with a path steps into an instance the way a name path does")
    func resolvesIntoAnInstance() throws {
        let address = try #require(NodeAddress("@chip/Label"))
        let resolved = try document().resolve(address, tags: ["chip": "ref01"])
        #expect(resolved == .instanceDescendant(refID: "ref01", descendantKey: "lbl01"))
    }

    @Test("A tag with a path that names nothing is a miss, not a parse failure")
    func missingSuffixIsAMiss() throws {
        let address = try #require(NodeAddress("@row/Nope"))
        #expect(throws: EditingError.self) {
            try document().resolve(address, tags: ["row": "row01"])
        }
    }

    @Test("A path on an unknown tag is a miss")
    func unknownTagIsAMiss() throws {
        let address = try #require(NodeAddress("@nope/Title"))
        #expect(throws: EditingError.self) {
            try document().resolve(address, tags: [:])
        }
    }

    // MARK: - In a batch

    @Test("A later line dresses a descendant of what an earlier line tagged")
    func batchSetsThroughATag() throws {
        let document = EditableDocument(from: PenDocument(children: []))
        let subtree = PenNode(
            id: "row01",
            common: PenNodeCommon(name: "Row"),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(id: "ttl01", common: PenNodeCommon(name: "Title"), kind: .text(PenNode.TextData())),
            ]))
        )

        let report = try BatchApplier.apply([
            .add(BatchOperation.AddOp(node: subtree, tag: "row")),
            .set(BatchOperation.SetOp(
                target: #require(NodeAddress("@row/Title")),
                props: ["kind.content": AnyCodable.string("Hello")]
            )),
        ], to: document)

        #expect(report.lines.allSatisfy { $0.status == .applied })
        guard case let .text(data)? = document.nodes["ttl01"]?.kind else {
            Issue.record("no text node")
            return
        }
        #expect(data.content == .literal("Hello"))
    }

    @Test("A line addressing a descendant of a tag that was never created cascades")
    func batchCascadesThroughATag() throws {
        let document = EditableDocument(from: PenDocument(children: []))
        let unnamed = PenNode(id: "row01", common: PenNodeCommon(), kind: .frame(PenNode.FrameData()))

        let report = try BatchApplier.apply([
            .add(BatchOperation.AddOp(node: unnamed, tag: "row")),
            .set(BatchOperation.SetOp(
                target: #require(NodeAddress("@row/Title")),
                props: ["kind.content": AnyCodable.string("Hello")]
            )),
        ], to: document)

        #expect(report.lines[0].status == .failed)
        #expect(report.lines[1].status == .cascaded)
        #expect(report.lines[1].error?.contains("@row") == true)
    }
}
