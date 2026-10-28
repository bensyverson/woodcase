//
//  ComponentDeleteSlotFillTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Deleting a component counts the instances written inside slot fills, which are no
/// stored nodes: a ref in an instance's `descendants` children, at any depth of the
/// fill, and in the fill an instance inside that fill writes in turn.
@MainActor
struct ComponentDeleteSlotFillTests {
    // MARK: - Fixtures

    /// `Btn` sits in `Lib`, beside `Demo`, a `Card` instance filling its `Body` with a
    /// `Btn`. On the page, `Inst` fills `Card`'s `Body` with a `Btn` (`Fb`), a frame
    /// holding one (`Box`/`Fb2`), and `Tag`, a `Badge` instance filling its own `Hole`
    /// with a third (`Fb3`).
    private func json() -> String {
        #"""
        {"version": "2.17", "children": [
          {"id": "Lib", "type": "frame", "name": "Lib", "children": [
            {"id": "Btn", "type": "frame", "name": "Btn", "reusable": true, "width": 40, "height": 20, "children": [
              {"id": "Lbl", "type": "text", "name": "Label", "content": "go"}]},
            {"id": "Demo", "type": "ref", "name": "Demo", "ref": "Card", "descendants": {
              "Body": {"children": [{"id": "Fb9", "type": "ref", "name": "Fb9", "ref": "Btn"}]}}}]},
          {"id": "Card", "type": "frame", "name": "Card", "reusable": true, "width": 200, "height": 100, "children": [
            {"id": "Body", "name": "Body", "type": "frame", "slot": ["frame", "ref"], "width": 150, "height": 80}]},
          {"id": "Badge", "type": "frame", "name": "Badge", "reusable": true, "width": 60, "height": 20, "children": [
            {"id": "Hole", "name": "Hole", "type": "frame", "slot": ["ref"], "width": 40, "height": 12}]},
          {"id": "Inst", "type": "ref", "name": "Inst", "ref": "Card", "descendants": {
            "Body": {"children": [
              {"id": "Fb", "type": "ref", "name": "Fb", "ref": "Btn"},
              {"id": "Box", "type": "frame", "name": "Box", "children": [
                {"id": "Fb2", "type": "ref", "name": "Fb2", "ref": "Btn"}]},
              {"id": "Tag", "type": "ref", "name": "Tag", "ref": "Badge", "descendants": {
                "Hole": {"children": [{"id": "Fb3", "type": "ref", "name": "Fb3", "ref": "Btn"}]}}}]}}}
        ]}
        """#
    }

    private func document() throws -> PenDocument {
        try PenParser.parse(Data(json().utf8))
    }

    private func editable(peerID: PeerID? = nil) throws -> EditableDocument {
        if let peerID {
            return try EditableDocument(from: document(), peerID: peerID)
        }
        return try EditableDocument(from: document())
    }

    private let deleteBtn = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: "Btn", instances: .detach))

    // MARK: - Helpers

    /// The component every ref in a fill names, at every depth, keyed by the ref's id.
    private func fillRefs(in editable: EditableDocument) -> [String: String] {
        var result: [String: String] = [:]
        func walk(_ list: [AnyCodable]) {
            for case let .dictionary(node) in list {
                if case let .string(id)? = node["id"], case let .string(ref)? = node["ref"] {
                    result[id] = ref
                }
                if case let .array(children)? = node["children"] { walk(children) }
                if case let .dictionary(map)? = node["descendants"] {
                    for case let .dictionary(entry) in map.values {
                        if case let .array(fill)? = entry["children"] { walk(fill) }
                    }
                }
            }
        }
        for node in editable.nodes.values {
            guard case let .ref(data) = node.kind else { continue }
            for entry in (data.descendants ?? [:]).values {
                if case let .array(fill)? = entry.properties["children"] { walk(fill) }
            }
        }
        return result
    }

    /// The fill a stored ref writes for one key.
    private func fill(_ key: String, of refID: String, in editable: EditableDocument) throws -> [AnyCodable] {
        guard case let .ref(data)? = editable.nodes[refID]?.kind,
              case let .array(children)? = data.descendants?[key]?.properties["children"]
        else {
            Issue.record("\(refID) writes no fill for \(key)")
            return []
        }
        return children
    }

    /// One node JSON's string value for a key.
    private func string(_ key: String, of value: AnyCodable?) -> String? {
        guard case let .dictionary(node)? = value, case let .string(string)? = node[key] else { return nil }
        return string
    }

    /// The children a node JSON holds.
    private func children(of value: AnyCodable?) -> [AnyCodable] {
        guard case let .dictionary(node)? = value, case let .array(children)? = node["children"] else { return [] }
        return children
    }

    // MARK: - Refusal

    @Test("A refused delete names every instance written inside a slot fill, nested fills included")
    func refusalNamesFillInstances() throws {
        let editable = try editable()
        let before = editable.materialize()

        #expect(throws: EditingError.componentHasInstances(
            componentID: "Btn",
            // Expanded addresses, hosts in name-path order (`Inst` before `Lib/Demo`).
            instanceIDs: ["Inst/Fb", "Inst/Fb2", "Inst/Tag/Fb3", "Demo/Fb9"]
        )) {
            try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Btn")))
        }
        #expect(editable.materialize() == before)
    }

    @Test("A fill whose host is deleted too strands nothing")
    func fillInsideTheDeletedSubtreeIsNotCounted() throws {
        let editable = try editable()

        #expect(throws: EditingError.componentHasInstances(
            componentID: "Btn",
            instanceIDs: ["Inst/Fb", "Inst/Fb2", "Inst/Tag/Fb3"]
        )) {
            try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Lib")))
        }
    }

    @Test("Validation refuses the delete before anything runs")
    func validationRefuses() throws {
        let editable = try editable()
        #expect(throws: EditingError.self) {
            try editable.validate(.deleteNode(EditOperation.DeleteNode(nodeID: "Lib")))
        }
    }

    @Test("A replace that drops a component a fill still instances refuses")
    func replaceRefusesForFillInstances() throws {
        let editable = try editable()
        let emptyLib = PenNode(id: "Lib", common: PenNodeCommon(name: "Lib"), kind: .frame(PenNode.FrameData(children: [])))

        #expect(throws: EditingError.componentHasInstances(
            componentID: "Btn",
            instanceIDs: ["Inst/Fb", "Inst/Fb2", "Inst/Tag/Fb3"]
        )) {
            try editable.apply(.replaceSubtree(EditOperation.ReplaceSubtree(node: emptyLib)))
        }
    }

    // MARK: - Detach

    @Test("A detaching delete detaches every fill instance in place, leaving no ref to the component")
    func detachingDeleteDetachesFillInstances() throws {
        let editable = try editable()

        try editable.apply(deleteBtn)

        #expect(editable.nodes["Btn"] == nil)
        #expect(!fillRefs(in: editable).values.contains("Btn"))

        let body = try fill("Body", of: "Inst", in: editable)
        #expect(body.count == 3)
        #expect(string("type", of: body.first) == "frame")
        #expect(string("name", of: body.first) == "Fb")
        #expect(string("content", of: children(of: body.first).first) == "go")

        let box = children(of: body.dropFirst().first)
        #expect(string("type", of: box.first) == "frame")
        #expect(string("content", of: children(of: box.first).first) == "go")

        let tag = body.last
        #expect(string("ref", of: tag) == "Badge", "the instance between keeps its link")
        guard case let .dictionary(tagNode)? = tag,
              case let .dictionary(map)? = tagNode["descendants"],
              case let .dictionary(hole)? = map["Hole"],
              case let .array(holeFill)? = hole["children"]
        else {
            Issue.record("Tag lost its fill")
            return
        }
        #expect(string("type", of: holeFill.first) == "frame")

        let demo = try fill("Body", of: "Demo", in: editable)
        #expect(string("type", of: demo.first) == "frame")
    }

    @Test("Every id the detached fills take is unique across the document")
    func detachedFillIDsAreUnique() throws {
        let editable = try editable()
        try editable.apply(deleteBtn)
        #expect(!fillRefs(in: editable).values.contains("Btn"), "the delete detached the fill instances")

        var ids = Array(editable.nodes.keys)
        for node in editable.nodes.values {
            guard case let .ref(data) = node.kind else { continue }
            for entry in (data.descendants ?? [:]).values {
                if case let .array(fill)? = entry.properties["children"] { ids += SlotJSON.allIDs(in: fill) }
            }
        }
        #expect(Set(ids).count == ids.count)
    }

    @Test("The inverse of a detaching delete puts every fill back as it was")
    func inverseRestoresFills() throws {
        let editable = try editable()
        let before = editable.materialize()
        let inverse = try editable.prepareInverse(of: deleteBtn)

        try editable.apply(deleteBtn)
        #expect(!fillRefs(in: editable).values.contains("Btn"), "the delete detached the fill instances")
        for step in inverse {
            try editable.apply(step)
        }

        #expect(editable.materialize() == before)
    }

    @Test("A detaching delete's change keys name each fill it rewrites")
    func changeKeysNameRewrittenFills() throws {
        let editable = try editable()
        let keys = try Set(ChangeKey.keys(of: deleteBtn, in: editable))

        #expect(keys.contains(.override(ref: "Inst", descendant: "Body", key: "children")))
        #expect(keys.contains(.override(ref: "Demo", descendant: "Body", key: "children")))
    }

    @Test("A collaborative detaching delete detaches fill instances on both peers")
    func collaborativeDeleteReplicates() throws {
        let peerA = try editable(peerID: PeerID(rawValue: "peerA"))
        let peerB = try editable(peerID: PeerID(rawValue: "peerB"))
        let before = peerA.materialize()
        let inverse = try peerA.prepareInverse(of: deleteBtn)

        let ops = try peerA.applyLocal(deleteBtn)
        peerB.applyRemote(ops)

        #expect(!fillRefs(in: peerA).values.contains("Btn"))
        #expect(peerB.materialize() == peerA.materialize())

        var undo: [CRDTOperation] = []
        for step in inverse {
            try undo.append(contentsOf: peerA.applyLocal(step))
        }
        peerB.applyRemote(undo)
        #expect(peerA.materialize() == before)
        #expect(peerB.materialize() == before)
    }

    @Test("A session's detaching delete undoes exactly")
    func sessionUndoesExactly() throws {
        let session = try DocumentSession(
            document: document(),
            author: Author(name: "ana", peerID: PeerID(rawValue: "peer-ana")),
            collaborative: false
        )
        let before = session.document.materialize()

        try session.submit(.local(LocalEdit(operations: [deleteBtn])))
        #expect(!fillRefs(in: session.document).values.contains("Btn"))

        try session.submit(.undo)
        #expect(session.document.materialize() == before)
    }

    @Test("A fill instance whose detach leads back to the deleted component through a fill drops the ref that closes the cycle")
    func cycleThroughAFillIsDropped() throws {
        // `Loop` holds `Hold`, a `Frame` instance whose slot holds `Loop` again; the page's
        // `Page` fills its own `Frame` slot with a `Loop`.
        let editable = try EditableDocument(from: PenParser.parse(Data(#"""
        {"version": "2.17", "children": [
          {"id": "Frm", "type": "frame", "name": "Frame", "reusable": true, "width": 100, "height": 100, "children": [
            {"id": "Hol", "name": "Hole", "type": "frame", "slot": ["ref"], "width": 80, "height": 80}]},
          {"id": "Loop", "type": "frame", "name": "Loop", "reusable": true, "width": 100, "height": 100, "children": [
            {"id": "LT", "type": "text", "name": "T", "content": "loop"},
            {"id": "Hold", "type": "ref", "name": "Hold", "ref": "Frm", "descendants": {
              "Hol": {"children": [{"id": "Back", "type": "ref", "name": "Back", "ref": "Loop"}]}}}]},
          {"id": "Page", "type": "ref", "name": "Page", "ref": "Frm", "descendants": {
            "Hol": {"children": [{"id": "PL", "type": "ref", "name": "PL", "ref": "Loop"}]}}}
        ]}
        """#.utf8)))

        try editable.allowingComponentLoops {
            try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "Loop", instances: .detach)))
        }

        #expect(!fillRefs(in: editable).values.contains("Loop"))
        let page = try fill("Hol", of: "Page", in: editable)
        #expect(string("type", of: page.first) == "frame", "the page's instance is detached")
        #expect(string("content", of: children(of: page.first).first) == "loop")
    }

    @Test("A batch rm --detach detaches the component's fill instances before deleting it")
    func batchRemoveDetachesFillInstances() throws {
        let editable = try editable()

        let report = try BatchApplier.apply(
            BatchOperation.decodeJSONL(#"{"op":"rm","target":"Btn","detach":true}"#), to: editable
        )

        #expect(report.lines.map(\.status) == [.applied])
        #expect(editable.nodes["Btn"] == nil)
        #expect(!fillRefs(in: editable).values.contains("Btn"))
    }
}
