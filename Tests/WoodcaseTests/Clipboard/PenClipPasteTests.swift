//
//  PenClipPasteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenClip/plan(into:at:)`` — the paste half of copy and paste: what job criterion
/// `YQk` asks of it.
struct PenClipPasteTests {
    /// A target that already has a different `Button` and a different `$accent`.
    static let collidingTarget = """
    {
      "version": "2.17",
      "variables": { "accent": { "type": "color", "value": "#FF00FF" } },
      "children": [
        {
          "id": "Mine", "name": "Button", "type": "frame", "reusable": true, "width": 30, "height": 10,
          "children": [{ "id": "Box", "type": "rectangle", "width": 5, "height": 5, "fill": "#00FFFF" }]
        }
      ]
    }
    """

    @Test("An instance pasted into an empty document renders the same as the source")
    func pasteIntoEmptyRendersTheSame() throws {
        let source = try PenClipFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: source)
        let target = PasteFixture.empty()

        let plan = try clip.plan(into: target, at: .inPlace)
        try PasteFixture.apply(plan, to: target)

        let pasted = try #require(plan.insertedRootIDs.first)
        let before = try #require(PasteFixture.render(source, nodeID: "BtnI"))
        let after = try #require(PasteFixture.render(target, nodeID: pasted))
        let blank = try #require(PasteFixture.blank(like: before))
        #expect(PenSnapshotTestHelpers.meanAbsoluteError(between: before, and: blank) > 1)
        #expect(after.width == before.width)
        #expect(after.height == before.height)
        #expect(PenSnapshotTestHelpers.meanAbsoluteError(between: after, and: before) < 0.01)
    }

    @Test("A component whose name the target holds with another definition comes along renamed")
    func collidingComponentIsRenamed() throws {
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: PenClipFixture.document())
        let target = try PasteFixture.document(Self.collidingTarget)

        let plan = try clip.plan(into: target, at: .inPlace)

        let inserted = PasteFixture.inserted(plan)
        let button = try #require(inserted.values.first { $0.common.name == "Button 2" })
        #expect(button.common.reusable == true)
        let pasted = try #require(inserted[plan.insertedRootIDs.first ?? ""])
        guard case let .ref(instance) = pasted.kind else {
            Issue.record("the pasted instance is not a ref")
            return
        }
        #expect(instance.ref == button.id)
        #expect(plan.renamedComponents == [PastePlan.Rename(from: "Button", to: "Button 2")])
        try PasteFixture.apply(plan, to: target)
        #expect(target.nodes["Mine"]?.common.name == "Button")
    }

    @Test("A variable whose name the target holds with another value comes along renamed, and its uses follow")
    func collidingVariableIsRenamed() throws {
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: PenClipFixture.document())
        let target = try PasteFixture.document(Self.collidingTarget)

        let plan = try clip.plan(into: target, at: .inPlace)

        let added = PasteFixture.addedVariables(plan)
        #expect(Set(added.keys) == ["accent-2", "brand"])
        #expect(added["accent-2"]?.value == .simple("$brand"))
        #expect(plan.renamedVariables == [PastePlan.Rename(from: "accent", to: "accent-2")])
        let icon = try #require(PasteFixture.inserted(plan).values.first { $0.common.name == "Icon" })
        guard case let .frame(data) = icon.kind else {
            Issue.record("the pasted Icon is not a frame")
            return
        }
        #expect(data.fills == .single(.shorthand("$accent-2")))
    }

    @Test("A component and variables the target already holds, identically, are reused")
    func identicalDefinitionsAreReused() throws {
        let source = try PenClipFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: source)

        let plan = try clip.plan(into: source, at: .inPlace)

        #expect(plan.operations.count == 1)
        #expect(plan.reusedComponents == ["Btn": "Btn", "Icon": "Icon"])
        #expect(plan.reusedVariables == ["accent", "brand"])
        let pasted = try #require(PasteFixture.inserts(plan).first?.node)
        guard case let .ref(instance) = pasted.kind else {
            Issue.record("the pasted instance is not a ref")
            return
        }
        #expect(instance.ref == "Btn")
        #expect(!source.nodes.keys.contains(pasted.id))
    }

    @Test("Pasted into a stack, the copy lands at the end of its children and joins the flow")
    func intoStackLandsAtTheEnd() throws {
        let source = try PenClipFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["Free"], from: source)

        let plan = try clip.plan(into: source, at: .inside(containerID: "Card"))
        try PasteFixture.apply(plan, to: source)

        let pasted = try #require(plan.insertedRootIDs.first)
        #expect(try PasteFixture.childIDs(of: "Card", in: source) == ["BtnI", "Fill", pasted])
        #expect(source.nodes[pasted]?.common.x == nil)
        #expect(source.nodes[pasted]?.common.y == nil)
    }

    @Test("Submitted as one local edit, a paste is one undo step")
    func oneUndoStep() throws {
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: PenClipFixture.document())
        let ana = Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
        let session = DocumentSession(document: PasteFixture.empty().materialize(), author: ana)

        let plan = try clip.plan(into: session.document, at: .inPlace)
        try session.submit(.local(LocalEdit(operations: plan.operations)))
        #expect(session.document.nodes.count > 1)
        try session.submit(.undo)

        #expect(session.document.nodes.isEmpty)
        #expect((session.document.variables ?? [:]).isEmpty)
        #expect((session.document.themes ?? [:]).isEmpty)
    }

    @Test("A paste that would put a component inside itself is refused, naming the loop")
    func loopIsRefused() throws {
        let source = try PenClipFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["BtnI"], from: source)

        #expect {
            try clip.plan(into: source, at: .inside(containerID: "Icon"))
        } throws: { error in
            guard case let .wouldCloseComponentLoop(loop) = error as? PasteError else { return false }
            return loop.description == "Icon → Button → Icon"
        }
    }
}
