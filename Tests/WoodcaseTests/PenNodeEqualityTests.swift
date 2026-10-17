//
//  PenNodeEqualityTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `PenNode`'s `==` and `hash(into:)` mean what the synthesized ones meant — every
/// stored property of every node in the tree, children in order — although they walk
/// the tree from a work list rather than recursing.
struct PenNodeEqualityTests {
    /// A small tree with something in every place a difference can hide: a frame payload
    /// field, a group, nested children, extras, a node of an unknown type, and a
    /// container that declares an empty list.
    private static func tree(
        leafName: String = "leaf",
        deepExtras: PenExtras = PenExtras(["custom": .string("kept")]),
        innerWidth: Double = 10,
        emptyChildren: [PenNode]? = [],
        swapSiblings: Bool = false,
        extraSibling: Bool = false
    ) -> PenNode {
        let leaf = PenNode(id: "leaf", common: PenNodeCommon(name: leafName), kind: .text(PenNode.TextData(content: .literal("hi"))))
        let unknown = PenNode(
            id: "odd",
            common: PenNodeCommon(),
            kind: .unknown(typeName: "video_clip", properties: ["src": .string("a.mp4")])
        )
        let deep = PenNode(
            id: "deep",
            common: PenNodeCommon(),
            kind: .group(PenNode.GroupData(children: [leaf, unknown])),
            extras: deepExtras
        )
        let empty = PenNode(id: "empty", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(children: emptyChildren)))
        var siblings = [deep, empty]
        if swapSiblings { siblings.reverse() }
        if extraSibling {
            siblings.append(PenNode(id: "more", common: PenNodeCommon(), kind: .ellipse(PenNode.EllipseData())))
        }
        let inner = PenNode(
            id: "inner",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(width: .fixed(innerWidth), children: siblings))
        )
        return PenNode(id: "root", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(children: [inner])))
    }

    @Test("Two trees built apart are equal and hash alike")
    func equalTrees() {
        let a = Self.tree()
        let b = Self.tree()

        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(Set([a, b]).count == 1)
    }

    @Test("A copy is equal to its original")
    func copy() {
        let a = Self.tree()
        let b = a

        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("A difference only in a deep leaf's property makes the trees unequal")
    func deepLeafProperty() {
        #expect(Self.tree() != Self.tree(leafName: "other"))
    }

    @Test("A difference only in a deep node's extras makes the trees unequal")
    func deepExtras() {
        #expect(Self.tree() != Self.tree(deepExtras: PenExtras(["custom": .string("changed")])))
        #expect(Self.tree() != Self.tree(deepExtras: PenExtras()))
    }

    @Test("A difference only in a container's own payload makes the trees unequal")
    func containerPayload() {
        #expect(Self.tree() != Self.tree(innerWidth: 11))
    }

    @Test("Children in another order make the trees unequal")
    func childOrder() {
        #expect(Self.tree() != Self.tree(swapSiblings: true))
    }

    @Test("Another child makes the trees unequal")
    func childCount() {
        #expect(Self.tree() != Self.tree(extraSibling: true))
        #expect(Self.tree(extraSibling: true) != Self.tree())
    }

    @Test("A container that declares no children differs from one that declares an empty list")
    func absentAgainstEmptyChildren() {
        #expect(Self.tree(emptyChildren: []) != Self.tree(emptyChildren: nil))
    }

    @Test("A frame and a group holding the same children are unequal")
    func containerKind() {
        let child = PenNode(id: "c", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let frame = PenNode(id: "n", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(children: [child])))
        let group = PenNode(id: "n", common: PenNodeCommon(), kind: .group(PenNode.GroupData(children: [child])))

        #expect(frame != group)
    }

    @Test("A container with children differs from a leaf that is otherwise the same")
    func containerAgainstLeaf() {
        let child = PenNode(id: "c", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let parent = PenNode(id: "n", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(children: [child])))
        let bare = PenNode(id: "n", common: PenNodeCommon(), kind: .frame(PenNode.FrameData()))

        #expect(parent != bare)
        #expect(bare != parent)
    }

    @Test("Equal trees decoded from the same JSON twice are equal and hash alike")
    func decodedTwice() throws {
        let data = try JSONEncoder().encode(Self.tree())
        let a = try JSONDecoder().decode(PenNode.self, from: data)
        let b = try JSONDecoder().decode(PenNode.self, from: data)

        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a == Self.tree())
    }

    /// The stored properties ``PenNode``'s `==`, `hash(into:)` and `customMirror` cover,
    /// in order.
    private struct CoveredProperties {
        let id: String
        var common: PenNodeCommon
        var storage: PenNode.KindStorage
        var extras: PenExtras
    }

    @Test("The node stores exactly the properties its equality, hash and mirror cover")
    func storedProperties() {
        // A new stored property changes the node's layout. It must join `==`,
        // `hash(into:)` (PenNode+Equatable.swift) and `customMirror` (PenNode.swift),
        // and then `CoveredProperties`.
        #expect(MemoryLayout<PenNode>.size == MemoryLayout<CoveredProperties>.size)
        #expect(MemoryLayout<PenNode>.offset(of: \.common) == MemoryLayout<CoveredProperties>.offset(of: \.common))
        #expect(MemoryLayout<PenNode>.offset(of: \.extras) == MemoryLayout<CoveredProperties>.offset(of: \.extras))
        #expect(MemoryLayout<PenNode.KindStorage>.size == MemoryLayout<Int>.size, "a gap a new property could hide in")
    }

    @Test("A node's mirror shows its kind, not the storage holding it")
    func mirror() {
        let labels = Mirror(reflecting: Self.tree()).children.compactMap(\.label)

        #expect(labels == ["id", "common", "kind", "extras"])
    }

    @Test("A childless kind and its copy are one box; equal kinds built apart are not, and still compare equal")
    func sameBox() {
        let kind = PenNode.Kind.text(PenNode.TextData(content: .literal("a")))
        let copy = kind
        let apart = PenNode.Kind.text(PenNode.TextData(content: .literal("a")))
        let other = PenNode.Kind.text(PenNode.TextData(content: .literal("b")))

        #expect(MemoryLayout<PenNode.Kind>.size == MemoryLayout<UInt>.size, "the shortcut is off")
        #expect(PenNode.Kind.sameBox(kind, copy))
        #expect(!PenNode.Kind.sameBox(kind, apart))
        #expect(!PenNode.Kind.sameBox(kind, other))
        #expect(kind == apart)
    }

    @Test("Two materializations of one editable document are equal and hash alike")
    func materializedTwice() {
        let document = EditableDocument(from: PenDocument(children: [Self.tree()]))
        let first = document.materialize().children
        let second = document.materialize().children

        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(first == [Self.tree()])
    }
}
