import ArgumentParser
import CoreGraphics
import Foundation
import Woodcase

/// Renders a whole .pen file to PNG or PDF, one output per theme combination.
struct Render: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render: a whole .pen file to PNG or PDF.",
        discussion: """
        A render verb: it reads the file, settles the layout and writes an image \
        beside it — one per theme combination when the document defines theme axes, \
        named for the pins it rendered under. `woodcase shot` is the cheaper sibling, \
        scoped to one node. The libraries the file's own `imports` name are read \
        from beside it; a missing one is a warning, and fails --strict.

          woodcase render design.pen --format pdf --theme "mode=dark" --output-dir out
        """
    )

    @Argument(help: "The .pen file to render.")
    var input: PenFilePath

    @Option(name: .long, help: "Output format: png or pdf.")
    var format: OutputFormat = .png

    @Option(name: .long, help: "Scale factor for PNG output.")
    var scale: Int = 2

    @OptionGroup var themePin: ThemeOption

    @Option(name: .long, help: "JSON dictionary of variable overrides.")
    var vars: String?

    @Option(name: .long, help: "Path to a JSON file of variable overrides.")
    var varsFile: String?

    @Option(name: .long, help: "Output directory (defaults to input file's directory).")
    var outputDir: String?

    @Flag(name: .long, help: "Fail on warnings (missing fonts, broken refs, etc.); notices never fail.")
    var strict: Bool = false

    /// Reads the file, settles each theme combination's layout and writes the images.
    ///
    /// - Throws: ``CommandFailure`` when the .pen file cannot be read, and whatever
    ///   the parser, the layout engine or the exporters throw.
    func run() async throws {
        let inputURL = try input.existingFile()
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let outputDirectory = outputDir.map { URL(fileURLWithPath: $0) }
            ?? inputURL.deletingLastPathComponent()
        let diagnostics = PenDiagnosticCollector()

        // 1–3. Parse, read the libraries the file imports, and expand refs — keeping
        // reusable definitions: a definition placed in visible flow is an artboard
        // like any other, exactly as it is for `shot`, `tree` and the viewer.
        let document = try await PenFileTransaction.read(
            at: inputURL, diagnostics: diagnostics, fonts: .shared
        ) { editable in
            editable.readContext.libraries.report(into: diagnostics)
            return editable.expanded(for: .canvas)
        }.value
        // Once per document, not per theme combination: the same shaders go undrawn in each.
        if let shaders = ShaderFills.diagnostic(under: document.children) {
            diagnostics.add(shaders)
        }

        // 4. Parse variable overrides
        let variableOverrides = try parseVariableOverrides()

        // 5. Compute theme combinations
        let pins = try ThemePinParser.parse(themePin.theme)
        let combinations = ThemeCombination.allCombinations(
            from: document.themes, pins: pins
        )
        let useSubdirectories = combinations.count > 1
        // Decided once for the document, not per combination: an artboard keeps the
        // same file name in every theme's subdirectory, even in a combination where
        // it happens to be the only one that matches.
        let isMultiFrame = document.children.count { node in
            if case .frame = node.kind { return true }
            return false
        } > 1

        // 6. Render each theme combination
        var totalFiles = 0
        for combo in combinations {
            // Resolve variables with this theme
            let resolved = PenVariableResolver.resolve(
                document, theme: combo, overrides: variableOverrides
            )

            // Resolve fonts
            await GoogleFontResolver.shared.prepareFonts(
                for: resolved, relativeTo: inputURL, diagnostics: diagnostics
            )

            // Download the images that remote image fills point at
            await RemoteImageResolver.shared.prepareImages(
                for: resolved, diagnostics: diagnostics
            )

            // Layout
            let rects = PenLayoutEngine.layout(resolved)

            // Discover frames matching this theme combination
            let frames = resolved.children.filter { node in
                guard case .frame = node.kind else { return false }
                return ThemeCombination.frameMatches(
                    theme: node.common.theme, combination: combo
                )
            }

            guard !frames.isEmpty else { continue }

            // Determine output subdirectory
            let comboDir: URL = if useSubdirectories, let subdir = ThemeCombination.subdirectoryName(for: combo) {
                outputDirectory.appendingPathComponent(subdir)
            } else {
                outputDirectory
            }

            totalFiles += format == .pdf ? 1 : frames.count
            let themeValues: [String] = useSubdirectories
                ? combo.sorted(by: { $0.key < $1.key }).map(\.value)
                : []

            let imageProvider = PenRenderer.imageProvider(
                relativeTo: inputURL.deletingLastPathComponent()
            )

            switch format {
            case .png:
                try renderPNG(
                    frames: frames, resolved: resolved, rects: rects,
                    baseName: baseName, isMultiFrame: isMultiFrame,
                    outputDir: comboDir, activeThemeValues: themeValues,
                    imageProvider: imageProvider
                )
            case .pdf:
                try renderPDF(
                    frames: frames, resolved: resolved, rects: rects,
                    baseName: baseName, isMultiFrame: isMultiFrame,
                    outputDir: comboDir, imageProvider: imageProvider
                )
            }
        }

        // Report diagnostics
        if diagnostics.hasIssues {
            for diagnostic in diagnostics.diagnostics {
                FileHandle.standardError.write(
                    Data("\(diagnostic)\n".utf8)
                )
            }
            // A notice — a file from a newer Pen — is something to read, not a failure.
            if strict, diagnostics.contains(atLeast: .warning) {
                throw ExitCode.failure
            }
        }

        print("Rendered \(totalFiles) file(s) to \(outputDirectory.path)")
    }

    // MARK: - PNG Rendering

    private func renderPNG(
        frames: [PenNode],
        resolved: PenDocument,
        rects: [String: PenRect],
        baseName: String,
        isMultiFrame: Bool,
        outputDir: URL,
        activeThemeValues: [String] = [],
        imageProvider: @escaping PenRenderer.ImageProvider
    ) throws {
        for frame in frames {
            guard let frameRect = rects[frame.id] else { continue }
            let size = CGSize(width: frameRect.width, height: frameRect.height)

            guard let image = PenRenderer.render(
                resolved, layoutRects: rects, size: size,
                scale: CGFloat(scale), rootNodeID: frame.id,
                imageProvider: imageProvider
            ) else {
                throw RenderError.renderFailed(frame.common.name ?? frame.id)
            }

            let filename = OutputNamer.filename(
                baseName: baseName,
                frameName: frame.common.name,
                format: .png,
                scale: scale,
                isMultiFrame: isMultiFrame,
                activeThemeValues: activeThemeValues
            )
            let outputURL = outputDir.appendingPathComponent(filename)
            try ImageExporter.writePNG(image, to: outputURL)
        }
    }

    // MARK: - PDF Rendering

    private func renderPDF(
        frames: [PenNode],
        resolved: PenDocument,
        rects: [String: PenRect],
        baseName: String,
        isMultiFrame: Bool,
        outputDir: URL,
        imageProvider: @escaping PenRenderer.ImageProvider
    ) throws {
        let filename = OutputNamer.filename(
            baseName: baseName, frameName: nil, format: .pdf,
            scale: scale, isMultiFrame: isMultiFrame
        )
        let outputURL = outputDir.appendingPathComponent(filename)

        let pages: [PDFExporter.Page] = frames.compactMap { frame in
            PDFExporter.Page(
                frame: frame.id, of: resolved, layoutRects: rects, imageProvider: imageProvider
            )
        }

        try PDFExporter.writePDF(pages: pages, to: outputURL)
    }

    // MARK: - Variable Overrides

    private func parseVariableOverrides() throws -> [String: AnyCodable] {
        var overrides: [String: AnyCodable] = [:]

        if let varsFile {
            let url = URL(fileURLWithPath: varsFile)
            let data = try Data(contentsOf: url)
            let dict = try JSONDecoder().decode([String: AnyCodable].self, from: data)
            overrides.merge(dict) { _, new in new }
        }

        if let vars {
            guard let data = vars.data(using: .utf8) else {
                throw ValidationError("Invalid --vars JSON string.")
            }
            let dict = try JSONDecoder().decode([String: AnyCodable].self, from: data)
            overrides.merge(dict) { _, new in new }
        }

        return overrides
    }

    enum RenderError: Error, CustomStringConvertible {
        case renderFailed(String)

        var description: String {
            switch self {
            case let .renderFailed(name):
                "Failed to render frame '\(name)'"
            }
        }
    }
}
