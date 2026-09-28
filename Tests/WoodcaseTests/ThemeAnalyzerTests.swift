//
//  ThemeAnalyzerTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct ThemeAnalyzerTests {
    // MARK: - Helpers

    private func makeDocument(
        themes: [String: [String]]? = nil,
        variables: [String: PenVariable]? = nil,
        children: [PenNode] = []
    ) -> PenDocument {
        PenDocument(
            version: "2.9",
            themes: themes,
            variables: variables,
            children: children
        )
    }

    // MARK: - Theme Axes

    @Test("Extracts theme axes from document")
    func extractsThemeAxes() {
        let doc = makeDocument(themes: [
            "mode": ["light", "dark"],
            "density": ["default", "compact"],
        ])

        let manifest = ThemeAnalyzer.analyze(doc)

        #expect(manifest.axes.count == 2)
        let modeAxis = manifest.axes.first { $0.name == "mode" }
        #expect(modeAxis?.values == ["light", "dark"])
        let densityAxis = manifest.axes.first { $0.name == "density" }
        #expect(densityAxis?.values == ["default", "compact"])
    }

    @Test("Returns empty axes when no themes defined")
    func emptyThemes() {
        let doc = makeDocument()
        let manifest = ThemeAnalyzer.analyze(doc)
        #expect(manifest.axes.isEmpty)
    }

    // MARK: - Variables

    @Test("Simple variable is not themed")
    func simpleVariable() {
        let doc = makeDocument(variables: [
            "white": PenVariable(type: .color, value: .simple(.string("#FFFFFF"))),
        ])

        let manifest = ThemeAnalyzer.analyze(doc)

        #expect(manifest.variables.count == 1)
        let v = manifest.variables[0]
        #expect(v.name == "white")
        #expect(v.type == .color)
        #expect(v.isThemed == false)
        #expect(v.values.count == 1)
        #expect(v.values[0].value == .string("#FFFFFF"))
        #expect(v.values[0].conditions.isEmpty)
    }

    @Test("Themed variable has isThemed true with correct values")
    func themedVariable() {
        let doc = makeDocument(variables: [
            "bg-page": PenVariable(type: .color, value: .themed([
                PenThemedValue(value: .string("#FAF8F4"), theme: ["mode": "light"]),
                PenThemedValue(value: .string("#1A1A1A"), theme: ["mode": "dark"]),
            ])),
        ])

        let manifest = ThemeAnalyzer.analyze(doc)

        #expect(manifest.variables.count == 1)
        let v = manifest.variables[0]
        #expect(v.name == "bg-page")
        #expect(v.type == .color)
        #expect(v.isThemed == true)
        #expect(v.values.count == 2)

        let light = v.values.first { $0.conditions == ["mode": "light"] }
        #expect(light?.value == .string("#FAF8F4"))
        let dark = v.values.first { $0.conditions == ["mode": "dark"] }
        #expect(dark?.value == .string("#1A1A1A"))
    }

    @Test("Themed value with nil theme has empty conditions")
    func themedValueWithDefaultTheme() {
        let doc = makeDocument(variables: [
            "size": PenVariable(type: .number, value: .themed([
                PenThemedValue(value: .int(16), theme: nil),
                PenThemedValue(value: .int(12), theme: ["density": "compact"]),
            ])),
        ])

        let manifest = ThemeAnalyzer.analyze(doc)

        let v = manifest.variables[0]
        #expect(v.isThemed == true)
        let defaultVal = v.values.first { $0.conditions.isEmpty }
        #expect(defaultVal?.value == .int(16))
    }

    // MARK: - Context Nodes

    @Test("Collects context nodes with theme overrides")
    func contextNodes() {
        let doc = makeDocument(children: [
            PenNode(
                id: "node1",
                common: PenNodeCommon(theme: ["mode": "dark"]),
                kind: .frame(PenNode.FrameData())
            ),
            PenNode(
                id: "node2",
                common: PenNodeCommon(),
                kind: .rectangle(PenNode.RectangleData())
            ),
        ])

        let manifest = ThemeAnalyzer.analyze(doc)

        #expect(manifest.contextNodes == ["node1"])
    }

    @Test("Collects context nodes in nested children")
    func nestedContextNodes() {
        let doc = makeDocument(children: [
            PenNode(
                id: "parent",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(
                        id: "child",
                        common: PenNodeCommon(theme: ["density": "compact"]),
                        kind: .text(PenNode.TextData())
                    ),
                ]))
            ),
        ])

        let manifest = ThemeAnalyzer.analyze(doc)

        #expect(manifest.contextNodes == ["child"])
    }

    // MARK: - Integration

    @Test("Analyzes woodcase-app.pen fixture")
    func woodcaseAppIntegration() throws {
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)

        let manifest = ThemeAnalyzer.analyze(doc)

        // Two axes: mode and density
        #expect(manifest.axes.count == 2)
        #expect(manifest.axes.contains { $0.name == "mode" })
        #expect(manifest.axes.contains { $0.name == "density" })

        // 21 variables total
        #expect(manifest.variables.count == 21)

        // Density-themed variables exist
        let densityVars = manifest.variables.filter { v in
            v.values.contains { $0.conditions.keys.contains("density") }
        }
        #expect(densityVars.count >= 5) // card-radius, font-size-body, spacing-lg, spacing-md, spacing-sm
    }
}
