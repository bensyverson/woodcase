//
//  ViewerScaffolder.swift
//  Woodcase
//

import Foundation

/// Generates a `viewer/` directory containing a Vite + React app for
/// previewing generated components and theme variables.
///
/// All viewer files use ``GeneratedFile/WritePolicy/scaffoldOnce`` except
/// `viewer/components.ts`, which is regenerated on every run to match the
/// current component list.
public enum ViewerScaffolder {
    /// Generate viewer scaffold files.
    ///
    /// - Parameters:
    ///   - components: The analyzed component definitions.
    ///   - pages: The analyzed page definitions.
    ///   - packageName: The npm package name (for display in the viewer).
    /// - Returns: Generated files for the viewer directory.
    /// - Throws: ``WoodcaseResources/Missing`` when the templates cannot be read because
    ///   the resource bundle is not installed.
    public static func scaffold(
        components: [ComponentDefinition],
        pages: [PageDefinition],
        packageName: String
    ) throws -> [GeneratedFile] {
        var files: [GeneratedFile] = []

        // Scaffold-once files loaded from bundled templates
        let templateFiles: [(templateName: String, outputPath: String)] = [
            ("viewer-package.json", "viewer/package.json"),
            ("vite.config.ts", "viewer/vite.config.ts"),
            ("index.html", "viewer/index.html"),
            ("tsconfig.json", "viewer/tsconfig.json"),
            ("main.tsx", "viewer/main.tsx"),
        ]

        for entry in templateFiles {
            let content = try loadTemplate(named: entry.templateName)
            files.append(GeneratedFile(
                path: entry.outputPath,
                content: content,
                writePolicy: .scaffoldOnce
            ))
        }

        // App.tsx needs package name substitution
        let appTemplate = try loadTemplate(named: "App.tsx")
        let appContent = appTemplate.replacingOccurrences(
            of: "{{packageName}}", with: escapedForJSX(packageName)
        )
        files.append(GeneratedFile(
            path: "viewer/App.tsx",
            content: appContent,
            writePolicy: .scaffoldOnce
        ))

        // Always-regenerated file (tracks current component/page list)
        files.append(GeneratedFile(
            path: "viewer/components.ts",
            content: componentsRegistry(components: components, pages: pages)
        ))

        return files
    }

    // MARK: - Template Loading

    private static func loadTemplate(named name: String) throws -> String {
        guard let url = try WoodcaseResources.bundle().url(
            forResource: name, withExtension: nil,
            subdirectory: "ViewerTemplates"
        ) else {
            preconditionFailure("Missing viewer template: \(name)")
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("Could not read viewer template: \(name)")
        }
        return content
    }

    // MARK: - Component Registry

    private static func componentsRegistry(
        components: [ComponentDefinition],
        pages: [PageDefinition]
    ) -> String {
        var lines: [String] = []

        // Component imports
        for component in components {
            lines.append(
                "import { \(component.name) } from \"../src/components/\(component.name)\";"
            )
        }

        // Page imports
        for page in pages {
            lines.append(
                "import { \(page.name) } from \"../src/pages/\(page.name)\";"
            )
        }

        if !lines.isEmpty {
            lines.append("")
        }

        // Components export
        let componentNames = components.map(\.name).joined(separator: ", ")
        lines.append("export const components = { \(componentNames) };")

        // Pages export
        let pageNames = pages.map(\.name).joined(separator: ", ")
        lines.append("export const pages = { \(pageNames) };")

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    /// Escape a package name for safe embedding in JSX.
    private static func escapedForJSX(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
