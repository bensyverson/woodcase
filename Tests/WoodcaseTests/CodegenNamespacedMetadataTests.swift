//
//  CodegenNamespacedMetadataTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Every code-gen reader takes its keys from `metadata.woodcase` — `props`, `role`,
/// `states`, `action`, `scroll` — as it still takes the underscore spellings, the
/// namespace winning where both are written.
@MainActor
struct CodegenNamespacedMetadataTests {
    private static let json = """
    {
      "version": "2.20",
      "children": [
        {
          "id": "Btn01", "name": "Button", "type": "frame", "reusable": true,
          "width": 120, "height": 40,
          "metadata": { "type": "component", "_role": "card",
            "woodcase": { "role": "button", "props": { "label": "Label" }, "states": { "hover": "Btn02" } } },
          "children": [
            { "id": "Lbl01", "name": "Label", "type": "text", "content": "Go", "fill": "#000000" },
            { "id": "Tgl01", "name": "Toggle", "type": "frame", "width": 10, "height": 10,
              "metadata": { "type": "unknown", "woodcase": { "role": "toggle", "action": "flip" } } }
          ]
        },
        {
          "id": "Btn02", "name": "Hovered", "type": "frame", "x": 0, "y": 100,
          "width": 120, "height": 40,
          "children": [
            { "id": "Lbl02", "name": "Label", "type": "text", "content": "Go", "fill": "#FF0000" }
          ]
        },
        {
          "id": "Scr01", "name": "Scroller", "type": "frame", "clip": true, "layout": "vertical",
          "width": 100, "height": 50, "x": 400, "y": 0,
          "metadata": { "type": "unknown", "woodcase": { "scroll": "vertical" } },
          "children": [
            { "id": "Tal01", "name": "Tall", "type": "rectangle", "width": 100, "height": 300, "fill": "#000000" }
          ]
        }
      ]
    }
    """

    private func document() throws -> PenDocument {
        try PenParser.parse(Self.json)
    }

    @Test("The component analyzer reads role, props, states and action from the namespace")
    func analyzerReadsNamespace() throws {
        let button = try #require(ComponentAnalyzer.analyze(document()).first { $0.id == "Btn01" })

        #expect(button.role == .button)
        #expect(button.props.map(\.name) == ["label"])
        #expect(button.states.map(\.name).contains("hover"))
        #expect(button.actions.contains { $0.name == "flip" && $0.role == "toggle" })
    }

    @Test("The page analyzer treats a namespaced state variant as no page")
    func pageAnalyzerReadsNamespacedStates() throws {
        let pages = try PageAnalyzer.analyze(document())

        #expect(!pages.contains { $0.sourceNode.id == "Btn02" })
    }

    @Test("A component's parameters come from woodcase.props")
    func parametersReadNamespace() throws {
        let editable = try EditableDocument(from: document())

        #expect(editable.parameters(ofComponent: "Btn01").map(\.name) == ["label"])
    }

    @Test("A namespaced scroll exempts the declared axis from clipped")
    func scrollReadsNamespace() throws {
        let findings = try DocumentLinter.findings(in: EditableDocument(from: document()))

        #expect(!findings.contains { $0.check == .clipped && ["Scr01", "Tal01"].contains($0.nodeID) })
    }
}
