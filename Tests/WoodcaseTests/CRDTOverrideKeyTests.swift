//
//  CRDTOverrideKeyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An instance's overrides replicate one register per key — per descendant and key, and
/// per root-override key — so two people overriding different keys of one instance both
/// keep their work.
@MainActor
struct CRDTOverrideKeyTests {
    private func makePeers() -> (EditableDocument, EditableDocument) {
        let label = PenNode(id: "label", common: PenNodeCommon(name: "Label"), kind: .text(PenNode.TextData()))
        let icon = PenNode(id: "icon", common: PenNodeCommon(name: "Icon"), kind: .rectangle(PenNode.RectangleData()))
        let dotted = PenNode(id: "dot.ted", common: PenNodeCommon(name: "Dotted"), kind: .rectangle(PenNode.RectangleData()))
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [label, icon, dotted]))
        )
        let ref = PenNode(id: "ref1", common: PenNodeCommon(), kind: .ref(PenNode.RefData(ref: "comp1")))
        let doc = PenDocument(children: [component, ref])
        return (
            EditableDocument(from: doc, peerID: PeerID(rawValue: "peerA")),
            EditableDocument(from: doc, peerID: PeerID(rawValue: "peerB"))
        )
    }

    private func override(_ descendant: String, _ properties: [String: AnyCodable], unset: [String] = []) -> EditOperation {
        .overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1", descendantID: descendant, properties: properties, unset: unset
        ))
    }

    private func refData(_ doc: EditableDocument) -> PenNode.RefData? {
        guard case let .ref(data) = doc.nodes["ref1"]?.kind else { return nil }
        return data
    }

    @Test("one override write replicates as one operation per key it changed")
    func oneOperationPerKey() throws {
        let (a, _) = makePeers()
        let ops = try a.applyLocal(override("label", ["name": "OK", "opacity": 0.5]))
        let paths = ops.compactMap { op -> String? in
            if case let .setProperty(p) = op.payload { p.property } else { nil }
        }
        #expect(paths.sorted() == ["kind.descendants.label.name", "kind.descendants.label.opacity"])
    }

    @Test("two peers overriding different keys of one descendant both keep their key")
    func differentKeysOfOneDescendantSurvive() throws {
        let (a, b) = makePeers()
        let fromA = try a.applyLocal(override("label", ["name": "OK"]))
        let fromB = try b.applyLocal(override("label", ["opacity": 0.5]))
        a.applyRemote(fromB)
        b.applyRemote(fromA)

        let properties = refData(a)?.descendants?["label"]?.properties
        #expect(properties?["name"] == "OK")
        #expect(properties?["opacity"] == 0.5)
        #expect(refData(a) == refData(b))
    }

    @Test("two peers overriding different descendants both keep theirs")
    func differentDescendantsSurvive() throws {
        let (a, b) = makePeers()
        let fromA = try a.applyLocal(override("label", ["name": "OK"]))
        let fromB = try b.applyLocal(override("icon", ["name": "Star"]))
        a.applyRemote(fromB)
        b.applyRemote(fromA)

        #expect(refData(a)?.descendants?["label"]?.properties["name"] == "OK")
        #expect(refData(a)?.descendants?["icon"]?.properties["name"] == "Star")
        #expect(refData(a) == refData(b))
    }

    @Test("unsetting an override key replicates, and the emptied descendant goes")
    func unsetReplicates() throws {
        let (a, b) = makePeers()
        try b.applyRemote(a.applyLocal(override("label", ["name": "OK"])))
        try b.applyRemote(a.applyLocal(override("label", [:], unset: ["name"])))

        #expect(refData(a)?.descendants == nil)
        #expect(refData(b)?.descendants == nil)
    }

    @Test("a whole descendants map written through kind.descendants replicates per key")
    func wholeMapWriteIsPerKey() throws {
        let (a, b) = makePeers()
        let fromA = try a.applyLocal(.setProperties(EditOperation.SetProperties(
            nodeID: "ref1", properties: ["kind.descendants": ["label": ["name": "OK"]]]
        )))
        let fromB = try b.applyLocal(override("label", ["opacity": 0.5]))
        a.applyRemote(fromB)
        b.applyRemote(fromA)

        let properties = refData(b)?.descendants?["label"]?.properties
        #expect(properties?["name"] == "OK")
        #expect(properties?["opacity"] == 0.5)
        #expect(refData(a) == refData(b))
    }

    @Test("two peers writing different root-override keys both keep theirs")
    func rootOverrideKeysSurvive() throws {
        let (a, b) = makePeers()
        let fromA = try a.applyLocal(.overrideRoot(EditOperation.OverrideRoot(
            refNodeID: "ref1", properties: ["kind.width": 120]
        )))
        let fromB = try b.applyLocal(.overrideRoot(EditOperation.OverrideRoot(
            refNodeID: "ref1", properties: ["kind.height": 40]
        )))
        a.applyRemote(fromB)
        b.applyRemote(fromA)

        #expect(a.nodes["ref1"] == b.nodes["ref1"])
        #expect(refData(a)?.rootOverrides?.count == 2)
    }

    @Test("an override key with a dot in its descendant id round-trips")
    func escapedDescendantID() throws {
        let (a, b) = makePeers()
        try b.applyRemote(a.applyLocal(override("dot.ted", ["name": "OK"])))
        #expect(refData(b)?.descendants?["dot.ted"]?.properties["name"] == "OK")
    }
}
