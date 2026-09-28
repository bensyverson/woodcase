//
//  ViewerScaffolderTests.swift
//  Woodcase
//

import Testing
@testable import Woodcase

@Suite("ViewerScaffolder")
struct ViewerScaffolderTests {
    // MARK: - Helpers

    private func sampleComponents() -> [ComponentDefinition] {
        [
            ComponentDefinition(
                id: "node-1",
                name: "ActionButton",
                sourceNode: PenNode(
                    id: "node-1",
                    common: PenNodeCommon(name: "ActionButton"),
                    kind: .frame(PenNode.FrameData())
                ),
                props: [],
                actions: [],
                bindings: []
            ),
            ComponentDefinition(
                id: "node-2",
                name: "ScreenRatings",
                sourceNode: PenNode(
                    id: "node-2",
                    common: PenNodeCommon(name: "ScreenRatings"),
                    kind: .frame(PenNode.FrameData())
                ),
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
                sourceNode: PenNode(
                    id: "page-1",
                    common: PenNodeCommon(name: "Home"),
                    kind: .frame(PenNode.FrameData())
                )
            ),
        ]
    }

    private func scaffold(
        components: [ComponentDefinition]? = nil,
        pages: [PageDefinition]? = nil,
        packageName: String = "@test/ui"
    ) throws -> [GeneratedFile] {
        try ViewerScaffolder.scaffold(
            components: components ?? sampleComponents(),
            pages: pages ?? samplePages(),
            packageName: packageName
        )
    }

    private func file(named path: String, in files: [GeneratedFile]) -> GeneratedFile? {
        files.first { $0.path == path }
    }

    // MARK: - File generation

    @Test("Generates all expected viewer files")
    func generatesAllFiles() throws {
        let result = try scaffold()
        let paths = Set(result.map(\.path))
        #expect(paths.contains("viewer/package.json"))
        #expect(paths.contains("viewer/vite.config.ts"))
        #expect(paths.contains("viewer/index.html"))
        #expect(paths.contains("viewer/tsconfig.json"))
        #expect(paths.contains("viewer/main.tsx"))
        #expect(paths.contains("viewer/App.tsx"))
        #expect(paths.contains("viewer/components.ts"))
    }

    // MARK: - Write policies

    @Test("Scaffold files use scaffoldOnce policy")
    func scaffoldFilesPolicy() throws {
        let result = try scaffold()
        let scaffoldPaths = [
            "viewer/package.json",
            "viewer/vite.config.ts",
            "viewer/index.html",
            "viewer/tsconfig.json",
            "viewer/main.tsx",
            "viewer/App.tsx",
        ]
        for path in scaffoldPaths {
            let f = file(named: path, in: result)
            #expect(f?.writePolicy == .scaffoldOnce, "Expected .scaffoldOnce for \(path)")
        }
    }

    @Test("components.ts uses .always write policy")
    func componentsRegistryPolicy() throws {
        let result = try scaffold()
        let registry = try #require(file(named: "viewer/components.ts", in: result))
        #expect(registry.writePolicy == .always)
    }

    // MARK: - Component registry

    @Test("components.ts imports all components from barrel export")
    func componentsImports() throws {
        let result = try scaffold()
        let registry = try #require(file(named: "viewer/components.ts", in: result))
        #expect(registry.content.contains("import { ActionButton } from \"../src/components/ActionButton\""))
        #expect(registry.content.contains("import { ScreenRatings } from \"../src/components/ScreenRatings\""))
    }

    @Test("components.ts imports pages")
    func pagesImports() throws {
        let result = try scaffold()
        let registry = try #require(file(named: "viewer/components.ts", in: result))
        #expect(registry.content.contains("import { Home } from \"../src/pages/Home\""))
    }

    @Test("components.ts exports components registry object")
    func componentsExport() throws {
        let result = try scaffold()
        let registry = try #require(file(named: "viewer/components.ts", in: result))
        #expect(registry.content.contains("export const components"))
        #expect(registry.content.contains("ActionButton"))
        #expect(registry.content.contains("ScreenRatings"))
    }

    @Test("components.ts exports pages registry object")
    func pagesExport() throws {
        let result = try scaffold()
        let registry = try #require(file(named: "viewer/components.ts", in: result))
        #expect(registry.content.contains("export const pages"))
        #expect(registry.content.contains("Home"))
    }

    // MARK: - Viewer package.json

    @Test("viewer/package.json includes react and vite dependencies")
    func viewerPackageJson() throws {
        let result = try scaffold()
        let pkg = try #require(file(named: "viewer/package.json", in: result))
        #expect(pkg.content.contains("\"react\""))
        #expect(pkg.content.contains("\"react-dom\""))
        #expect(pkg.content.contains("\"vite\""))
        #expect(pkg.content.contains("\"@vitejs/plugin-react\""))
        #expect(pkg.content.contains("\"tailwindcss\""))
        #expect(pkg.content.contains("\"@tailwindcss/vite\""))
    }

    // MARK: - Vite config

    @Test("vite.config.ts allows parent directory access")
    func viteConfigParentAccess() throws {
        let result = try scaffold()
        let vite = try #require(file(named: "viewer/vite.config.ts", in: result))
        #expect(vite.content.contains("fs:"))
        #expect(vite.content.contains("allow"))
        #expect(vite.content.contains("__dirname"))
    }

    // MARK: - index.html

    @Test("index.html has root div and script tag")
    func indexHtml() throws {
        let result = try scaffold()
        let html = try #require(file(named: "viewer/index.html", in: result))
        #expect(html.content.contains("<div id=\"root\">"))
        #expect(html.content.contains("src=\"/main.tsx\""))
    }

    // MARK: - main.tsx

    @Test("main.tsx imports theme.css and renders App")
    func mainTsx() throws {
        let result = try scaffold()
        let main = try #require(file(named: "viewer/main.tsx", in: result))
        #expect(main.content.contains("../theme.css"))
        #expect(main.content.contains("<App"))
    }

    // MARK: - App.tsx

    @Test("App.tsx contains viewer shell structure")
    func appTsx() throws {
        let result = try scaffold()
        let app = try #require(file(named: "viewer/App.tsx", in: result))
        // Should have key viewer elements
        #expect(app.content.contains("manifest"))
        #expect(app.content.contains("components"))
    }

    // MARK: - Edge cases

    @Test("Empty components and pages produces valid registry")
    func emptyInputs() throws {
        let result = try scaffold(components: [], pages: [])
        let registry = try #require(file(named: "viewer/components.ts", in: result))
        #expect(registry.content.contains("export const components"))
        #expect(registry.content.contains("export const pages"))
    }
}
