//
//  PropMapperSharedTargetTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// What ``PropMapper`` does when several of a component's props name the *same*
/// descendant.
///
/// One descendant carrying several props is legitimate — a `label` reading a text
/// node's content and a `tint` reading its fill are two different readings of one node —
/// so the node-id lookup is one-to-many and the mapper emits one attribute per prop that
/// finds a value in the override. Two props of the *same* type read the same field and
/// are ambiguous; the mapper keeps the first by prop name so an ambiguous file emits
/// something rather than emitting the same value twice, and `lint` reports the ambiguity
/// under `codegen-prop-path`.
struct PropMapperSharedTargetTests {
    // MARK: - Helpers

    private func makeComponent(props: [PropDefinition]) -> ComponentDefinition {
        ComponentDefinition(
            id: "comp1",
            name: "StatCard",
            sourceNode: PenNode(
                id: "comp1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData())
            ),
            props: props,
            actions: [],
            bindings: []
        )
    }

    // MARK: - Several props, one node

    @Test("Two props of different types on one node both map")
    func differentTypesOnOneNodeBothMap() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "label", path: "Body/Title", type: .string,
                defaultValue: .string("Total"), targetNodeID: "Ttl01"
            ),
            PropDefinition(
                name: "tint", path: "Body/Title", type: .color,
                defaultValue: .string("#000000"), targetNodeID: "Ttl01"
            ),
        ])
        let overrides: [String: PenDescendantOverride] = [
            "Ttl01": PenDescendantOverride(properties: [
                "content": .string("Hello"),
                "fill": .string("#FFD166"),
            ]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.map(\.name) == ["label", "tint"])
        #expect(result.first { $0.name == "label" }?.value == .string("Hello"))
        #expect(result.first { $0.name == "tint" }?.value == .color(.literal("#FFD166")))
    }

    @Test("A prop whose field the override does not carry is skipped, the other still maps")
    func onlyThePropWithAValueMaps() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "label", path: "Body/Title", type: .string,
                defaultValue: .string("Total"), targetNodeID: "Ttl01"
            ),
            PropDefinition(
                name: "tint", path: "Body/Title", type: .color,
                defaultValue: .string("#000000"), targetNodeID: "Ttl01"
            ),
        ])
        let overrides: [String: PenDescendantOverride] = [
            "Ttl01": PenDescendantOverride(properties: ["content": .string("Hello")]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.map(\.name) == ["label"])
    }

    // MARK: - The ambiguous case

    @Test("Two props of the same type on one node map once, keeping the first by name")
    func sameTypeOnOneNodeKeepsTheFirstByName() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "label", path: "Body/Title", type: .string,
                defaultValue: .string("Total"), targetNodeID: "Ttl01"
            ),
            PropDefinition(
                name: "width", path: "Body/Title", type: .string,
                defaultValue: .string("Total"), targetNodeID: "Ttl01"
            ),
        ])
        let overrides: [String: PenDescendantOverride] = [
            "Ttl01": PenDescendantOverride(properties: ["content": .string("Hello")]),
        ]

        let result = PropMapper.map(overrides: overrides, to: component)

        #expect(result.map(\.name) == ["label"])
        #expect(result[0].value == .string("Hello"))
    }

    @Test("The prop kept is the first by name, whatever order the definitions arrive in")
    func theKeptPropDoesNotDependOnDefinitionOrder() {
        let width = PropDefinition(
            name: "width", path: "Body/Title", type: .string,
            defaultValue: .string("Total"), targetNodeID: "Ttl01"
        )
        let label = PropDefinition(
            name: "label", path: "Body/Title", type: .string,
            defaultValue: .string("Total"), targetNodeID: "Ttl01"
        )
        let overrides: [String: PenDescendantOverride] = [
            "Ttl01": PenDescendantOverride(properties: ["content": .string("Hello")]),
        ]

        #expect(PropMapper.map(overrides: overrides, to: makeComponent(props: [width, label]))
            .map(\.name) == ["label"])
        #expect(PropMapper.map(overrides: overrides, to: makeComponent(props: [label, width]))
            .map(\.name) == ["label"])
    }

    // MARK: - The lookup itself

    @Test("propsByNodeID groups every prop that names a node, in prop-name order")
    func propsByNodeIDGroups() {
        let component = makeComponent(props: [
            PropDefinition(
                name: "width", path: "Body/Title", type: .string,
                defaultValue: nil, targetNodeID: "Ttl01"
            ),
            PropDefinition(
                name: "label", path: "Body/Title", type: .string,
                defaultValue: nil, targetNodeID: "Ttl01"
            ),
            PropDefinition(
                name: "tint", path: "Body/Swatch", type: .color,
                defaultValue: nil, targetNodeID: "Swt01"
            ),
            PropDefinition(
                name: "gone", path: "Body/Missing", type: .string,
                defaultValue: nil, targetNodeID: nil
            ),
        ])

        let lookup = component.propsByNodeID

        #expect(lookup["Ttl01"]?.map(\.name) == ["label", "width"])
        #expect(lookup["Swt01"]?.map(\.name) == ["tint"])
        #expect(lookup["nonexistent"] == nil)
        #expect(lookup.count == 2)
    }
}
