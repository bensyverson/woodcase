//
//  PropMapperTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct PropMapperTests {
    // MARK: - Helpers

    private func makeComponent(
        props: [PropDefinition],
        id: String = "comp1",
        name: String = "TestComponent"
    ) -> ComponentDefinition {
        ComponentDefinition(
            id: id,
            name: name,
            sourceNode: PenNode(
                id: id,
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData())
            ),
            props: props,
            actions: [],
            bindings: []
        )
    }

    // MARK: - String Props

    @Test("Maps string override (content) to a string value")
    func mapsStringOverride() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "title",
                path: "Title",
                type: .string,
                defaultValue: .string("Default"),
                targetNodeID: "V:title1"
            ),
        ])

        let overrides: [String: PenDescendantOverride] = [
            "V:title1": PenDescendantOverride(properties: [
                "content": .string("Custom Title"),
            ]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.count == 1)
        #expect(result[0].name == "title")
        #expect(result[0].value == .string("Custom Title"))
    }

    // MARK: - Color Props

    @Test("Maps color override with shorthand hex fill")
    func mapsColorShorthandOverride() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "bg",
                path: "Background",
                type: .color,
                defaultValue: .string("#000000"),
                targetNodeID: "V:bg1"
            ),
        ])

        let overrides: [String: PenDescendantOverride] = [
            "V:bg1": PenDescendantOverride(properties: [
                "fill": .string("#FF5500"),
            ]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.count == 1)
        #expect(result[0].name == "bg")
        #expect(result[0].value == .color(.literal("#FF5500")))
    }

    @Test("Maps color override with variable fill")
    func mapsColorVariableOverride() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "bg",
                path: "Background",
                type: .color,
                defaultValue: nil,
                targetNodeID: "V:bg1"
            ),
        ])

        let overrides: [String: PenDescendantOverride] = [
            "V:bg1": PenDescendantOverride(properties: [
                "fill": .dictionary([
                    "type": .string("color"),
                    "color": .string("$primary"),
                ]),
            ]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.count == 1)
        #expect(result[0].name == "bg")
        #expect(result[0].value == .color(.variable("primary")))
    }

    @Test("Maps color override with a shorthand variable fill")
    func mapsShorthandVariableOverride() {
        let component = makeComponent(props: [
            PropDefinition(name: "bg", path: "Background", type: .color, defaultValue: nil, targetNodeID: "V:bg1"),
        ])
        let overrides: [String: PenDescendantOverride] = [
            "V:bg1": PenDescendantOverride(properties: ["fill": .string("$accent")]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.map(\.value) == [.color(.variable("accent"))])
    }

    @Test("Maps color override with literal color fill object")
    func mapsColorLiteralFillObject() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "bg",
                path: "Background",
                type: .color,
                defaultValue: nil,
                targetNodeID: "V:bg1"
            ),
        ])

        let overrides: [String: PenDescendantOverride] = [
            "V:bg1": PenDescendantOverride(properties: [
                "fill": .dictionary([
                    "type": .string("color"),
                    "color": .string("#AABBCC"),
                ]),
            ]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.count == 1)
        #expect(result[0].name == "bg")
        #expect(result[0].value == .color(.literal("#AABBCC")))
    }

    // MARK: - Boolean Props

    @Test("Maps boolean override from enabled property")
    func mapsBooleanOverride() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "visible",
                path: "Badge",
                type: .boolean,
                defaultValue: nil,
                targetNodeID: "V:badge1"
            ),
        ])

        let overrides: [String: PenDescendantOverride] = [
            "V:badge1": PenDescendantOverride(properties: [
                "enabled": .bool(false),
            ]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.count == 1)
        #expect(result[0].name == "visible")
        #expect(result[0].value == .boolean(false))
    }

    // MARK: - Image Props

    @Test("Maps imageURL override from image fill")
    func mapsImageURLOverride() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "image",
                path: "Thumbnail",
                type: .imageURL,
                defaultValue: nil,
                targetNodeID: "V:thumb1"
            ),
        ])

        let overrides: [String: PenDescendantOverride] = [
            "V:thumb1": PenDescendantOverride(properties: [
                "fill": .dictionary([
                    "type": .string("image"),
                    "url": .string("./images/photo.png"),
                ]),
            ]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.count == 1)
        #expect(result[0].name == "image")
        #expect(result[0].value == .imageURL("./images/photo.png"))
    }

    // MARK: - Edge Cases

    @Test("Returns empty array when no overrides match component props")
    func noMatchReturnsEmpty() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "title",
                path: "Title",
                type: .string,
                defaultValue: nil,
                targetNodeID: "V:title1"
            ),
        ])

        let overrides: [String: PenDescendantOverride] = [
            "V:unrelated": PenDescendantOverride(properties: [
                "content": .string("Something"),
            ]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.isEmpty)
    }

    @Test("Maps multiple overrides simultaneously")
    func mapsMultipleOverrides() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "title",
                path: "Title",
                type: .string,
                defaultValue: .string("Default"),
                targetNodeID: "V:title1"
            ),
            PropDefinition(
                name: "subtitle",
                path: "Subtitle",
                type: .string,
                defaultValue: .string("Sub"),
                targetNodeID: "V:sub1"
            ),
        ])

        let overrides: [String: PenDescendantOverride] = [
            "V:title1": PenDescendantOverride(properties: [
                "content": .string("New Title"),
            ]),
            "V:sub1": PenDescendantOverride(properties: [
                "content": .string("New Sub"),
            ]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.count == 2)
        let sorted = result.sorted { $0.name < $1.name }
        #expect(sorted[0].name == "subtitle")
        #expect(sorted[0].value == .string("New Sub"))
        #expect(sorted[1].name == "title")
        #expect(sorted[1].value == .string("New Title"))
    }
}
