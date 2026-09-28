//
//  StateEmitterIntegrationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct StateEmitterIntegrationTests {
    // MARK: - Helpers

    private func makeFrame(
        id: String = "f1",
        name: String? = nil,
        reusable: Bool? = nil,
        metadata: PenMetadata? = nil,
        fills: PenFills? = nil,
        width: PenSizing? = nil,
        height: PenSizing? = nil,
        layout: PenLayoutDirection? = nil,
        children: [PenNode]? = nil
    ) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(name: name, reusable: reusable, metadata: metadata),
            kind: .frame(PenNode.FrameData(
                width: width, height: height, fills: fills, layout: layout, children: children
            ))
        )
    }

    private var emptyTheme: ThemeManifest {
        ThemeManifest(axes: [], variables: [], contextNodes: [])
    }

    // MARK: - ReactEmitter.emit() integration

    @Test("emit() with stateful component produces states.css in output files")
    func emitProducesStatesCss() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(
                name: "ActionButton",
                fills: .single(.shorthand("#007AFF")),
                width: .fixed(200),
                height: .fixed(48),
                layout: .horizontal
            ),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "hover",
                    trigger: .hover,
                    source: .designerOverride,
                    isStructural: false,
                    deltas: [
                        StateDelta(nodePath: ".", changes: [
                            PropertyChange(property: .fills, value: .string("#0051D5")),
                        ]),
                    ],
                    variantNode: nil
                ),
            ]
        )

        let result = ReactEmitter.emit(
            document: PenDocument(version: "2.9", children: []),
            components: [component],
            theme: emptyTheme
        )

        let statesCss = result.files.first { $0.path == "states.css" }
        #expect(statesCss != nil)
        #expect(statesCss?.content.contains("wc-action-button") == true)
    }

    @Test("emit() with no stateful components does not produce states.css")
    func emitNoStatesCss() {
        let component = ComponentDefinition(
            id: "c1",
            name: "Card",
            sourceNode: makeFrame(
                name: "Card",
                width: .fixed(300),
                height: .fixed(200),
                layout: .vertical
            ),
            props: [],
            actions: [],
            bindings: [],
            states: []
        )

        let result = ReactEmitter.emit(
            document: PenDocument(version: "2.9", children: []),
            components: [component],
            theme: emptyTheme
        )

        let statesCss = result.files.first { $0.path == "states.css" }
        #expect(statesCss == nil)
    }

    // MARK: - PackageScaffolder integration

    @Test("PackageScaffolder routes states.css to root")
    func scaffolderRoutesStatesCss() {
        let files: [GeneratedFile] = [
            GeneratedFile(path: "components/Button.tsx", content: "export function Button() {}"),
            GeneratedFile(path: "theme.css", content: ":root {}"),
            GeneratedFile(path: "states.css", content: ".wc-button { --wc-button-bg: #007AFF; }"),
            GeneratedFile(path: "manifest.json", content: "{}"),
            GeneratedFile(path: "lib/cn.ts", content: "export function cn() {}"),
            GeneratedFile(path: "ThemeProvider.tsx", content: "export function ThemeProvider() {}"),
        ]

        let result = PackageScaffolder.scaffold(
            files: files,
            options: PackageScaffolder.Options(packageName: "@test/ui")
        )

        let statesCss = result.first { $0.path == "states.css" }
        #expect(statesCss != nil)
        #expect(statesCss?.content.contains("wc-button") == true)
    }

    @Test("PackageScaffolder theme.css includes @import states.css when present")
    func scaffolderThemeCssImportsStates() {
        let files: [GeneratedFile] = [
            GeneratedFile(path: "components/Button.tsx", content: "export function Button() {}"),
            GeneratedFile(path: "theme.css", content: ":root {}"),
            GeneratedFile(path: "states.css", content: ".wc-button {}"),
            GeneratedFile(path: "manifest.json", content: "{}"),
            GeneratedFile(path: "lib/cn.ts", content: "export function cn() {}"),
            GeneratedFile(path: "ThemeProvider.tsx", content: "export function ThemeProvider() {}"),
        ]

        let result = PackageScaffolder.scaffold(
            files: files,
            options: PackageScaffolder.Options(packageName: "@test/ui")
        )

        let themeCss = result.first { $0.path == "theme.css" }
        #expect(themeCss?.content.contains("@import \"./states.css\";") == true)
    }

    @Test("PackageScaffolder theme.css omits @import states.css when absent")
    func scaffolderThemeCssOmitsStates() {
        let files: [GeneratedFile] = [
            GeneratedFile(path: "components/Button.tsx", content: "export function Button() {}"),
            GeneratedFile(path: "theme.css", content: ":root {}"),
            GeneratedFile(path: "manifest.json", content: "{}"),
            GeneratedFile(path: "lib/cn.ts", content: "export function cn() {}"),
            GeneratedFile(path: "ThemeProvider.tsx", content: "export function ThemeProvider() {}"),
        ]

        let result = PackageScaffolder.scaffold(
            files: files,
            options: PackageScaffolder.Options(packageName: "@test/ui")
        )

        let themeCss = result.first { $0.path == "theme.css" }
        #expect(themeCss?.content.contains("states.css") != true)
    }

    // MARK: - Manifest integration

    @Test("Manifest includes role and states for stateful components")
    func manifestIncludesRoleAndStates() {
        let component = ComponentDefinition(
            id: "c1",
            name: "ActionButton",
            sourceNode: makeFrame(name: "ActionButton"),
            props: [],
            actions: [],
            bindings: [],
            role: .button,
            states: [
                StateDefinition(
                    name: "hover",
                    trigger: .hover,
                    source: .smartDefault,
                    isStructural: false,
                    deltas: [],
                    effects: RoleStateMapping.smartEffects(for: .hover),
                    variantNode: nil
                ),
            ]
        )

        let manifest = ManifestEmitter.emit(
            components: [component], pages: [], theme: emptyTheme
        )

        #expect(manifest.content.contains("\"role\" : \"button\""))
        #expect(manifest.content.contains("\"hover\""))
    }

    @Test("Manifest omits role and states for non-stateful components")
    func manifestOmitsRoleAndStates() {
        let component = ComponentDefinition(
            id: "c1",
            name: "Card",
            sourceNode: makeFrame(name: "Card"),
            props: [],
            actions: [],
            bindings: [],
            states: []
        )

        let manifest = ManifestEmitter.emit(
            components: [component], pages: [], theme: emptyTheme
        )

        #expect(!manifest.content.contains("\"role\""))
        #expect(!manifest.content.contains("\"states\""))
    }
}
