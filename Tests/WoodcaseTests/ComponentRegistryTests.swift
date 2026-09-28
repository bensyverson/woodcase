//
//  ComponentRegistryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct ComponentRegistryTests {
    // MARK: - Init Population

    @Test("Init from document with reusable components populates registry")
    func initWithReusables() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [
                PenNode(id: "label", common: PenNodeCommon(), kind: .text(PenNode.TextData())),
            ]))
        )
        let regular = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData())
        )
        let doc = PenDocument(children: [component, regular])
        let editable = EditableDocument(from: doc)

        #expect(editable.componentRegistry.count == 1)
        #expect(editable.componentRegistry["comp1"] != nil)
        #expect(editable.componentRegistry["comp1"]?.common.name == "Button")
        #expect(editable.componentRegistry["rect1"] == nil)
    }

    @Test("Init from empty document has empty registry")
    func initEmpty() {
        let doc = PenDocument(children: [])
        let editable = EditableDocument(from: doc)
        #expect(editable.componentRegistry.isEmpty)
    }

    @Test("Init with CRDT mode populates registry")
    func initWithCRDT() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Card", reusable: true),
            kind: .frame(PenNode.FrameData())
        )
        let doc = PenDocument(children: [component])
        let editable = EditableDocument(from: doc, peerID: PeerID(rawValue: "test-peer"))

        #expect(editable.componentRegistry.count == 1)
        #expect(editable.componentRegistry["comp1"] != nil)
    }

    // MARK: - Insert Reusable

    @Test("Inserting a reusable node adds it to registry")
    func insertReusable() throws {
        let doc = PenDocument(children: [])
        let editable = EditableDocument(from: doc)

        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData())
        )
        try editable.apply(.insertNode(EditOperation.InsertNode(node: component)))

        #expect(editable.componentRegistry["comp1"] != nil)
    }

    @Test("Inserting a non-reusable node does not affect registry")
    func insertNonReusable() throws {
        let doc = PenDocument(children: [])
        let editable = EditableDocument(from: doc)

        let regular = PenNode(
            id: "r1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData())
        )
        try editable.apply(.insertNode(EditOperation.InsertNode(node: regular)))

        #expect(editable.componentRegistry.isEmpty)
    }

    // MARK: - Update Reusable Flag

    @Test("Setting reusable to false removes from registry")
    func setReusableFalse() throws {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData())
        )
        let doc = PenDocument(children: [component])
        let editable = EditableDocument(from: doc)

        #expect(editable.componentRegistry["comp1"] != nil)

        try editable.apply(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "comp1",
            common: PenNodeCommon(name: "Button", reusable: false)
        )))

        #expect(editable.componentRegistry["comp1"] == nil)
    }

    @Test("Setting reusable to true adds to registry")
    func setReusableTrue() throws {
        let regular = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Box"),
            kind: .frame(PenNode.FrameData())
        )
        let doc = PenDocument(children: [regular])
        let editable = EditableDocument(from: doc)

        #expect(editable.componentRegistry.isEmpty)

        try editable.apply(.updateCommon(EditOperation.UpdateCommon(
            nodeID: "r1",
            common: PenNodeCommon(name: "Box", reusable: true)
        )))

        #expect(editable.componentRegistry["r1"] != nil)
    }

    // MARK: - Delete Reusable

    @Test("Deleting a reusable node removes it from registry")
    func deleteReusable() throws {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData())
        )
        let doc = PenDocument(children: [component])
        let editable = EditableDocument(from: doc)

        #expect(editable.componentRegistry["comp1"] != nil)

        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "comp1")))

        #expect(editable.componentRegistry["comp1"] == nil)
    }

    // MARK: - CRDT Mutations

    @Test("Remote setNode mutation updates registry")
    func remoteSetNodeUpdatesRegistry() {
        let doc = PenDocument(children: [])
        let editable = EditableDocument(from: doc, peerID: PeerID(rawValue: "test-peer"))

        // Simulate a remote mutation that sets a reusable node
        let node = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Card", reusable: true),
            kind: .frame(PenNode.FrameData())
        )
        editable.applyMutation(.setNode(node))

        #expect(editable.componentRegistry["comp1"] != nil)
    }

    @Test("Remote removeNode mutation clears registry entry")
    func remoteRemoveNodeClearsRegistry() {
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData())
        )
        let doc = PenDocument(children: [component])
        let editable = EditableDocument(from: doc, peerID: PeerID(rawValue: "test-peer"))

        #expect(editable.componentRegistry["comp1"] != nil)

        editable.applyMutation(.removeNode(nodeID: "comp1"))

        #expect(editable.componentRegistry["comp1"] == nil)
    }
}
