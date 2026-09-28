import Foundation
import Testing
@testable import Woodcase

/// Pins the `@font-face` rules ``ReactHarnessBuilder`` writes for a font directory: each
/// face is named by the family its file declares, never by the file's name, and carries
/// the weights the file can draw.
///
/// A face named after its file is a face no page asks for: `Inter[opsz,wght].ttf` became
/// family `Inter[opsz,wght]`, so every harness page that set `font-family: Inter` drew
/// the browser's serif instead (leaf `vXVtb1`).
@Suite("ReactHarnessBuilder font faces")
struct ReactHarnessBuilderFontFaceTests {
    /// The fonts the WebView suites load: variable IBM Plex Sans, Inter, JetBrains Mono and
    /// the two resolver fixtures, and the static Google faces in its `GoogleFonts` folder.
    private static let fontDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fonts")

    /// The `@font-face` rule whose `src` names `file`, or `nil` when there is none.
    private static func face(for file: String) -> String? {
        let html = ReactHarnessBuilder.buildHTML(
            from: [],
            componentName: "Missing",
            viewportWidth: 100,
            fontRelativePath: "Fonts",
            fontDir: fontDir
        )
        return html.components(separatedBy: "@font-face").first { $0.contains("url('Fonts/\(file)')") }
    }

    @Test("A variable font's face takes the family its name table declares", arguments: [
        ("Inter[opsz,wght].ttf", "Inter"),
        ("IBMPlexSans[wdth,wght].ttf", "IBM Plex Sans"),
        ("JetBrainsMono[wght].ttf", "JetBrains Mono"),
        ("WoodcaseDeclaredMono.ttf", "Woodcase Declared Mono"),
    ])
    func variableFamily(file: String, family: String) throws {
        let face = try #require(Self.face(for: file))
        #expect(face.contains("font-family: '\(family)';"), "\(file): \(face)")
    }

    @Test("A variable font's face spans its weight axis", arguments: [
        ("Inter[opsz,wght].ttf", "100 900"),
        ("IBMPlexSans[wdth,wght].ttf", "100 700"),
        ("JetBrainsMono[wght].ttf", "100 800"),
    ])
    func variableWeightRange(file: String, range: String) throws {
        let face = try #require(Self.face(for: file))
        #expect(face.contains("font-weight: \(range);"), "\(file): \(face)")
    }

    @Test("A static font's face takes its family and its OS/2 weight class", arguments: [
        ("GoogleFonts/IBMPlexMono-Regular.ttf", "IBM Plex Mono", 400),
        ("GoogleFonts/IBMPlexMono-Bold.ttf", "IBM Plex Mono", 700),
        ("GoogleFonts/Spectral-Bold.ttf", "Spectral", 700),
    ])
    func staticWeight(file: String, family: String, weight: Int) throws {
        let face = try #require(Self.face(for: file))
        #expect(face.contains("font-family: '\(family)';"), "\(file): \(face)")
        #expect(face.contains("font-weight: \(weight);"), "\(file): \(face)")
    }

    @Test("An upright font's face says so")
    func uprightStyle() throws {
        let face = try #require(Self.face(for: "IBMPlexSans[wdth,wght].ttf"))
        #expect(face.contains("font-style: normal;"), "\(face)")
    }

    @Test("A font in a folder of the directory gets its face too, at its path under the directory", arguments: [
        ("GoogleFonts/IBMPlexMono-Bold.ttf", "IBM Plex Mono", "700", "normal"),
        ("GoogleFonts/IBMPlexMono-BoldItalic.ttf", "IBM Plex Mono", "700", "italic"),
        ("GoogleFonts/Inter-Italic[opsz,wght].ttf", "Inter", "100 900", "italic"),
        ("GoogleFonts/Spectral-Regular.ttf", "Spectral", "400", "normal"),
    ])
    func nestedFace(file: String, family: String, weight: String, style: String) throws {
        let face = try #require(Self.face(for: file))
        #expect(face.contains("font-family: '\(family)';"), "\(file): \(face)")
        #expect(face.contains("font-weight: \(weight);"), "\(file): \(face)")
        #expect(face.contains("font-style: \(style);"), "\(file): \(face)")
    }

    @Test("No face is named after its file")
    func noFileNamedFace() {
        let html = ReactHarnessBuilder.buildHTML(
            from: [],
            componentName: "Missing",
            viewportWidth: 100,
            fontRelativePath: "Fonts",
            fontDir: Self.fontDir
        )
        #expect(!html.contains("font-family: 'Inter[opsz,wght]'"))
        #expect(!html.contains("font-family: 'JetBrainsMono[wght]'"))
    }
}
