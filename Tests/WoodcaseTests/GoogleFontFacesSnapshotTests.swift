//
//  GoogleFontFacesSnapshotTests.swift
//  WoodcaseTests
//

import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Woodcase

/// Google families draw bold and italic in the face the document asks for, as Pen does
/// (finding F3 of `project/2026-09-27-fidelity-gaps.md`).
///
/// `render-font-faces.pen` sets one line per board in IBM Plex Mono (400, 700, italic,
/// 700 italic), Spectral (400, 700, italic), Inter and Lora italic (variable families
/// with a separate italic file) and Instrument Serif italic. The references are Pen's 2x
/// exports (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-font-faces.pen --scale 2`).
///
/// The fonts come the way a render gets them: ``GoogleFontResolver/prepareFonts(for:diagnostics:)``
/// against an empty cache, fetching from ``LocalGoogleFontsFetcher/committed`` rather
/// than GitHub — except Instrument Serif, whose Regular and Italic files are put in the
/// cache first, the warm-cache case where the resolver used to register whichever file
/// listed first and draw upright text in italic.
///
/// Core Text registration is process-wide and irreversible, and exactly one test per run
/// may watch a family go from absent to present (`project/gotchas.md`, 2026-09-02). IBM
/// Plex Mono, Spectral, Lora and Instrument Serif belong to this suite; no other suite
/// registers them. So the preparation runs once, in ``preparation``, and every test here
/// awaits it rather than preparing its own.
@Suite("Google font faces")
struct GoogleFontFacesSnapshotTests {
    /// Inter's upright file is the test target's (`TestFontRegistration`); only its
    /// italic comes through the resolver.
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let fixture = "render-font-faces"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// The resolver's run over the fixture, once per process: the font files it asked
    /// the fetcher for. `ReactRenderWebViewTests` awaits it too, so its CG side draws these
    /// faces whichever suite runs first.
    static let preparation = Task<[String], Error> {
        TestFontRegistration.registerTestFonts()
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoogleFontFacesSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        let warm = cache.appendingPathComponent("instrumentserif", isDirectory: true)
        try FileManager.default.createDirectory(at: warm, withIntermediateDirectories: true)
        let committed = LocalGoogleFontsFetcher.committedDirectory
        for (source, target) in [
            ("InstrumentSerif-Italic.ttf", "InstrumentSerif-Italic.ttf"),
            ("InstrumentSerif-Regular.ttf", "InstrumentSerif-Regular.ttf"),
            ("instrumentserif.METADATA.pb", "METADATA.pb"),
        ] {
            try FileManager.default.copyItem(
                at: committed.appendingPathComponent(source), to: warm.appendingPathComponent(target)
            )
        }
        let fetcher = LocalGoogleFontsFetcher.committed
        let resolver = GoogleFontResolver(cache: GoogleFontCache(rootDirectory: cache), fetcher: fetcher)
        try await resolver.prepareFonts(for: document(), diagnostics: PenDiagnosticCollector())
        return fetcher.requestedFontFiles
    }

    private static func document() throws -> PenDocument {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("\(fixture).pen"))
        return try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
    }

    @Test("On an empty cache, each face drawn is fetched: Plex Mono and Spectral per face, Lora and Inter their italic file")
    func fetchesEachFaceDrawn() async throws {
        let requested = try await Self.preparation.value
        #expect(Set(requested) == [
            "ibmplexmono/IBMPlexMono-Regular.ttf", "ibmplexmono/IBMPlexMono-Bold.ttf",
            "ibmplexmono/IBMPlexMono-Italic.ttf", "ibmplexmono/IBMPlexMono-BoldItalic.ttf",
            "spectral/Spectral-Regular.ttf", "spectral/Spectral-Bold.ttf", "spectral/Spectral-Italic.ttf",
            "lora/Lora-Italic[wght].ttf", "inter/Inter-Italic[opsz,wght].ttf",
        ])
    }

    /// The face Core Text resolves for each (family, weight, style) the fixture draws, and
    /// the upright Instrument Serif it does not — the face a warm cache used to lose.
    private static let faces: [(String, String, String, String)] = [
        ("IBM Plex Mono", "400", "normal", "IBMPlexMono-Regular"),
        ("IBM Plex Mono", "700", "normal", "IBMPlexMono-Bold"),
        ("IBM Plex Mono", "400", "italic", "IBMPlexMono-Italic"),
        ("IBM Plex Mono", "700", "italic", "IBMPlexMono-BoldItalic"),
        ("Spectral", "700", "normal", "Spectral-Bold"),
        ("Spectral", "400", "italic", "Spectral-Italic"),
        ("Lora", "400", "italic", "Lora-Italic"),
        ("Inter", "400", "italic", "Inter-Italic"),
        ("Instrument Serif", "400", "normal", "InstrumentSerif-Regular"),
        ("Instrument Serif", "400", "italic", "InstrumentSerif-Italic"),
    ]

    @Test("Weight and style pick the registered face", arguments: faces)
    func weightAndStylePickTheFace(family: String, weight: String, style: String, postScriptName: String) async throws {
        _ = try await Self.preparation.value
        let font = PenTextMeasurer.resolveFont(family: family, size: 32, weight: weight, style: style)
        #expect(CTFontCopyPostScriptName(font) as String == postScriptName)
    }

    /// MAE ceilings against Pen's render at 2x: the leaf's gate of 3.0, which is tighter
    /// than the margin rule (max(measured×1.5, measured+0.25),
    /// `project/2026-09-26-mae-margin-rule.md`) would set for every board, so the rule's
    /// "never looser than the bar it replaces" keeps 3.0 throughout. A board drawn in the
    /// wrong face scores 7 to 16, far above it.
    ///
    /// Measured 2026-09-27 (leaf DAmmQF, `swift test -j 3 --filter GoogleFontFacesSnapshotTests`):
    /// plexmono-400 2.464, plexmono-700 2.414, plexmono-italic 2.626, plexmono-700-italic
    /// 2.539, spectral-400 2.245, spectral-700 2.196, spectral-italic 2.422, inter-italic
    /// 2.466, lora-italic 2.696, instrumentserif-italic 2.678. What is left is the regular
    /// controls' glyph mismatch, not the face.
    ///
    /// Before per-face resolution, the same test printed the figures the finding measured
    /// with `woodcase shot` + `scripts/png-mae`: with `woodcase shot` + `scripts/png-mae` (the finding's table):
    /// plexmono-400 2.46, plexmono-700 7.32, plexmono-italic 8.54, plexmono-700-italic
    /// 11.02, spectral-400 2.25, spectral-700 15.76, spectral-italic 14.07, inter-italic
    /// 13.82, lora-italic 14.81, instrumentserif-italic 2.68.
    private static let maeCeilings: [(String, Double)] = [
        ("plexmono-400", 3.0), ("plexmono-700", 3.0), ("plexmono-italic", 3.0), ("plexmono-700-italic", 3.0),
        ("spectral-400", 3.0), ("spectral-700", 3.0), ("spectral-italic", 3.0),
        ("inter-italic", 3.0), ("lora-italic", 3.0), ("instrumentserif-italic", 3.0),
    ]

    @Test("Each board draws its face within its MAE ceiling against Pen", arguments: maeCeilings)
    func matchesPen(artboard: String, ceiling: Double) async throws {
        _ = try await Self.preparation.value
        let image = try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: 2
        )
        let rendered = try #require(image)
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Font face \(artboard) MAE: \(mae)")
        #expect(mae < ceiling, "\(artboard): MAE \(mae)")
    }
}
