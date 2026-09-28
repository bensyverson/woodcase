//
//  PenNodeEditingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct PenNodeEditingTests {
    // MARK: - withEmptyChildren

    @Test("withEmptyChildren on frame with children returns frame with nil children")
    func withEmptyChildrenOnFrame() {
        let child = PenNode(id: "child", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let frameData = PenNode.FrameData(children: [child])
        let kind = PenNode.Kind.frame(frameData)

        let stripped = kind.withEmptyChildren()

        if case let .frame(data) = stripped {
            #expect(data.children == nil)
            // Other properties preserved
            #expect(data.width == frameData.width)
        } else {
            Issue.record("Expected frame kind")
        }
    }

    @Test("withEmptyChildren on group with children returns group with nil children")
    func withEmptyChildrenOnGroup() {
        let child = PenNode(id: "child", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let groupData = PenNode.GroupData(children: [child])
        let kind = PenNode.Kind.group(groupData)

        let stripped = kind.withEmptyChildren()

        if case let .group(data) = stripped {
            #expect(data.children == nil)
        } else {
            Issue.record("Expected group kind")
        }
    }

    @Test("withEmptyChildren on text node returns identical kind")
    func withEmptyChildrenOnText() {
        let textData = PenNode.TextData(fontFamily: .literal("Arial"))
        let kind = PenNode.Kind.text(textData)

        let result = kind.withEmptyChildren()

        #expect(result == kind)
    }

    @Test("withEmptyChildren on rectangle returns identical kind")
    func withEmptyChildrenOnRectangle() {
        let kind = PenNode.Kind.rectangle(PenNode.RectangleData())
        let result = kind.withEmptyChildren()
        #expect(result == kind)
    }

    // MARK: - withChildren

    @Test("withChildren on frame sets children")
    func withChildrenOnFrame() {
        let frameData = PenNode.FrameData()
        let kind = PenNode.Kind.frame(frameData)
        let child = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))

        let result = kind.withChildren([child])

        if case let .frame(data) = result {
            #expect(data.children?.count == 1)
            #expect(data.children?.first?.id == "c1")
        } else {
            Issue.record("Expected frame kind")
        }
    }

    @Test("withChildren on group sets children")
    func withChildrenOnGroup() {
        let groupData = PenNode.GroupData()
        let kind = PenNode.Kind.group(groupData)
        let child = PenNode(id: "c1", common: PenNodeCommon(), kind: .text(PenNode.TextData()))

        let result = kind.withChildren([child])

        if case let .group(data) = result {
            #expect(data.children?.count == 1)
            #expect(data.children?.first?.id == "c1")
        } else {
            Issue.record("Expected group kind")
        }
    }

    @Test("withChildren on text node is a no-op")
    func withChildrenOnText() {
        let kind = PenNode.Kind.text(PenNode.TextData())
        let child = PenNode(id: "c1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))

        let result = kind.withChildren([child])

        #expect(result == kind)
    }

    // MARK: - canHaveChildren

    @Test("canHaveChildren returns true for frame and group only")
    func canHaveChildren() {
        let containerKinds: [PenNode.Kind] = [
            .frame(PenNode.FrameData()),
            .group(PenNode.GroupData()),
        ]
        let leafKinds: [PenNode.Kind] = [
            .text(PenNode.TextData()),
            .rectangle(PenNode.RectangleData()),
            .ellipse(PenNode.EllipseData()),
            .path(PenNode.PathData()),
            .line(PenNode.LineData()),
            .polygon(PenNode.PolygonData()),
            .ref(PenNode.RefData(ref: "someRef")),
            .note(PenNode.NoteData()),
            .prompt(PenNode.PromptData()),
            .context(PenNode.ContextData()),
            .icon(PenNode.IconData()),
            .unknown(typeName: "custom", properties: [:]),
        ]

        for kind in containerKinds {
            #expect(kind.canHaveChildren, "Expected \(kind) to support children")
        }
        for kind in leafKinds {
            #expect(!kind.canHaveChildren, "Expected \(kind) to NOT support children")
        }
    }

    // MARK: - childIDs

    @Test("childIDs returns IDs from frame's inline children")
    func childIDsFrame() {
        let c1 = PenNode(id: "a", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let c2 = PenNode(id: "b", common: PenNodeCommon(), kind: .text(PenNode.TextData()))
        let kind = PenNode.Kind.frame(PenNode.FrameData(children: [c1, c2]))

        #expect(kind.childIDs == ["a", "b"])
    }

    @Test("childIDs returns IDs from group's inline children")
    func childIDsGroup() {
        let c1 = PenNode(id: "x", common: PenNodeCommon(), kind: .ellipse(PenNode.EllipseData()))
        let kind = PenNode.Kind.group(PenNode.GroupData(children: [c1]))

        #expect(kind.childIDs == ["x"])
    }

    @Test("childIDs returns empty array for leaf nodes")
    func childIDsLeaf() {
        let kind = PenNode.Kind.rectangle(PenNode.RectangleData())
        #expect(kind.childIDs == [])
    }

    @Test("childIDs returns empty array for container with nil children")
    func childIDsNilChildren() {
        let kind = PenNode.Kind.frame(PenNode.FrameData(children: nil))
        #expect(kind.childIDs == [])
    }
}
