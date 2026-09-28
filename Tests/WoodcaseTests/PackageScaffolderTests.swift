//
//  PackageScaffolderTests.swift
//  Woodcase
//

import Testing
@testable import Woodcase

@Suite("PackageScaffolder")
struct PackageScaffolderTests {
    // MARK: - Helpers

    private func sampleFiles() -> [GeneratedFile] {
        [
            GeneratedFile(path: "components/Button.tsx", content: "export function Button() {}"),
            GeneratedFile(path: "components/Card.tsx", content: "export function Card() {}"),
            GeneratedFile(path: "pages/Home.tsx", content: "export function Home() {}"),
            GeneratedFile(path: "ThemeProvider.tsx", content: "export function ThemeProvider() {}"),
            GeneratedFile(path: "lib/cn.ts", content: "export function cn() {}"),
            GeneratedFile(path: "theme.css", content: ":root {\n  --accent: #C67A52;\n}\n"),
        ]
    }

    private func scaffold(
        files: [GeneratedFile]? = nil,
        packageName: String = "@test/ui",
        additionalDependencies: [String: String] = [:],
        fontFamilies: Set<String> = [],
        preview: Bool = false
    ) -> [GeneratedFile] {
        let options = PackageScaffolder.Options(
            packageName: packageName,
            additionalDependencies: additionalDependencies,
            fontFamilies: fontFamilies,
            preview: preview
        )
        return PackageScaffolder.scaffold(files: files ?? sampleFiles(), options: options)
    }

    private func file(named path: String, in files: [GeneratedFile]) -> GeneratedFile? {
        files.first { $0.path == path }
    }

    // MARK: - File relocation

    @Test("Source files are relocated under src/")
    func sourceFilesRelocated() {
        let result = scaffold()
        let paths = Set(result.map(\.path))
        #expect(paths.contains("src/components/Button.tsx"))
        #expect(paths.contains("src/components/Card.tsx"))
        #expect(paths.contains("src/pages/Home.tsx"))
        #expect(paths.contains("src/ThemeProvider.tsx"))
        #expect(paths.contains("src/lib/cn.ts"))
    }

    @Test("theme.css stays at root")
    func themeCSSAtRoot() {
        let result = scaffold()
        let paths = Set(result.map(\.path))
        #expect(paths.contains("theme.css"))
        #expect(!paths.contains("src/theme.css"))
    }

    @Test("Original unrelocated paths are not present")
    func originalPathsRemoved() {
        let result = scaffold()
        let paths = Set(result.map(\.path))
        #expect(!paths.contains("components/Button.tsx"))
        #expect(!paths.contains("ThemeProvider.tsx"))
        #expect(!paths.contains("lib/cn.ts"))
    }

    // MARK: - Barrel export

    @Test("Barrel index.ts exports all components")
    func barrelExportsComponents() throws {
        let result = scaffold()
        let barrel = try #require(file(named: "index.ts", in: result))
        #expect(barrel.content.contains("Button"))
        #expect(barrel.content.contains("Card"))
    }

    @Test("Barrel index.ts exports pages")
    func barrelExportsPages() throws {
        let result = scaffold()
        let barrel = try #require(file(named: "index.ts", in: result))
        #expect(barrel.content.contains("Home"))
    }

    @Test("Barrel index.ts exports ThemeProvider")
    func barrelExportsThemeProvider() throws {
        let result = scaffold()
        let barrel = try #require(file(named: "index.ts", in: result))
        #expect(barrel.content.contains("ThemeProvider"))
    }

    @Test("Barrel index.ts does NOT export utility files")
    func barrelOmitsUtilities() throws {
        let result = scaffold()
        let barrel = try #require(file(named: "index.ts", in: result))
        #expect(!barrel.content.contains("cn"))
    }

    @Test("Barrel index.ts has .always write policy")
    func barrelWritePolicy() throws {
        let result = scaffold()
        let barrel = try #require(file(named: "index.ts", in: result))
        #expect(barrel.writePolicy == .always)
    }

    // MARK: - Scaffold files

    @Test("package.json uses provided package name")
    func packageJsonName() throws {
        let result = scaffold(packageName: "@myorg/design-system")
        let pkg = try #require(file(named: "package.json", in: result))
        #expect(pkg.content.contains("@myorg/design-system"))
    }

    @Test("tsup.config.ts is generated")
    func tsupConfigGenerated() throws {
        let result = scaffold()
        let tsup = try #require(file(named: "tsup.config.ts", in: result))
        #expect(tsup.content.contains("defineConfig"))
    }

    @Test("Scaffold files have .scaffoldOnce write policy")
    func scaffoldFilesPolicy() throws {
        let result = scaffold()
        let pkg = try #require(file(named: "package.json", in: result))
        let tsup = try #require(file(named: "tsup.config.ts", in: result))
        #expect(pkg.writePolicy == .scaffoldOnce)
        #expect(tsup.writePolicy == .scaffoldOnce)
    }

    // MARK: - Theme CSS

