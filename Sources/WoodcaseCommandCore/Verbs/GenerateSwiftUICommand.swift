//
//  GenerateSwiftUICommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

extension Generate {
    /// Generates a SwiftPM package of SwiftUI views, one per page.
    struct SwiftUI: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "swiftui",
            abstract: "Render: a SwiftUI package from a .pen file.",
            discussion: """
            A render verb: it reads the document and writes a SwiftPM package -- \
            Package.swift (rewritten every run), one view per reusable component \
            under Sources/<name>/Components, one view per top-level frame under \
            Sources/<name>/Pages, and \
            Sources/<name>/Support/PenSupport*.swift, the helpers the views use. Layout is \
            idiomatic stacks (HStack, VStack, ZStack, Spacer, frame, padding): it keeps \
            the design's intent, not Pen's flexbox to the pixel.

            Every view ends with a #Preview per state and theme. The package also carries \
            a catalog of the kit -- every component in its states, every page, the \
            theme's colours, tokens and type, with a picker per theme axis -- under \
            Sources/<name>/Catalog, and an executable that opens it: \
            `swift run <name>Catalog` (macOS), `swift run <name>Catalog --snapshot \
            kit.png` to render it under every theme, or `swift run <name>Catalog \
            --fonts` to list the bundled fonts and whether each registered.

            Frames, rectangles, ellipses, arcs, polygons, paths, lines, icons and text \
            are written with their paints -- colours, gradients, images (copied into \
            Sources/<name>/Resources), stacks, blend modes and opacity -- their strokes \
            and their effects. Icon fonts, and the files of every text family the OS \
            does not ship -- the document's declared fonts, else Google Fonts through \
            the font cache -- are copied into Resources beside the images, and the \
            package registers them itself; a family with no file is a warning. \
            A component's props are typed lets with defaults; an instance is a call to \
            its view, or the component inlined where no prop carries an override (a \
            warning). Every other node is a marked placeholder; each gap is a warning on \
            stderr.

            The views are written for iOS 26 / macOS 26; --floor ios18 declares iOS 18 / \
            macOS 15 instead, served by availability branches in the support file.

              woodcase generate swiftui design.pen --output ui --name AcmeUI
            """
        )

        @Argument(help: "The .pen file to generate from.")
        var input: PenFilePath

        @Option(name: .long, help: "Output directory for the package.")
        var output: String = "."

        @Option(name: .long, help: "The Swift module and package name; a Swift identifier.")
        var name: String = SwiftUIEmitter.Options().moduleName

        @Option(name: .long, help: "The oldest OS releases the package supports.")
        var floor: SwiftUIEmitter.DeploymentFloor = SwiftUIEmitter.Options().deploymentFloor

        @Flag(name: .long, help: "Clear the output directory before generating.")
        var force: Bool = false

        func validate() throws {
            guard name.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*/) != nil else {
                throw ValidationError("--name must be a Swift identifier (letters, digits, underscores), not '\(name)'.")
            }
        }

        /// Reads the file and writes the package.
        ///
        /// The input file is checked before anything is written, so a `--force` run that
        /// names a file which is not there leaves the output directory alone.
        ///
        /// - Throws: ``CommandFailure`` when the .pen file cannot be read, and whatever
        ///   the parser, the analyzers and `FileManager` throw.
        func run() async throws {
            let inputURL = try input.existingFile()
            let outputDirectory = URL(fileURLWithPath: output)
            if force, FileManager.default.fileExists(atPath: outputDirectory.path) {
                try FileManager.default.removeItem(at: outputDirectory)
            }
            let document = try await PenFileTransaction.read(at: inputURL, fonts: .shared) { editable in
                editable.materializeForGeneration()
            }.value

            let diagnostics = PenDiagnosticCollector()
            let result = SwiftUIEmitter.emit(
                document: document,
                components: ComponentAnalyzer.analyze(document),
                pages: PageAnalyzer.analyze(document),
                theme: ThemeAnalyzer.analyze(document),
                options: SwiftUIEmitter.Options(deploymentFloor: floor, moduleName: name),
                diagnostics: diagnostics
            )
            let written = try Generate.write(result.files, to: outputDirectory)
            let resources = outputDirectory.appendingPathComponent("Sources/\(name)/Resources", isDirectory: true)
            let images = try copyImages(result.imageAssetURLs, from: inputURL.deletingLastPathComponent(), to: resources)
            let iconFonts = try Self.copy(result.iconLibraries.sorted().flatMap(SwiftUIEmitter.iconFontFiles(for:)), into: resources)
            let bundle = await GoogleFontResolver.shared.fontBundle(
                for: result.fontFaces, declaredIn: document, relativeTo: inputURL
            )
            let textFonts = try Self.copy(bundle.files, into: resources)
            for diagnostic in diagnostics.diagnostics {
                StandardErrorLine.write("\(diagnostic.severity.rawValue): \(diagnostic.nodeID.map { "\($0): " } ?? "")\(diagnostic.message)")
            }
            for missing in bundle.missing {
                StandardErrorLine.write("warning: \(missing.reason)")
            }
            let imageNote = images > 0 ? " + \(images) image(s)" : ""
            let iconNote = iconFonts > 0 ? " + \(iconFonts) icon font(s)" : ""
            let textNote = textFonts > 0 ? " + \(textFonts) text font(s)" : ""
            print("Generated \(written) file(s)\(imageNote)\(iconNote)\(textNote) to \(outputDirectory.path)")
        }

        /// Copies `sources` into `resources`, flat, as SwiftPM's `.process` bundles them,
        /// replacing a file of the same name.
        ///
        /// - Returns: How many files were copied.
        private static func copy(_ sources: [URL], into resources: URL) throws -> Int {
            let fileManager = FileManager.default
            for source in sources {
                try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
                let destination = resources.appendingPathComponent(source.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
            }
            return sources.count
        }

        /// Copies each image the views load into `resources`; an image missing beside the
        /// .pen file is a warning.
        ///
        /// - Returns: How many images were copied.
        private func copyImages(_ urls: Set<String>, from inputDirectory: URL, to resources: URL) throws -> Int {
            var sources: [URL] = []
            for url in urls.sorted() {
                let source = inputDirectory.appendingPathComponent(url)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    StandardErrorLine.write("warning: the image \(url) is not beside the .pen file; the package will not find it")
                    continue
                }
                sources.append(source)
            }
            return try Self.copy(sources, into: resources)
        }
    }
}
