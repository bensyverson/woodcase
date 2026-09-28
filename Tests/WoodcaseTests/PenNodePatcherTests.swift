//
//  PenNodePatcherTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins ``PenNodePatcher/patchNode(_:with:)`` to the JSON-merge semantics its callers
/// depend on.
///
/// The patcher is the seam every component override goes through — ``PenRefExpander``
/// at parse time, ``ReactEmitter`` at code-gen time — and it is a JSON merge by
/// design: a patch names keys, and only those keys change. These tests exist because
/// the merge no longer re-serializes the node's whole subtree to do it (that round
/// trip was 492 ms of the 715 ms `tree` of `woodcase-app.pen` spends, measured
/// 2026-08-29; see <doc:WoodcasePerformance>), and skipping the subtree is only safe
/// while every case below still holds.
struct PenNodePatcherTests {
    // MARK: - Helpers

    /// A frame with a nested frame and a text leaf, three levels deep.
    ///
    /// - Returns: The node to patch.
    private func makeFrame() -> PenNode {
        PenNode(
            id: "outer",
            common: PenNodeCommon(name: "Outer", x: .literal(10)),
            kind: .frame(PenNode.FrameData(
                width: .fixed(200),
                height: .fixed(100),
                fills: .single(.shorthand("red")),
                children: [
                    PenNode(
                        id: "inner",
                        common: PenNodeCommon(name: "Inner"),
                        kind: .frame(PenNode.FrameData(
                            width: .fixed(50),
                            children: [
                                PenNode(
                                    id: "label",
                                    common: PenNodeCommon(name: "Label"),
                                    kind: .text(PenNode.TextData(content: .literal("Hi")))
                                ),
                            ]
                        ))
                    ),
                ]
            ))
        )
    }

    /// The children of a frame node, or `nil` for any other kind.
    ///
    /// - Parameter node: The node to read.
    /// - Returns: The frame's children.
    private func children(of node: PenNode) -> [PenNode]? {
        guard case let .frame(data) = node.kind else { return nil }
        return data.children
    }

    // MARK: - Property merge

    @Test("A patch changes only the keys it names")
    func patchTouchesOnlyNamedKeys() {
        let patched = PenNodePatcher.patchNode(makeFrame(), with: ["name": .string("Renamed")])

        #expect(patched.common.name == "Renamed")
        #expect(patched.common.x == .literal(10))
        #expect(patched.id == "outer")
        guard case let .frame(data) = patched.kind else {
            Issue.record("The patch changed the node's kind.")
            return
        }
        #expect(data.width == .fixed(200))
        #expect(data.fills == .single(.shorthand("red")))
    }

    @Test("A patch of a kind property leaves the common properties alone")
    func patchOfKindPropertyKeepsCommon() {
        let patched = PenNodePatcher.patchNode(makeFrame(), with: ["fill": .string("blue")])

        #expect(patched.common.name == "Outer")
        guard case let .frame(data) = patched.kind else {
            Issue.record("The patch changed the node's kind.")
            return
        }
        #expect(data.fills == .single(.shorthand("blue")))
    }

    // MARK: - The subtree

    @Test("A patch preserves the whole subtree untouched")
    func patchPreservesSubtree() {
        let original = makeFrame()
        let patched = PenNodePatcher.patchNode(original, with: ["name": .string("Renamed")])

        #expect(children(of: patched) == children(of: original))
    }

    @Test("A patch on a childless node leaves it childless")
    func patchOfChildlessNodeKeepsNoChildren() {
        let leaf = PenNode(
            id: "solo",
            common: PenNodeCommon(name: "Solo"),
            kind: .frame(PenNode.FrameData(width: .fixed(10)))
        )
        let patched = PenNodePatcher.patchNode(leaf, with: ["name": .string("Renamed")])

        #expect(patched.common.name == "Renamed")
        #expect(children(of: patched) == nil)
    }

    @Test("A patch on a node kind that cannot have children still merges")
    func patchOfLeafKindMerges() {
        let text = PenNode(
            id: "t",
            common: PenNodeCommon(name: "Text"),
            kind: .text(PenNode.TextData(content: .literal("Before")))
        )
        let patched = PenNodePatcher.patchNode(text, with: ["content": .string("After")])

        guard case let .text(data) = patched.kind else {
            Issue.record("The patch changed the node's kind.")
            return
        }
        #expect(data.content == .literal("After"))
    }

    // MARK: - Patches that rewrite structure

    @Test("A patch that names children replaces them")
    func patchOfChildrenReplacesThem() throws {
        let replacement: AnyCodable = .array([
            .dictionary([
                "id": .string("only"),
                "type": .string("text"),
                "name": .string("Only"),
                "content": .string("New"),
            ]),
        ])
        let patched = PenNodePatcher.patchNode(makeFrame(), with: ["children": replacement])

        let kids = try #require(children(of: patched))
        #expect(kids.count == 1)
        #expect(kids.first?.id == "only")
    }

    @Test("A patch that names a new type changes the node's kind")
    func patchOfTypeChangesKind() {
        let patched = PenNodePatcher.patchNode(
            makeFrame(), with: ["type": .string("rectangle")]
        )

        guard case .rectangle = patched.kind else {
            Issue.record("The patch left the node a frame.")
            return
        }
    }

    @Test("A patch of nothing returns an equal node")
    func emptyPatchIsIdentity() {
        let original = makeFrame()
        #expect(PenNodePatcher.patchNode(original, with: [:]) == original)
    }
}
