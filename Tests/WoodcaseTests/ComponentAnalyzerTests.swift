//
//  ComponentAnalyzerTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct ComponentAnalyzerTests {
    // MARK: - Helpers

    private func makeDocument(children: [PenNode] = []) -> PenDocument {
        PenDocument(version: "2.9", children: children)
    }

    private func makeFrame(
        id: String = "frame1",
        name: String? = nil,
        reusable: Bool? = nil,
        metadata: PenMetadata? = nil,
        layout: PenLayoutDirection? = nil,
        fills: PenFills? = nil,
        children: [PenNode]? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name, reusable: reusable, metadata: metadata),
            kind: .frame(PenNode.FrameData(fills: fills, layout: layout, children: children))
        )
    }

    private func makeText(
        id: String = "text1",
        name: String? = nil,
        metadata: PenMetadata? = nil,
        content: String = "Hello"
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name, metadata: metadata),
            kind: .text(PenNode.TextData(content: .literal(content)))
        )
    }

    // MARK: - Basic Component Detection

    @Test("Finds reusable nodes as components")
    func findsReusableNodes() {
        let doc = makeDocument(children: [
            makeFrame(
                id: "comp1",
                name: "Component/My Widget",
                reusable: true,
                metadata: ["type": "component"]
            ),
            makeFrame(id: "regular", name: "Not a component"),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components.count == 1)
        #expect(components[0].id == "comp1")
    }

    @Test("Non-reusable nodes are excluded")
    func excludesNonReusable() {
        let doc = makeDocument(children: [
            makeFrame(id: "a", name: "Regular Frame"),
            makeText(id: "b", name: "Regular Text"),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components.isEmpty)
    }

    // MARK: - Name Sanitization

    @Test("Strips Component/ prefix and PascalCases name")
    func sanitizesName() {
        let doc = makeDocument(children: [
            makeFrame(
                id: "c1",
                name: "Component/Stat Card",
                reusable: true,
                metadata: ["type": "component"]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].name == "StatCard")
    }

    @Test("Sanitizes nested component prefix")
    func sanitizesNestedPrefix() {
        let doc = makeDocument(children: [
            makeFrame(
                id: "c1",
                name: "Component/Tab Bar/Home Active",
                reusable: true,
                metadata: ["type": "component"]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].name == "TabBarHomeActive")
    }

    @Test("Handles name without Component/ prefix")
    func handlesNoPrefix() {
        let doc = makeDocument(children: [
            makeFrame(id: "c1", name: "Usage Log", reusable: true),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].name == "UsageLog")
    }

    // MARK: - Props

    @Test("Extracts props from _props metadata")
    func extractsProps() {
        let valueText = makeText(id: "t1", name: "Value", content: "142h")
        let labelText = makeText(id: "t2", name: "Label", content: "Total Hours")

        let doc = makeDocument(children: [
            makeFrame(
                id: "sc",
                name: "Component/Stat Card",
                reusable: true,
                metadata: [
                    "type": "component",
                    "_props": .dictionary([
                        "value": .string("Value"),
                        "label": .string("Label"),
                    ]),
                ],
                children: [valueText, labelText]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].props.count == 2)
        let valueProp = components[0].props.first { $0.name == "value" }
        #expect(valueProp?.type == .string)
        #expect(valueProp?.path == "Value")
        #expect(valueProp?.defaultValue == .string("142h"))

        let labelProp = components[0].props.first { $0.name == "label" }
        #expect(labelProp?.type == .string)
        #expect(labelProp?.defaultValue == .string("Total Hours"))
    }

    @Test("Resolves nested prop paths")
    func nestedPropPaths() {
        let nameText = makeText(id: "t1", name: "Name", content: "Pencil A")
        let infoFrame = makeFrame(
            id: "info",
            name: "Info",
            children: [nameText]
        )

        let doc = makeDocument(children: [
            makeFrame(
                id: "comp",
                name: "Component/List Item",
                reusable: true,
                metadata: [
                    "type": "component",
                    "_props": .dictionary([
                        "name": .string("Info/Name"),
                    ]),
                ],
                children: [infoFrame]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].props.count == 1)
        let nameProp = components[0].props[0]
        #expect(nameProp.name == "name")
        #expect(nameProp.path == "Info/Name")
        #expect(nameProp.type == .string)
        #expect(nameProp.defaultValue == .string("Pencil A"))
    }

    @Test("Infers color prop type from node with color fill")
    func colorPropType() {
        let colorRect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Background"),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )

        let doc = makeDocument(children: [
            makeFrame(
                id: "comp",
                name: "Component/Card",
                reusable: true,
                metadata: [
                    "type": "component",
                    "_props": .dictionary(["bg": .string("Background")]),
                ],
                children: [colorRect]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].props[0].type == .color)
        #expect(components[0].props[0].defaultValue == .string("#FF0000"))
    }

    @Test("Infers imageURL prop type from node with image fill")
    func imagePropType() {
        let imageNode = PenNode(
            id: "img1",
            common: PenNodeCommon(name: "Thumbnail"),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.image(PenFill.PenImageFill(url: "photo.jpg")))
            ))
        )

        let doc = makeDocument(children: [
            makeFrame(
                id: "comp",
                name: "Component/Card",
                reusable: true,
                metadata: [
                    "type": "component",
                    "_props": .dictionary(["image": .string("Thumbnail")]),
                ],
                children: [imageNode]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].props[0].type == .imageURL)
        #expect(components[0].props[0].defaultValue == .string("photo.jpg"))
    }

    // MARK: - Actions

    @Test("Extracts action from _role + _action metadata")
    func extractsExplicitAction() {
        let button = makeFrame(
            id: "btn1",
            name: "Submit Button",
            metadata: ["_role": .string("button"), "_action": .string("submit")]
        )

        let doc = makeDocument(children: [
            makeFrame(
                id: "comp",
                name: "Component/Form",
                reusable: true,
                metadata: ["type": "component"],
                children: [button]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].actions.count == 1)
        #expect(components[0].actions[0].name == "submit")
        #expect(components[0].actions[0].role == "button")
        #expect(components[0].actions[0].nodeID == "btn1")
    }

    @Test("Generates default action for button role without _action")
    func defaultButtonAction() {
        let button = makeFrame(
            id: "btn1",
            name: "Press Me",
            metadata: ["_role": .string("button")]
        )

        let doc = makeDocument(children: [
            makeFrame(
                id: "comp",
                name: "Component/Card",
                reusable: true,
                metadata: ["type": "component"],
                children: [button]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].actions.count == 1)
        #expect(components[0].actions[0].name == "click")
        #expect(components[0].actions[0].role == "button")
    }

    @Test("Action from component root _role metadata")
    func rootRoleAction() {
        let doc = makeDocument(children: [
            makeFrame(
                id: "btn",
                name: "Component/Action Button",
                reusable: true,
                metadata: [
                    "type": "component",
                    "_role": .string("button"),
                    "_props": .dictionary(["label": .string("Label")]),
                ],
                children: [makeText(id: "lbl", name: "Label", content: "Submit")]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].actions.count == 1)
        #expect(components[0].actions[0].name == "click")
        #expect(components[0].actions[0].role == "button")
        #expect(components[0].actions[0].nodeID == "btn")
    }

    // MARK: - Bindings

    @Test("Extracts binding from _role textInput")
    func extractsTextInputBinding() {
        let field = makeFrame(
            id: "field1",
            name: "Field",
            metadata: ["_role": .string("textInput")]
        )

        let doc = makeDocument(children: [
            makeFrame(
                id: "comp",
                name: "Component/Text Input",
                reusable: true,
                metadata: ["type": "component"],
                children: [field]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].bindings.count == 1)
        #expect(components[0].bindings[0].name == "field")
        #expect(components[0].bindings[0].role == "textInput")
        #expect(components[0].bindings[0].nodeID == "field1")
        #expect(components[0].bindings[0].valueType == .string)
    }

    @Test("Extracts binding from toggle role")
    func extractsToggleBinding() {
        let toggle = makeFrame(
            id: "tog1",
            name: "Track",
            metadata: ["_role": .string("toggle")]
        )

        let doc = makeDocument(children: [
            makeFrame(
                id: "comp",
                name: "Component/Toggle Row",
                reusable: true,
                metadata: ["type": "component"],
                children: [toggle]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].bindings.count == 1)
        #expect(components[0].bindings[0].name == "track")
        #expect(components[0].bindings[0].role == "toggle")
        #expect(components[0].bindings[0].valueType == .boolean)
    }

    // MARK: - ID-to-Name Bridge

    @Test("Props have targetNodeID populated from resolved descendant")
    func propsHaveTargetNodeID() {
        let valueText = makeText(id: "V:abc123", name: "Value", content: "142h")
        let labelText = makeText(id: "V:def456", name: "Label", content: "Total Hours")

        let doc = makeDocument(children: [
            makeFrame(
                id: "sc",
                name: "Component/Stat Card",
                reusable: true,
                metadata: [
                    "type": "component",
                    "_props": .dictionary([
                        "value": .string("Value"),
                        "label": .string("Label"),
                    ]),
                ],
                children: [valueText, labelText]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        let valueProp = components[0].props.first { $0.name == "value" }
        #expect(valueProp?.targetNodeID == "V:abc123")

        let labelProp = components[0].props.first { $0.name == "label" }
        #expect(labelProp?.targetNodeID == "V:def456")
    }

    @Test("Props with unresolvable paths have nil targetNodeID")
    func unresolvedPathHasNilTargetNodeID() {
        let doc = makeDocument(children: [
            makeFrame(
                id: "comp",
                name: "Component/Card",
                reusable: true,
                metadata: [
                    "type": "component",
                    "_props": .dictionary(["title": .string("NonExistent")]),
                ],
                children: []
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].props[0].targetNodeID == nil)
    }

    @Test("propsByNodeID maps node IDs to the props that read them")
    func propsByNodeIDLookup() {
        let valueText = makeText(id: "V:abc123", name: "Value", content: "142h")
        let labelText = makeText(id: "V:def456", name: "Label", content: "Total Hours")

        let doc = makeDocument(children: [
            makeFrame(
                id: "sc",
                name: "Component/Stat Card",
                reusable: true,
                metadata: [
                    "type": "component",
                    "_props": .dictionary([
                        "value": .string("Value"),
                        "label": .string("Label"),
                    ]),
                ],
                children: [valueText, labelText]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)
        let lookup = components[0].propsByNodeID

        #expect(lookup["V:abc123"]?.map(\.name) == ["value"])
        #expect(lookup["V:def456"]?.map(\.name) == ["label"])
        #expect(lookup["nonexistent"] == nil)
    }

    @Test("Nested prop path resolves targetNodeID correctly")
    func nestedPathTargetNodeID() {
        let nameText = makeText(id: "V:nested789", name: "Name", content: "Pencil A")
        let infoFrame = makeFrame(
            id: "info",
            name: "Info",
            children: [nameText]
        )

        let doc = makeDocument(children: [
            makeFrame(
                id: "comp",
                name: "Component/List Item",
                reusable: true,
                metadata: [
                    "type": "component",
                    "_props": .dictionary([
                        "name": .string("Info/Name"),
                    ]),
                ],
                children: [infoFrame]
            ),
        ])

        let components = ComponentAnalyzer.analyze(doc)

        #expect(components[0].props[0].targetNodeID == "V:nested789")
        #expect(components[0].propsByNodeID["V:nested789"]?.map(\.name) == ["name"])
    }

    @Test("Integration: woodcase-app.pen props have targetNodeIDs")
    func integrationTargetNodeIDs() throws {
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let components = ComponentAnalyzer.analyze(doc)

        let statCard = try #require(components.first { $0.name == "StatCard" })

        // All props should have resolved targetNodeIDs
        for prop in statCard.props {
            #expect(prop.targetNodeID != nil, "Prop '\(prop.name)' should have a targetNodeID")
        }

        // propsByNodeID should account for every prop with a targetNodeID
        #expect(statCard.propsByNodeID.values.map(\.count).reduce(0, +) == statCard.props.count)
    }

    // MARK: - Integration

    @Test("Analyzes woodcase-app.pen fixture")
    func woodcaseAppIntegration() throws {
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)

        let components = ComponentAnalyzer.analyze(doc)

        // Should find 18 components (4 TabBar variants merged into 1 base = 21 - 3)
        #expect(components.count == 18)

        // Stat Card should have 2 props
        let statCard = components.first { $0.name == "StatCard" }
        #expect(statCard != nil)
        #expect(statCard?.props.count == 2)
        #expect(statCard?.props.contains { $0.name == "value" } == true)
        #expect(statCard?.props.contains { $0.name == "label" } == true)

        // Action Button should have button action
        let actionButton = components.first { $0.name == "ActionButton" }
        #expect(actionButton != nil)
        #expect(actionButton?.actions.contains { $0.role == "button" } == true)

        // Text Input should have textInput binding
        let textInput = components.first { $0.name == "TextInput" }
        #expect(textInput != nil)
        #expect(textInput?.bindings.contains { $0.role == "textInput" } == true)

        // Pencil List Item has 4 props
        let listItem = components.first { $0.name == "PencilListItem" }
        #expect(listItem != nil)
        #expect(listItem?.props.count == 4)
    }
}
