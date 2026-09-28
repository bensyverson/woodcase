//
//  ThemeEmitterTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct ThemeEmitterTests {
    // MARK: - Helpers

    private func loadGolden(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "golden", subdirectory: "Fixtures/golden")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func assertGolden(_ content: String, name: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
            let goldenDir = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures")
                .appendingPathComponent("golden")
            let url = goldenDir.appendingPathComponent("\(name).golden")
            try content.write(to: url, atomically: true, encoding: .utf8)
            print("  Updated golden file: \(name).golden")
        } else {
            let golden = try loadGolden(name)
            #expect(content == golden, sourceLocation: sourceLocation)
        }
    }

    // MARK: - Unit Tests

    @Test("Simple variable emits in :root")
    func simpleVariableInRoot() {
        let manifest = ThemeManifest(
            axes: [],
            variables: [
                VariableInfo(
                    name: "white",
                    type: .color,
                    isThemed: false,
                    values: [ThemedVariableValue(value: .string("#FFFFFF"), conditions: [:])]
                ),
            ],
            contextNodes: []
        )

        let file = ThemeEmitter.emitCSS(theme: manifest)

        #expect(file.path == "theme.css")
        #expect(file.content.contains("--white: #FFFFFF;"))
        #expect(file.content.contains(":root {"))
    }

    @Test("Themed variable emits default in :root and override in selector")
    func themedVariableEmitsOverride() {
        let manifest = ThemeManifest(
            axes: [ThemeAxis(name: "mode", values: ["light", "dark"])],
            variables: [
                VariableInfo(
                    name: "bg",
                    type: .color,
                    isThemed: true,
                    values: [
                        ThemedVariableValue(value: .string("#FFF"), conditions: ["mode": "light"]),
                        ThemedVariableValue(value: .string("#000"), conditions: ["mode": "dark"]),
                    ]
                ),
            ],
            contextNodes: []
        )

        let file = ThemeEmitter.emitCSS(theme: manifest)

        #expect(file.content.contains(":root {\n  --bg: #FFF;\n}"))
        #expect(file.content.contains("[data-mode=\"dark\"] {\n  --bg: #000;\n}"))
    }

    @Test("Number variable emits as integer when whole")
    func numberVariableEmitsInteger() {
        let manifest = ThemeManifest(
            axes: [],
            variables: [
                VariableInfo(
                    name: "spacing",
                    type: .number,
                    isThemed: false,
                    values: [ThemedVariableValue(value: .int(16), conditions: [:])]
                ),
            ],
            contextNodes: []
        )

        let file = ThemeEmitter.emitCSS(theme: manifest)

        #expect(file.content.contains("--spacing: 16px;"))
    }

    @Test("Number variable emits px units for CSS compatibility")
    func numberVariableEmitsPxUnits() {
        let manifest = ThemeManifest(
            axes: [],
            variables: [
                VariableInfo(
                    name: "card-radius",
                    type: .number,
                    isThemed: false,
                    values: [ThemedVariableValue(value: .int(16), conditions: [:])]
                ),
            ],
            contextNodes: []
        )

        let file = ThemeEmitter.emitCSS(theme: manifest)

        #expect(file.content.contains("--card-radius: 16px;"))
    }

    @Test("Themed number variable emits px units in all selectors")
    func themedNumberVariableEmitsPxUnits() {
        let manifest = ThemeManifest(
            axes: [ThemeAxis(name: "density", values: ["default", "compact"])],
            variables: [
                VariableInfo(
                    name: "spacing-md",
                    type: .number,
                    isThemed: true,
                    values: [
                        ThemedVariableValue(value: .double(16), conditions: ["density": "default"]),
                        ThemedVariableValue(value: .double(8), conditions: ["density": "compact"]),
                    ]
                ),
            ],
            contextNodes: []
        )

        let file = ThemeEmitter.emitCSS(theme: manifest)

        #expect(file.content.contains("--spacing-md: 16px;"))
        #expect(file.content.contains("--spacing-md: 8px;"))
    }

    @Test("Color variable does not get px units")
    func colorVariableNoPxUnits() {
        let manifest = ThemeManifest(
            axes: [],
            variables: [
                VariableInfo(
                    name: "bg",
                    type: .color,
                    isThemed: false,
                    values: [ThemedVariableValue(value: .string("#FFFFFF"), conditions: [:])]
                ),
            ],
            contextNodes: []
        )

        let file = ThemeEmitter.emitCSS(theme: manifest)

        #expect(file.content.contains("--bg: #FFFFFF;"))
        #expect(!file.content.contains("px"))
    }

    // MARK: - Golden File

    @Test("Woodcase-app theme CSS matches golden file")
    func woodcaseAppGolden() throws {
        let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
        let doc = try PenParser.parse(contentsOf: url)
        let manifest = ThemeAnalyzer.analyze(doc)

        let file = ThemeEmitter.emitCSS(theme: manifest)

        try assertGolden(file.content, name: "theme.css")
    }
}