    @Test("theme.css gets @import tailwindcss prepended")
    func themeCSSImport() throws {
        let result = scaffold()
        let theme = try #require(file(named: "theme.css", in: result))
        #expect(theme.content.hasPrefix("@import \"tailwindcss\";\n"))
        #expect(theme.content.contains(":root"))
    }

    // MARK: - Source file policies

    @Test("Relocated source files retain .always write policy")
    func sourceFilePolicies() {
        let result = scaffold()
        let sourceFiles = result.filter { $0.path.hasPrefix("src/") }
        for file in sourceFiles {
            #expect(file.writePolicy == .always, "Expected .always for \(file.path)")
        }
    }

    // MARK: - Edge cases

    @Test("Empty input produces only scaffold and barrel files")
    func emptyInput() {
        let result = scaffold(files: [])
        let paths = Set(result.map(\.path))
        #expect(paths.contains("package.json"))
        #expect(paths.contains("tsup.config.ts"))
        #expect(paths.contains("index.ts"))
        #expect(result.count == 3)
    }

    @Test("Components-only input (no pages, no theme)")
    func componentsOnly() throws {
        let files = [
            GeneratedFile(path: "components/Button.tsx", content: "export function Button() {}"),
        ]
        let result = scaffold(files: files)
        let barrel = try #require(file(named: "index.ts", in: result))
        #expect(barrel.content.contains("Button"))
        #expect(!barrel.content.contains("ThemeProvider"))
    }

    // MARK: - Additional dependencies

    @Test("package.json includes additional dependencies")
    func additionalDependencies() throws {
        let result = scaffold(additionalDependencies: ["lucide-react": "^0.300.0"])
        let pkg = try #require(file(named: "package.json", in: result))
        #expect(pkg.content.contains("\"lucide-react\""))
        #expect(pkg.content.contains("\"^0.300.0\""))
    }

    @Test("clsx and tailwind-merge are in dependencies, not devDependencies")
    func runtimeDepsInDependencies() throws {
        let result = scaffold()
        let pkg = try #require(file(named: "package.json", in: result))
        // clsx should be in "dependencies", not "devDependencies"
        #expect(pkg.content.contains("\"dependencies\""))
        // Find the dependencies section and verify clsx is there
        let lines = pkg.content.components(separatedBy: "\n")
        var inDependencies = false
        var clsxInDeps = false
        for line in lines {
            if line.contains("\"dependencies\"") { inDependencies = true }
            if line.contains("\"devDependencies\"") { inDependencies = false }
            if inDependencies, line.contains("\"clsx\"") { clsxInDeps = true }
        }
        #expect(clsxInDeps, "clsx should be in dependencies, not devDependencies")
    }

    // MARK: - Font families

    @Test("theme.css gets fontsource imports before tailwind import")
    func fontsourceImports() throws {
        let result = scaffold(fontFamilies: ["IBM Plex Sans", "Inter"])
        let theme = try #require(file(named: "theme.css", in: result))
        // Fontsource imports should come before @import "tailwindcss"
        let tailwindIndex = theme.content.range(of: "@import \"tailwindcss\"")
        let fontsourceIndex = theme.content.range(of: "@import \"@fontsource/")
        #expect(fontsourceIndex != nil, "Should contain fontsource import")
        #expect(tailwindIndex != nil, "Should contain tailwind import")
        if let fi = fontsourceIndex, let ti = tailwindIndex {
            #expect(fi.lowerBound < ti.lowerBound, "Fontsource should come before tailwind")
        }
    }

    // MARK: - Preview mode

    @Test("package.json includes preview script when preview enabled")
    func previewScript() throws {
        let result = scaffold(preview: true)
        let pkg = try #require(file(named: "package.json", in: result))
        #expect(pkg.content.contains("\"preview\""))
        #expect(pkg.content.contains("cd viewer && npx vite"))
    }

    @Test("package.json includes workspaces when preview enabled")
    func previewWorkspaces() throws {
        let result = scaffold(preview: true)
        let pkg = try #require(file(named: "package.json", in: result))
        #expect(pkg.content.contains("\"workspaces\""))
        #expect(pkg.content.contains("\"viewer\""))
    }

    @Test("package.json omits preview script by default")
    func noPreviewByDefault() throws {
        let result = scaffold()
        let pkg = try #require(file(named: "package.json", in: result))
        #expect(!pkg.content.contains("\"preview\""))
        #expect(!pkg.content.contains("\"workspaces\""))
    }

    @Test("manifest.json stays at root (not under src/)")
    func manifestAtRoot() {
        let files = sampleFiles() + [
            GeneratedFile(path: "manifest.json", content: "{}"),
        ]
        let result = scaffold(files: files)
        let paths = Set(result.map(\.path))
        #expect(paths.contains("manifest.json"))
        #expect(!paths.contains("src/manifest.json"))
    }

    // MARK: - Font families

    @Test("package.json includes fontsource packages")
    func fontsourcePackages() throws {
        let result = scaffold(fontFamilies: ["IBM Plex Sans"])
        let pkg = try #require(file(named: "package.json", in: result))
        #expect(pkg.content.contains("@fontsource/ibm-plex-sans"))
    }
}
