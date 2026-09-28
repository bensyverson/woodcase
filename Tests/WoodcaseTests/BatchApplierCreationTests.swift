//
//  BatchApplierCreationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct BatchApplierCreationTests {
    // MARK: - Helpers

    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/batch.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func apply(_ jsonl: String, to document: EditableDocument) throws -> BatchReport {
        try BatchApplier.apply(BatchOperation.decodeJSONL(jsonl), to: document)
    }

    // MARK: - Naming

    @Test("An unnamed node in an add fails that line, naming the type and suggesting a name")
    func unnamedNodeFails() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"rectangle","width":10,"height":10}}
        """#, to: doc)

        #expect(report.lines[0].status == .failed)
        let message = try #require(report.lines[0].error)
        #expect(message.contains("rectangle"))
        #expect(message.lowercased().contains("name"))
    }

    @Test("An unnamed node deep in the subtree fails the line and locates itself")
    func unnamedDescendantFails() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Hero","width":10,\
        "children":[{"type":"text","name":"Caption","content":"hi"},{"type":"ellipse","width":4}]}}
        """, to: doc)

        #expect(report.lines[0].status == .failed)
        let message = try #require(report.lines[0].error)
        #expect(message.contains("ellipse"))
        #expect(message.contains("Hero"))
        #expect(doc.childIDs(of: "Crd01").count == 2)
    }

    @Test("A cp never demands names, because the source may be a file we did not write")
    func copyDoesNotDemandNames() throws {
        let doc = try makeDocument()
        try doc.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: "Cd101", common: PenNodeCommon())))

        let report = try apply(#"{"op":"cp","source":"Cd101","parent":"Canvas/Cards"}"#, to: doc)
        #expect(report.lines[0].status == .applied)
    }

    // MARK: - Created tree

    @Test("An add reports the created subtree as a tree of names and fresh ids")
    func createdTreeMirrorsTheSubtree() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Hero","width":10,\
        "children":[{"type":"text","name":"Caption","content":"hi"},\
        {"type":"frame","name":"Inner","width":4,"children":[{"type":"text","name":"Deep","content":"d"}]}]}}
        """, to: doc)

        let created = try #require(report.lines[0].created.first)
        #expect(created.name == "Hero")
        #expect(created.children.map(\.name) == ["Caption", "Inner"])
        #expect(created.children[1].children.map(\.name) == ["Deep"])

        // Every reported id is a real node, and the shape matches the document.
        #expect(doc.node(id: created.id) != nil)
        #expect(doc.childIDs(of: created.id) == created.children.map(\.id))
        #expect(doc.childIDs(of: created.children[1].id) == created.children[1].children.map(\.id))
    }

    // MARK: - Ids

    @Test("An id the caller supplied is the id the node gets")
    func suppliedIDIsKept() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"add","parent":"Canvas/Cards","node":{"id":"Hero1","type":"frame","name":"Hero","width":10}}
        """#, to: doc)

        #expect(report.lines[0].status == .applied)
        #expect(report.lines[0].created.first?.id == "Hero1")
        #expect(doc.node(id: "Hero1")?.common.name == "Hero")
    }

    @Test("A subtree may supply some ids and omit others; the omitted ones are drawn")
    func omittedIDsAreGenerated() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"add","parent":"Canvas/Cards","node":{"id":"Hero1","type":"frame","name":"Hero","width":10,\
        "children":[{"type":"text","name":"Caption","content":"hi"}]}}
        """, to: doc)

        let created = try #require(report.lines[0].created.first)
        #expect(created.id == "Hero1")
        let caption = try #require(created.children.first)
        #expect(!caption.id.isEmpty)
        #expect(PenID.isValid(caption.id))
        #expect(doc.node(id: caption.id)?.common.name == "Caption")
    }

    @Test("A supplied id already in the document fails the line and says to leave it out")
    func collidingSuppliedIDFails() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"add","parent":"Canvas/Cards","node":{"id":"Cd101","type":"frame","name":"Hero","width":10}}
        """#, to: doc)

        #expect(report.lines[0].status == .failed)
        let message = try #require(report.lines[0].error)
        #expect(message.contains("Cd101"))
        #expect(message.contains("\"id\""))
        // Nothing changed: the existing Cd101 is still First, and Cards still has two children.
        #expect(doc.node(id: "Cd101")?.common.name == "First")
        #expect(doc.childIDs(of: "Crd01").count == 2)
    }

    @Test("Two nodes in one subtree sharing an id fail the line, even though the document has neither")
    func selfCollidingSuppliedIDsFail() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"add","parent":"Canvas/Cards","node":{"id":"Hero1","type":"frame","name":"Hero","width":10,\
        "children":[{"id":"Dup","type":"text","name":"One","content":"a"},\
        {"id":"Dup","type":"text","name":"Two","content":"b"}]}}
        """, to: doc)

        #expect(report.lines[0].status == .failed)
        #expect(try #require(report.lines[0].error).contains("Dup"))
        #expect(doc.node(id: "Hero1") == nil)
    }

    @Test("A supplied id with a slash in it fails the line, because nothing could address it")
    func suppliedIDWithASlashFails() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"add","parent":"Canvas/Cards","node":{"id":"Hero/1","type":"frame","name":"Hero","width":10}}
        """#, to: doc)

        #expect(report.lines[0].status == .failed)
        let message = try #require(report.lines[0].error)
        #expect(message.contains("Hero/1"))
        #expect(message.contains("/"))
    }

    @Test("A tagged line may supply its own id, and @tag and the id name the same node")
    func taggedLineWithASuppliedID() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"add","parent":"Canvas","node":{"id":"Hero1","type":"frame","name":"Hero","width":10},"tag":"hero"}
        {"op":"add","parent":"@hero","node":{"type":"text","name":"Caption","content":"hi"}}
        {"op":"set","target":"Hero1","props":{"common.name":"Renamed"}}
        """, to: doc)

        #expect(report.lines.map(\.status) == [.applied, .applied, .applied])
        #expect(report.lines[0].created.first?.id == "Hero1")
        let caption = try #require(report.lines[1].created.first?.id)
        #expect(doc.parentID(of: caption) == "Hero1")
        #expect(doc.node(id: "Hero1")?.common.name == "Renamed")
    }

    @Test("An add honours its index")
    func addAtIndex() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Hero","width":10},"at":0}
        """#, to: doc)

        let created = try #require(report.lines[0].created.first)
        #expect(doc.childIDs(of: "Crd01") == [created.id, "Cd101", "Cd201"])
    }

    // MARK: - Root-level placement

    @Test("A root-level add with no coordinates lands to the right of the rightmost root")
    func rootPlacement() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"add","node":{"type":"frame","name":"Fresh","width":120,"height":80}}
        """#, to: doc)

        let created = try #require(report.lines[0].created.first)
        let node = try #require(doc.node(id: created.id))
        // Roots occupy up to x = 700 (Board at x 500, width 200); the gap is 100.
        #expect(node.common.x?.literalValue == 800)
        #expect(node.common.y?.literalValue == 0)
        #expect(doc.rootOrder.last == created.id)
    }

    @Test("A root-level add that declares its own coordinates keeps them")
    func rootPlacementRespectsDeclaredCoordinates() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"add","node":{"type":"frame","name":"Fresh","x":12,"y":34,"width":10}}
        """#, to: doc)

        let createdID = try #require(report.lines[0].created.first?.id)
        let node = try #require(doc.node(id: createdID))
        #expect(node.common.x?.literalValue == 12)
        #expect(node.common.y?.literalValue == 34)
    }

    @Test("Two root-level adds in one batch do not land on top of each other")
    func successiveRootAddsStepRight() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"add","node":{"type":"frame","name":"One","width":100,"height":50}}
        {"op":"add","node":{"type":"frame","name":"Two","width":100,"height":50}}
        """, to: doc)

        let firstID = try #require(report.lines[0].created.first?.id)
        let secondID = try #require(report.lines[1].created.first?.id)
        let first = try #require(doc.node(id: firstID))
        let second = try #require(doc.node(id: secondID))
        #expect(first.common.x?.literalValue == 800)
        #expect(second.common.x?.literalValue == 1000)
    }

    @Test("A child of a laid-out parent takes no coordinates of its own")
    func childrenTakeNoCoordinates() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Hero","width":10}}
        """#, to: doc)

        let createdID = try #require(report.lines[0].created.first?.id)
        let node = try #require(doc.node(id: createdID))
        #expect(node.common.x == nil)
        #expect(node.common.y == nil)
    }

    // MARK: - Copy

    @Test("Copying a plain subtree deep-copies it with fresh ids")
    func copyPlainSubtree() throws {
        let doc = try makeDocument()
        let report = try apply(#"{"op":"cp","source":"Canvas/Cards","parent":"Board"}"#, to: doc)

        let created = try #require(report.lines[0].created.first)
        #expect(created.name == "Cards")
        #expect(created.id != "Crd01")
        #expect(created.children.map(\.name) == ["First", "Second"])
        #expect(doc.parentID(of: created.id) == "Brd01")
        #expect(doc.node(id: "Crd01") != nil)
    }

    @Test("A cp regenerates every id, even ones the caller could have supplied to an add")
    func copyRegeneratesEveryID() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"add","parent":"Board","node":{"id":"Kit1","type":"frame","name":"Kit","width":10,\
        "children":[{"id":"Btn1","type":"frame","name":"Button","width":10}]}}
        {"op":"cp","source":"Kit1","parent":"Canvas"}
        """, to: doc)

        #expect(report.lines.map(\.status) == [.applied, .applied])
        let copied = try #require(report.lines[1].created.first)
        #expect(copied.allIDs.count == 2)
        #expect(Set(copied.allIDs).isDisjoint(with: ["Kit1", "Btn1"]))
        #expect(doc.node(id: "Btn1")?.common.name == "Button")
    }

    @Test("A ref inside a copied subtree follows the copy, not the subtree it was copied from")
    func copyRewritesRefsInsideTheSubtree() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"add","parent":"Board","node":{"id":"Kit1","type":"frame","name":"Kit","width":10,\
        "children":[{"id":"Btn1","type":"frame","name":"Button","reusable":true,"width":10},\
        {"id":"Use1","type":"ref","name":"Instance","ref":"Btn1"}]}}
        {"op":"cp","source":"Kit1","parent":"Canvas"}
        """, to: doc)

        #expect(report.lines.map(\.status) == [.applied, .applied])
        let copied = try #require(report.lines[1].created.first)
        let copiedButton = try #require(copied.children.first)
        let copiedRefID = try #require(copied.children.last).id
        let copiedRef = try #require(doc.node(id: copiedRefID))
        guard case let .ref(data) = copiedRef.kind else {
            Issue.record("expected a ref node, got \(copiedRef.kind.typeName)")
            return
        }
        #expect(copiedButton.id != "Btn1")
        #expect(data.ref == copiedButton.id)
    }

    @Test("A ref pointing outside the copied subtree still points where it did")
    func copyKeepsRefsPointingOutside() throws {
        let doc = try makeDocument()
        let report = try apply(#"{"op":"cp","source":"Board","parent":"Canvas"}"#, to: doc)

        let copied = try #require(report.lines[0].created.first)
        let chipID = try #require(copied.children.first).id
        let chip = try #require(doc.node(id: chipID))
        guard case let .ref(data) = chip.kind else {
            Issue.record("expected a ref node, got \(chip.kind.typeName)")
            return
        }
        #expect(chipID != "Chi01")
        #expect(data.ref == "Cmp01")
    }

    @Test("Copying a reusable component makes a ref to it, as Pen does")
    func copyReusableMakesARef() throws {
        let doc = try makeDocument()
        let report = try apply(#"{"op":"cp","source":"Component","parent":"Board"}"#, to: doc)

        let created = try #require(report.lines[0].created.first)
        let node = try #require(doc.node(id: created.id))
        guard case let .ref(data) = node.kind else {
            Issue.record("expected a ref node, got \(node.kind.typeName)")
            return
        }
        #expect(data.ref == "Cmp01")
        #expect(node.common.name == "Component")
        #expect(created.children.isEmpty)
        #expect(doc.node(id: "Cmp01")?.common.reusable == true)
    }

    @Test("A root-level cp lands in empty space, not on top of the node it copied")
    func rootCopyIsPlaced() throws {
        let doc = try makeDocument()
        let report = try apply(#"{"op":"cp","source":"Board"}"#, to: doc)

        let created = try #require(report.lines[0].created.first)
        let node = try #require(doc.node(id: created.id))
        // Board sits at (500, 40); the copy belongs past the rightmost root, not on it.
        #expect(node.common.x?.literalValue == 800)
        #expect(node.common.y?.literalValue == 0)
    }

    @Test("A root-level cp takes the coordinates its caller gave it, and is placed on the axis it did not")
    func rootCopyTakesGivenCoordinates() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"cp","source":"Board","props":{"common.x":42}}
        """#, to: doc)

        let created = try #require(report.lines[0].created.first)
        let node = try #require(doc.node(id: created.id))
        #expect(node.common.x?.literalValue == 42)
        // Not the source's y of 40: only the props are authorship.
        #expect(node.common.y?.literalValue == 0)
    }

    @Test("A cp applies its props to the copy, not to the source")
    func copyAppliesProps() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"cp","source":"Canvas/Cards/First","parent":"Board","props":{"common.name":"Third"}}
        """#, to: doc)

        let created = try #require(report.lines[0].created.first)
        #expect(doc.node(id: created.id)?.common.name == "Third")
        #expect(doc.node(id: "Cd101")?.common.name == "First")
    }
}
