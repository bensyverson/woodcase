import ArgumentParser
import Foundation
import Woodcase

/// Generates code from a .pen file. One subcommand per target language.
struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render: code from a .pen file.",
        subcommands: [React.self, SwiftUI.self]
    )

    /// Generates React + Tailwind components, one .tsx file per component and page.
    struct React: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Render: React + Tailwind components from a .pen file.",
            discussion: """
            A render verb: it reads the document and writes .tsx files, one per \
            component and page, plus the theme as Tailwind tokens. --package wraps \
            them in an npm package; --preview adds a viewer app to browse them.

            Building the component this reads -- reusable, _role, _props, state variants \
            and what an override does -- is `woodcase help codegen`. Run `woodcase lint \
            <file> --severity error` first: it reports the _props and _role faults this \
            emitter reads and silently discards.

              woodcase generate react design.pen --output ui --package --name @acme/ui
            """
        )

        @Argument(help: "The .pen file to generate from.")
        var input: PenFilePath

        @Option(name: .long, help: "Output directory for generated files.")
        var output: String = "."

        @Flag(name: .customLong("package"), help: "Wrap output in an npm package structure.")
        var packaged: Bool = false

        @Option(name: .long, help: "Package name (e.g., @myorg/ui). Requires --package.")
        var name: String?

        @Flag(name: .long, help: "Generate a viewer app for browsing components. Requires --package.")
        var preview: Bool = false

        @Flag(name: .long, help: "Clear the output directory before generating.")
        var force: Bool = false

        func validate() throws {
            if name != nil, !packaged {
                throw ValidationError("--name requires --package.")
            }
            if preview, !packaged {
                throw ValidationError("--preview requires --package.")
            }
        }

        /// Reads the file and writes the generated .tsx files, scaffolding and assets.
        ///
        /// The input file is checked before anything is written, so a `--force` run
        /// that names a file which is not there leaves the output directory alone.
        ///
        /// - Throws: ``CommandFailure`` when the .pen file cannot be read, and whatever
        ///   the parser, the analyzers and `FileManager` throw.
        func run() async throws {
            let inputURL = try input.existingFile()
            let outputDirectory = URL(fileURLWithPath: output)
            let fileManager = FileManager.default

            // 1. Clear output directory if --force
            if force, fileManager.fileExists(atPath: outputDirectory.path) {
                try fileManager.removeItem(at: outputDirectory)
            }

            // 2–3. Parse, and merge in the components, variables and theme axes the
            // libraries the file imports define: every imported component becomes code
            // beside the file's own.
            let document = try await PenFileTransaction.read(at: inputURL, fonts: .shared) { editable in
                editable.materializeForGeneration()
            }.value

            // 4. Analyze
            let components = ComponentAnalyzer.analyze(document)
            let pages = PageAnalyzer.analyze(document)
            let theme = ThemeAnalyzer.analyze(document)

            // 5. Emit
            let result = ReactEmitter.emit(
                document: document,
                components: components,
                pages: pages,
                theme: theme
            )
            var files = result.files

            // 6. Collect font families from theme variables
            let fontFamilies = collectFontFamilies(from: theme)

            // 7. Package (if requested)
            if packaged {
                // Build additional dependencies from icon libraries
                var additionalDeps: [String: String] = [:]
                for family in result.iconLibraries {
                    if let pkg = IconLibraryMapping.npmPackage(for: family) {
                        additionalDeps[pkg] = "*"
                    }
                }

                let packageName = name ?? "@woodcase/ui"
                let options = PackageScaffolder.Options(
                    packageName: packageName,
                    additionalDependencies: additionalDeps,
                    fontFamilies: fontFamilies,
                    preview: preview
                )
                files = PackageScaffolder.scaffold(files: files, options: options)

                // Generate viewer app if --preview
                if preview {
                    let viewerFiles = ViewerScaffolder.scaffold(
                        components: components,
                        pages: pages,
                        packageName: packageName
                    )
                    files.append(contentsOf: viewerFiles)
                }
            }

            // 8. Copy image assets from input directory to output directory
            let inputDir = inputURL.deletingLastPathComponent()
            for imageURL in result.imageAssetURLs.sorted() {
                // Skip absolute paths and HTTP(S) URLs
                guard !imageURL.hasPrefix("/"),
                      !imageURL.hasPrefix("http://"),
                      !imageURL.hasPrefix("https://")
                else { continue }

                let sourceURL = inputDir.appendingPathComponent(imageURL)
                let destURL = outputDirectory.appendingPathComponent(imageURL)

                guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

                let destDir = destURL.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: destDir.path) {
                    try fileManager.createDirectory(
                        at: destDir, withIntermediateDirectories: true
                    )
                }

                // Remove existing file before copying (copyItem fails if dest exists)
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destURL)
            }

            // 9. Write files
            try Generate.write(files, to: outputDirectory)

            let imageCount = result.imageAssetURLs.count
            let imageMsg = imageCount > 0 ? " + \(imageCount) image(s)" : ""
            print("Generated \(files.count) file(s)\(imageMsg) to \(outputDirectory.path)")

            if preview {
                print("To start the viewer:")
                print("  cd \(outputDirectory.path) && npm install && npm run preview")
            }
        }

        /// Extracts font family names from string-typed theme variables
        /// whose names contain "font" (but not font-size, font-weight, etc.).
        private func collectFontFamilies(from theme: ThemeManifest) -> Set<String> {
            let excludedSuffixes = ["size", "weight", "style", "height", "spacing"]
            var families: Set<String> = []
            for variable in theme.variables where variable.type == .string {
                let name = variable.name.lowercased()
                guard name.contains("font") else { continue }
                // Skip font-size, font-weight, etc.
                let isExcluded = excludedSuffixes.contains { suffix in
                    name.hasSuffix(suffix)
                }
                guard !isExcluded else { continue }
                // Extract the string value
                for themed in variable.values {
                    if case let .string(str) = themed.value, !str.isEmpty {
                        families.insert(str)
                    }
                }
            }
            return families
        }
    }
}
