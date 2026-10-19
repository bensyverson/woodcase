//
//  ScaleInstanceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Scaling a component instance, or a node inside one (``ScaleCapture``): every scaled
/// property inside it is an override on the instance, and the component is unchanged (Ben's
/// ruling of 2026-10-18, Penumbra spec §5). The edits commit as one undo step and survive a
/// save.
@MainActor
struct ScaleInstanceTests {
    @Test("An instance moves by its own x and y, and its insides scale as overrides on it")
    func instance() throws {
        let document = try ScaleFixture.document()
        let component = try #require(document.node(id: "Button"))
        let label = try #require(document.node(id: "Label"))
        try ScaleFixture.scale(["Chip"], by: 2, anchor: .center, in: document)

        #expect(document.node(id: "Button") == component)
        #expect(document.node(id: "Label") == label)
        guard case let .ref(data)? = document.node(id: "Chip")?.kind else {
            Issue.record("Chip is no longer an instance")
            return
        }
        #expect(data.rootOverrides?["width"] == 240)
        #expect(data.rootOverrides?["height"] == 80)
        #expect(data.rootOverrides?["gap"] == 8)
        #expect(data.rootOverrides?["padding"] == 16)
        #expect(data.rootOverrides?["cornerRadius"] == 16)
        #expect(data.descendants?["Label"]?.properties["fontSize"] == 28)
        // The instance's box was 120 × 40 at (50, 600); about its center it is now 240 × 80.
        #expect(document.node(id: "Chip")?.common.x == .literal(-10))
        #expect(document.node(id: "Chip")?.common.y == .literal(580))
    }

    @Test("A node selected inside an instance scales as an override on the instance")
    func insideInstance() throws {
        let document = try ScaleFixture.document()
        let label = try #require(document.node(id: "Label"))
        try ScaleFixture.scale(["Chip/Label"], by: 1.5, in: document)

        #expect(document.node(id: "Label") == label)
        guard case let .ref(data)? = document.node(id: "Chip")?.kind else {
            Issue.record("Chip is no longer an instance")
            return
        }
        #expect(data.descendants?["Label"]?.properties["fontSize"] == 21)
        #expect(data.rootOverrides?["width"] == nil)
    }

    @Test("The edits commit as one undo step, which takes the whole scale back")
    func oneUndoStep() throws {
        let document = try ScaleFixture.document()
        let session = DocumentSession(document: document.materialize(), author: Author(name: "ana", peerID: PeerID(rawValue: "peer-ana")))
        let before = try PenParser.encode(session.document.materialize())
        let plan = try ScaleFixture.plan(["Card", "Chip", "Sticky"], by: 2, in: session.document)

        try session.submit(.local(LocalEdit(operations: plan.operations)))
        #expect(try ScaleFixture.value("kind.gap", of: "Card", in: session.document) == 16)
        try session.submit(.undo)

        #expect(try PenParser.encode(session.document.materialize()) == before)
    }

    @Test("A scaled document saves and reads back with every scaled value")
    func saveRoundTrip() throws {
        let document = try ScaleFixture.document()
        try ScaleFixture.scale(["Card", "Dashed", "Chip", "Sticky"], by: 2, in: document)

        let reread = try EditableDocument(from: PenParser.parse(PenParser.encode(document.materialize())))
        for id in ["Card", "Title", "Body", "Boxed", "Dashed", "Chip", "Sticky"] {
            #expect(reread.node(id: id) == document.node(id: id), "\(id)")
        }
        #expect(try ScaleFixture.value("kind.fontSize", of: "Title", in: reread) == 40)
        #expect(reread.node(id: "Dashed")?.strokeDash?.lengths == [8, 4])
        #expect(reread.node(id: "Card")?.shadowSpread(forEffect: 0) == 4)
    }
}
