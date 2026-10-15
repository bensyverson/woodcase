//
//  EditPlannerGroupTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Group and Frame Selection (``EditPlanner/planGroup(nodeIDs:kind:in:layout:)``): the
/// wrapper goes into the front-most member's parent at that member's slot, and every
/// member keeps the quad it is drawn as on the canvas — under turned and flipped parents,
/// across parents and out of a stack (Penumbra spec §14, the integrator's ruling of
/// 2026-10-15).
@MainActor
struct EditPlannerGroupTests {
    /// Every rectangle-like node in the fixture.
    private static let leaves = ["A", "B", "T1", "T2", "T3", "S1", "S2", "S3", "Front"]

    /// Plans and applies a group, returning the wrapper's id and what moved on the canvas.
    private func group(
        _ ids: [String], kind: WrapKind = .group, in document: EditableDocument
    ) throws -> (wrapperID: String, moved: [String]) {
        let before = WrapFixture.quads(Self.leaves, in: document)
        let plan = try EditPlanner.planGroup(
            nodeIDs: ids, kind: kind, in: document, layout: WrapFixture.layout(of: document)
        )
        try WrapFixture.apply(plan.operations, to: document)
        let after = WrapFixture.quads(Self.leaves, in: document)
        return (plan.wrapperID, WrapFixture.moved(before, after))
    }

    @Test("Two free siblings: the wrapper takes the front-most one's slot and nothing moves on the canvas")
    func freeSiblings() throws {
        let document = try WrapFixture.document()
        let result = try group(["B", "A"], in: document)

        #expect(result.moved.isEmpty, "moved: \(result.moved)")
        #expect(document.childIDs(of: "Board") == [result.wrapperID, "Turned", "Stack", "Front"])
        #expect(document.childIDs(of: result.wrapperID) == ["A", "B"])
        let wrapper = try #require(document.node(id: result.wrapperID))
        guard case .group = wrapper.kind else {
            Issue.record("the wrapper is not a group: \(wrapper.kind)")
            return
        }
        #expect(wrapper.common.rotation == nil)
    }

    @Test("Members of a turned, flipped group keep their quads, and the wrapper is unturned in that group")
    func underTurnedFlippedParent() throws {
        let document = try WrapFixture.document()
        let result = try group(["T2", "T3"], in: document)

        #expect(result.moved.isEmpty, "moved: \(result.moved)")
        #expect(document.parentID(of: result.wrapperID) == "Turned")
        #expect(document.childIDs(of: "Turned") == ["T1", result.wrapperID])
        let wrapper = try #require(document.node(id: result.wrapperID))
        #expect(wrapper.common.rotation == nil && wrapper.common.flipX == nil && wrapper.common.flipY == nil)
        // T2 keeps its own turn and flip, because the wrapper does not turn.
        let t2 = try #require(document.node(id: "T2"))
        #expect(t2.common.rotation == .literal(-20))
        #expect(t2.common.flipY == .literal(true))
    }

    @Test("A member from a turned, flipped parent moves in with its turn and flips folded in")
    func acrossParents() throws {
        let document = try WrapFixture.document()
        let result = try group(["T2", "A", "Front"], in: document)

        #expect(result.moved.isEmpty, "moved: \(result.moved)")
        #expect(document.parentID(of: result.wrapperID) == "Board")
        #expect(document.childIDs(of: "Board") == ["B", "Turned", "Stack", result.wrapperID])
        #expect(document.childIDs(of: result.wrapperID) == ["A", "T2", "Front"])
        #expect(document.childIDs(of: "Turned") == ["T1", "T3"])
    }

    @Test("A member from a stack leaves the flow where it was drawn, its fill width frozen")
    func outOfAStack() throws {
        let document = try WrapFixture.document()
        let result = try group(["S1", "Front"], in: document)

        // The members stay; S2 and S3 close the gap S1 left in the flow.
        #expect(result.moved == ["S2", "S3"], "moved: \(result.moved)")
        let s1 = try #require(document.node(id: "S1"))
        #expect(try NodePropertyCodec.value(at: "kind.width", of: s1) == .int(184))
        #expect(document.childIDs(of: "Stack") == ["S2", "S3"])
    }

