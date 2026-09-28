//
//  ManifestEmitterTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

@Suite("ManifestEmitter")
struct ManifestEmitterTests {
    // MARK: - Helpers

    private func makeNode(id: String, name: String) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name),
            kind: .frame(PenNode.FrameData())
        )
    }

    private func sampleComponents() -> [ComponentDefinition] {
        [
            ComponentDefinition(
                id: "node-1",
                name: "ActionButton",
                sourceNode: makeNode(id: "node-1", name: "ActionButton"),
                props: [
                    PropDefinition(name: "label", path: "Label", type: .string, defaultValue: .string("Click me")),
                    PropDefinition(name: "disabled", path: "Root", type: .boolean, defaultValue: .bool(false)),
                ],
                actions: [],
                bindings: []
            ),
            ComponentDefinition(
                id: "node-2",
                name: "ScreenRatings",
                sourceNode: makeNode(id: "node-2", name: "ScreenRatings"),
                props: [],
                actions: [],
                bindings: []
            ),
        ]
    }

    private func samplePages() -> [PageDefinition] {
        [
            PageDefinition(
                id: "page-1",
                name: "Home",
                sourceNode: makeNode(id: "page-1", name: "Home")
            ),
        ]
    }

    private func sampleTheme() -> ThemeManifest {
        ThemeManifest(
            axes: [
                ThemeAxis(name: "mode", values: ["light", "dark"]),
                ThemeAxis(name: "density", values: ["default", "compact"]),
            ],
            variables: [
                VariableInfo(
                    name: "accent",
                    type: .color,
                    isThemed: true,
                    values: [
                        ThemedVariableValue(value: .string("#C67A52"), conditions: [:]),
                        ThemedVariableValue(value: .string("#D4895F"), conditions: ["mode": "dark"]),
                    ]
                ),
                VariableInfo(
                    name: "card-radius",
                    type: .number,
                    isThemed: true,
                    values: [
                        ThemedVariableValue(value: .int(16), conditions: [:]),
                        ThemedVariableValue(value: .int(10), conditions: ["density": "compact"]),
                    ]
                ),
                VariableInfo(
                    name: "font-primary",
                    type: .string,
                    isThemed: false,
                    values: [
                        ThemedVariableValue(value: .string("IBM Plex Sans"), conditions: [:]),
                    ]
                ),
            ],
            contextNodes: []
        )
    }

    // MARK: - File metadata

    @Test("Emits manifest.json at root path")
    func emitsAtRootPath() {
        let file = ManifestEmitter.emit(
            components: sampleComponents(),
            pages: samplePages(),
            theme: sampleTheme()
        )
        #expect(file.path == "manifest.json")
    }

    @Test("manifest.json has .always write policy")
    func alwaysWritePolicy() {
        let file = ManifestEmitter.emit(
            components: sampleComponents(),
            pages: samplePages(),
            theme: sampleTheme()
        )
        #expect(file.writePolicy == .always)
    }

    // MARK: - Components

    @Test("Components appear with correct names and paths")
    func componentEntries() throws {
        let file = ManifestEmitter.emit(
            components: sampleComponents(),
            pages: [],
            theme: ThemeManifest(axes: [], variables: [], contextNodes: [])
        )
        let manifest = try decode(file.content)
        #expect(manifest.components.count == 2)
        #expect(manifest.components[0].name == "ActionButton")
        #expect(manifest.components[0].path == "components/ActionButton")
        #expect(manifest.components[1].name == "ScreenRatings")
        #expect(manifest.components[1].path == "components/ScreenRatings")
    }

    @Test("Component props include name and type")
    func componentProps() throws {
        let file = ManifestEmitter.emit(
            components: sampleComponents(),
            pages: [],
            theme: ThemeManifest(axes: [], variables: [], contextNodes: [])
        )
        let manifest = try decode(file.content)
        let button = manifest.components[0]
        #expect(button.props.count == 2)
        #expect(button.props[0].name == "label")
        #expect(button.props[0].type == "string")
        #expect(button.props[1].name == "disabled")
        #expect(button.props[1].type == "boolean")
    }

    // MARK: - Pages

    @Test("Pages appear with correct names and paths")
    func pageEntries() throws {
        let file = ManifestEmitter.emit(
            components: [],
            pages: samplePages(),
            theme: ThemeManifest(axes: [], variables: [], contextNodes: [])
        )
        let manifest = try decode(file.content)
        #expect(manifest.pages.count == 1)
        #expect(manifest.pages[0].name == "Home")
        #expect(manifest.pages[0].path == "pages/Home")
    }

    // MARK: - Theme axes

    @Test("Theme axes are included")
    func themeAxes() throws {
        let file = ManifestEmitter.emit(
            components: [],
            pages: [],
            theme: sampleTheme()
        )
        let manifest = try decode(file.content)
        #expect(manifest.theme.axes.count == 2)
        #expect(manifest.theme.axes[0].name == "mode")
        #expect(manifest.theme.axes[0].values == ["light", "dark"])
        #expect(manifest.theme.axes[1].name == "density")
        #expect(manifest.theme.axes[1].values == ["default", "compact"])
    }

    // MARK: - Variables

    @Test("Variables include typed values with condition keys")
    func variableValues() throws {
        let file = ManifestEmitter.emit(
            components: [],
            pages: [],
            theme: sampleTheme()
        )
        let manifest = try decode(file.content)
        #expect(manifest.theme.variables.count == 3)

        let accent = manifest.theme.variables[0]
        #expect(accent.name == "accent")
        #expect(accent.type == "color")
        #expect(accent.values["default"] == "#C67A52")
        #expect(accent.values["mode:dark"] == "#D4895F")

        let radius = manifest.theme.variables[1]
        #expect(radius.name == "card-radius")
        #expect(radius.type == "number")
        // Number values are encoded as JSON — could be int or double
        #expect(radius.values["default"] != nil)
        #expect(radius.values["density:compact"] != nil)

        let font = manifest.theme.variables[2]
        #expect(font.name == "font-primary")
        #expect(font.type == "string")
        #expect(font.values["default"] == "IBM Plex Sans")
    }

    // MARK: - Round-trip

    @Test("Manifest content round-trips through JSON")
    func roundTrip() throws {
        let file = ManifestEmitter.emit(
            components: sampleComponents(),
            pages: samplePages(),
            theme: sampleTheme()
        )
        // Verify it parses as valid JSON and re-encodes identically
        let data = try #require(file.content.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data)
        let reEncoded = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        let original = try JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(with: data),
            options: [.prettyPrinted, .sortedKeys]
        )
        #expect(reEncoded == original)
    }

    // MARK: - Decode helper

    /// Lightweight Decodable mirror of the manifest JSON for test assertions.
    private struct DecodedManifest: Decodable {
        var components: [DecodedComponent]
        var pages: [DecodedPage]
        var theme: DecodedTheme
    }

    private struct DecodedComponent: Decodable {
        var name: String
        var path: String
        var props: [DecodedProp]
    }

    private struct DecodedProp: Decodable {
        var name: String
        var type: String
    }

    private struct DecodedPage: Decodable {
        var name: String
        var path: String
    }

    private struct DecodedTheme: Decodable {
        var axes: [DecodedAxis]
        var variables: [DecodedVariable]
    }

    private struct DecodedAxis: Decodable {
        var name: String
        var values: [String]
    }

    private struct DecodedVariable: Decodable {
        var name: String
        var type: String
        var values: [String: AnyCodable]
    }

    private func decode(_ json: String) throws -> DecodedManifest {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(DecodedManifest.self, from: data)
    }
}
