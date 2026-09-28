//
//  PackageScaffolder.swift
//  Woodcase
//

/// Wraps emitted code generation files in an npm package structure.
///
/// Given the flat file list produced by an emitter (e.g. ``ReactEmitter``),
/// `PackageScaffolder` relocates source files under `src/`, generates a barrel
/// `index.ts` that re-exports all components, and produces scaffold files
/// (`package.json`, `tsup.config.ts`) that are only written once so the user
/// can customize them after initial generation.
public enum PackageScaffolder {
    /// Configuration for the scaffolded package.
    public struct Options: Friendly {
        /// The npm package name (e.g. `"@myorg/ui"`).
        public var packageName: String

        /// Additional runtime dependencies to include in `package.json`
        /// (e.g. `["lucide-react": "^0.300.0"]`).
        public var additionalDependencies: [String: String]

        /// Font families to load via Fontsource. Each family produces a
        /// CSS `@import` in `theme.css` and a dependency in `package.json`.
        public var fontFamilies: Set<String>

        /// When `true`, adds a `viewer` workspace and `preview` script
        /// to the generated `package.json`.
        public var preview: Bool

        public init(
            packageName: String,
            additionalDependencies: [String: String] = [:],
            fontFamilies: Set<String> = [],
            preview: Bool = false
        ) {
            self.packageName = packageName
            self.additionalDependencies = additionalDependencies
            self.fontFamilies = fontFamilies
            self.preview = preview
        }
    }

    /// Relocate source files under `src/`, generate a barrel export, and
    /// produce scaffold files for an npm package.
    ///
    /// - Parameters:
    ///   - files: The files produced by an emitter (e.g. ``ReactEmitter``).
    ///   - options: Package configuration.
    /// - Returns: A new file list with relocated sources, barrel export, and
    ///   scaffold files.
    public static func scaffold(
        files: [GeneratedFile],
        options: Options
    ) -> [GeneratedFile] {
        var result: [GeneratedFile] = []
        var exportEntries: [ExportEntry] = []

        // Build fontsource CSS imports
        let fontsourceImports = options.fontFamilies.sorted()
            .map { FontsourceMapping.cssImport(for: $0) }

        // Check if states.css is present in the file list
        let hasStatesCss = files.contains { $0.path == "states.css" }

        // 1. Relocate source files, collecting export info along the way
        for file in files {
            if file.path == "theme.css" {
                // theme.css stays at root with fontsource + Tailwind imports prepended
                var preamble = fontsourceImports
                preamble.append("@import \"tailwindcss\";")
                // Tell Tailwind to scan the src/ directory for utility classes
                preamble.append("@source \"./src\";")
                // Import states.css when present
                if hasStatesCss {
                    preamble.append("@import \"./states.css\";")
                }
                let content = preamble.joined(separator: "\n") + "\n\n" + file.content
                result.append(GeneratedFile(path: "theme.css", content: content))
            } else if file.path == "manifest.json" {
                // manifest.json stays at root (consumed by viewer and external tools)
                result.append(file)
            } else if file.path == "states.css" {
                // states.css stays at root (alongside theme.css)
                result.append(file)
            } else {
                // Relocate under src/
                let relocated = GeneratedFile(path: "src/" + file.path, content: file.content)
                result.append(relocated)

                // Track exportable files
                if let entry = exportEntry(for: file.path) {
                    exportEntries.append(entry)
                }
            }
        }

        // 2. Generate barrel index.ts
        exportEntries.sort { $0.name < $1.name }
        let barrelContent = exportEntries
            .map { "export { \($0.name) } from \"./src/\($0.importPath)\";" }
            .joined(separator: "\n")
            + (exportEntries.isEmpty ? "" : "\n")
        result.append(GeneratedFile(path: "index.ts", content: barrelContent))

        // 3. Generate scaffold files
        // Merge fontsource packages into additional dependencies
        var allDeps = options.additionalDependencies
        for family in options.fontFamilies {
            let pkg = FontsourceMapping.packageName(for: family)
            if allDeps[pkg] == nil {
                allDeps[pkg] = "^5.0.0"
            }
        }

        result.append(GeneratedFile(
            path: "package.json",
            content: packageJSON(
                name: options.packageName,
                additionalDependencies: allDeps,
                preview: options.preview
            ),
            writePolicy: .scaffoldOnce
        ))
        result.append(GeneratedFile(
            path: "tsup.config.ts",
            content: tsupConfig(),
            writePolicy: .scaffoldOnce
        ))

        return result
    }

    // MARK: - Private

    private struct ExportEntry {
        var name: String
        var importPath: String
    }

    private static func exportEntry(for path: String) -> ExportEntry? {
        // Export components: components/Button.tsx → Button
        if path.hasPrefix("components/"), path.hasSuffix(".tsx") {
            let name = String(path.dropFirst("components/".count).dropLast(".tsx".count))
            return ExportEntry(name: name, importPath: "components/\(name)")
        }
        // Export pages: pages/Home.tsx → Home
        if path.hasPrefix("pages/"), path.hasSuffix(".tsx") {
            let name = String(path.dropFirst("pages/".count).dropLast(".tsx".count))
            return ExportEntry(name: name, importPath: "pages/\(name)")
        }
        // Export ThemeProvider
        if path == "ThemeProvider.tsx" {
            return ExportEntry(name: "ThemeProvider", importPath: "ThemeProvider")
        }
        // Skip utilities (lib/cn.ts, etc.)
        return nil
    }

    private static func packageJSON(
        name: String,
        additionalDependencies: [String: String] = [:],
        preview: Bool = false
    ) -> String {
        // Build dependencies: runtime deps + additional (icon libs, fontsource)
        var deps: [String: String] = [
            "clsx": "^2.0.0",
            "tailwind-merge": "^2.0.0",
        ]
        for (key, value) in additionalDependencies {
            deps[key] = value
        }

        let depsJSON = deps.sorted(by: { $0.key < $1.key })
            .map { "    \"\($0.key)\": \"\($0.value)\"" }
            .joined(separator: ",\n")

        var scripts = [
            "\"build\": \"tsup\"",
            "\"dev\": \"tsup --watch\"",
        ]
        if preview {
            scripts.append("\"preview\": \"cd viewer && npx vite\"")
        }
        let scriptsJSON = scripts.map { "    \($0)" }.joined(separator: ",\n")

        let workspacesLine = preview
            ? "\n  \"workspaces\": [\"viewer\"],"
            : ""

        return """
        {
          "name": "\(name)",
          "version": "0.0.1",
          "type": "module",\(workspacesLine)
          "main": "./dist/index.js",
          "types": "./dist/index.d.ts",
          "exports": {
            ".": {
              "types": "./dist/index.d.ts",
              "import": "./dist/index.js"
            },
            "./theme.css": "./theme.css"
          },
          "scripts": {
        \(scriptsJSON)
          },
          "peerDependencies": {
            "react": "^18 || ^19",
            "react-dom": "^18 || ^19"
          },
          "dependencies": {
        \(depsJSON)
          },
          "devDependencies": {
            "tailwindcss": "^4.0.0",
            "tsup": "^8.0.0",
            "typescript": "^5.0.0"
          },
          "sideEffects": false
        }
        """
    }

    private static func tsupConfig() -> String {
        """
        import { defineConfig } from "tsup";

        export default defineConfig({
          entry: ["index.ts"],
          format: ["esm"],
          dts: true,
          sourcemap: true,
          clean: true,
          external: ["react", "react-dom"],
        });
        """
    }
}