    @Test("In-flow members of a stack become the wrapper's free children, and the wrapper takes the flow slot")
    func withinAStack() throws {
        let document = try WrapFixture.document()
        let result = try group(["S2", "S3"], in: document)

        #expect(result.moved.isEmpty, "moved: \(result.moved)")
        #expect(document.childIDs(of: "Stack") == ["S1", result.wrapperID])
        let wrapper = try #require(document.node(id: result.wrapperID))
        // In flow: the stack places it, so it carries no position of its own.
        #expect(wrapper.common.x == nil && wrapper.common.y == nil)
        #expect(wrapper.common.layoutPosition == nil)
        let s3 = try #require(document.node(id: "S3"))
        #expect(s3.common.x != nil && s3.common.y != nil)
    }

    @Test("Frame Selection wraps in a free frame sized to the members' union")
    func frameSelection() throws {
        let document = try WrapFixture.document()
        let result = try group(["A", "B"], kind: .frame, in: document)

        #expect(result.moved.isEmpty, "moved: \(result.moved)")
        let wrapper = try #require(document.node(id: result.wrapperID))
        guard case let .frame(data) = wrapper.kind else {
            Issue.record("the wrapper is not a frame: \(wrapper.kind)")
            return
        }
        #expect(data.layout == PenLayoutDirection.none)
        // A at (20, 30); B is 30 × 50 turned 15° about (100, 80): its bounds reach x 141.92 and y 128.30.
        #expect(wrapper.common.x == .literal(20))
        #expect(wrapper.common.y == .literal(30))
        let width = try #require(data.width?.fixedValue)
        let height = try #require(data.height?.fixedValue)
        #expect(abs(width - 121.92) < 0.01, "\(width)")
        #expect(abs(height - 98.30) < 0.01, "\(height)")
    }

    @Test("Frame Selection under a turned parent keeps every member's quad")
    func frameUnderTurnedParent() throws {
        let document = try WrapFixture.document()
        let result = try group(["T1", "T2"], kind: .frame, in: document)
        #expect(result.moved.isEmpty, "moved: \(result.moved)")
        #expect(document.parentID(of: result.wrapperID) == "Turned")
    }

    @Test("A member inside another member stays where it is; only the top-most are grouped")
    func descendantOfAMemberIsDropped() throws {
        let document = try WrapFixture.document()
        let result = try group(["Turned", "T1", "Front"], in: document)

        #expect(result.moved.isEmpty, "moved: \(result.moved)")
        #expect(document.childIDs(of: result.wrapperID) == ["Turned", "Front"])
        #expect(document.parentID(of: "T1") == "Turned")
    }

    @Test("An instance root can be grouped by its expanded id")
    func instanceRootByExpandedID() throws {
        let document = try WrapFixture.document()
        let expanded = document.expandedID(of: .node(id: "Chip"))
        let result = try group([expanded], in: document)
        #expect(document.childIDs(of: result.wrapperID) == ["Chip"])
    }

    // MARK: - Refusals

    @Test("A node inside an instance is refused with insideInstance")
    func insideInstance() throws {
        let document = try WrapFixture.document()
        let inside = document.expandedID(of: .instanceDescendant(refID: "Chip", descendantKey: "Slot"))
        let refusal = try #require(WrapFixture.groupRefusal([inside, "Front"], in: document))
        #expect(refusal.code == .insideInstance)
    }

    @Test("Nothing to group is refused with noNodes")
    func nothingToGroup() throws {
        let document = try WrapFixture.document()
        #expect(WrapFixture.groupRefusal([], in: document)?.code == .noNodes)
    }

    @Test("An id naming no node is refused with addressNotFound")
    func unknownID() throws {
        let document = try WrapFixture.document()
        #expect(WrapFixture.groupRefusal(["Nope"], in: document)?.code == .addressNotFound)
    }

    @Test("Grouping an instance into its own component closes a loop and is refused")
    func componentLoop() throws {
        let document = try WrapFixture.document()
        let refusal = try #require(WrapFixture.groupRefusal(["Chip", "Slot"], in: document))
        #expect(refusal.code == .documentRefused)
        #expect(refusal.errorCode == "wouldCloseComponentLoop")
    }
}
