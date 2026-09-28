//
//  SettledFontPreparationTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

/// The one font path every verb takes: a read registers the faces this machine
/// already has before it measures a single glyph.
///
/// `shot` and `render` prepared fonts and the read verbs did not, so `tree` measured a
/// cached Google font in SF Pro while `shot` measured it in the real face and the two
/// disagreed about every text width (D1). The fix goes in ``SettledTree`` — the one
/// place a read settles a document — so `tree`, `lint` and every write verb that
/// prints a settled tree measure in the face the render will use.
///
/// Preparation on a read is deliberately **offline**: it takes the system faces and
/// the disk cache and stops. A read that downloaded a font would be a read that hangs
/// on a captive portal, and `lint` promises in its own help that it never goes to the
/// network. What a read cannot resolve it says so about, rather than reporting a width
/// in a face the render will not use.
///
/// ## Where the disk-cache claim lives
///
/// Registering a face with CoreText is process-global and irreversible, so exactly one
/// test in this package may watch a family go from absent to present —
/// `GoogleFontResolverTests.cachedFontRegistersWithCoreText`, which owns that
/// transition and carries the "a cached TTF changes the settled width" claim with it.
/// A second test wanting the same family would race it. This suite therefore works
/// with families that are *already* placed and families that never will be, which is
/// everything else the read path has to get right.
@MainActor
@Suite("Font preparation on a settled read")
struct SettledFontPreparationTests {
    /// A family the test bundle registers at startup, so it is available without this
    /// suite changing anything process-wide.
    static let installedFamily = "IBM Plex Sans"

    /// A family name no font registry will ever answer to.
    static let unresolvableFamily = "Woodcase No Such Face"

    /// A resolver whose cache directory is empty and whose fetcher answers nothing —
    /// so anything it resolves came from the system, and anything it does not is a
    /// clean miss.
    static func makeResolver() -> GoogleFontResolver {
        GoogleFontResolver(
            cache: GoogleFontCache(
                rootDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("SettledFontPreparation-\(UUID().uuidString)")
            ),
            fetcher: MockFontFetcher()
        )
    }

    /// Loads a fixture from the test bundle.
    static func document(_ fixture: String) throws -> PenDocument {
        let base = (fixture as NSString).deletingPathExtension
        let ext = (fixture as NSString).pathExtension
        let url = try #require(
            Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures")
        )
        return try PenParser.parse(contentsOf: url)
    }

    // MARK: - What it can place

    @Test("A family this machine already has needs no network and no cache")
    func installedFamilyIsPlaced() throws {
        TestFontRegistration.registerTestFonts()
        let resolver = Self.makeResolver()

        #expect(try resolver.prepareCachedFonts(for: Self.document("font-system.pen")).isEmpty)
        #expect(PenTextMeasurer.fontFamilyAvailable(Self.installedFamily))
    }

    @Test("A settled read measures the placed family, not the fallback")
    func settledWidthIsTheInstalledFace() throws {
        TestFontRegistration.registerTestFonts()
        let document = try EditableDocument(from: Self.document("font-system.pen"))

        document.readContext = PenReadContext(fonts: Self.makeResolver())

        let settled = SettledTree(document: document, theme: [:])

        let rect = try #require(settled.rects["Txt01"])
        let inFace = PenTextMeasurer.measure(
            "Handgloves", fontFamily: Self.installedFamily, fontSize: 32
        )
        #expect(abs(rect.width - inFace.width) < 0.5)
    }

    // MARK: - What it cannot place, it says

    @Test("A family that is neither installed nor cached comes back unresolved")
    func unresolvableFamilyIsReported() throws {
        let resolver = Self.makeResolver()

        let unresolved = try resolver.prepareCachedFonts(for: Self.document("font-missing.pen"))

        #expect(unresolved == [Self.unresolvableFamily])
    }

    @Test("The fallback warning names the font and the face the measurement used")
    func fallbackWarningNamesFontAndFace() throws {
        let resolver = Self.makeResolver()
        let diagnostics = PenDiagnosticCollector()

        try resolver.prepareCachedFonts(
            for: Self.document("font-missing.pen"), diagnostics: diagnostics
        )

        let warning = try #require(diagnostics.diagnostics.first)
        #expect(warning.severity == .warning)
        #expect(warning.stage == .fontResolution)
        #expect(warning.message.contains(Self.unresolvableFamily))
        #expect(warning.message.contains(PenTextMeasurer.defaultFontFamily))
    }

    @Test("With no collector the warning goes to standard error, once per family")
    func noCollectorMeansStandardError() throws {
        let resolver = Self.makeResolver()

        try resolver.prepareCachedFonts(for: Self.document("font-missing.pen"))
        try resolver.prepareCachedFonts(for: Self.document("font-missing.pen"))

        #expect(resolver.fallbackNoticeCount == 1)
    }

    @Test("A collector takes the warning instead of standard error, never as well")
    func collectorSuppressesTheStandardErrorLine() throws {
        let resolver = Self.makeResolver()
        let diagnostics = PenDiagnosticCollector()

        try resolver.prepareCachedFonts(
            for: Self.document("font-missing.pen"), diagnostics: diagnostics
        )

        #expect(diagnostics.diagnostics.count == 1)
        #expect(resolver.fallbackNoticeCount == 0)
    }

    @Test("The download path reports on standard error when its caller collects nothing")
    func downloadPathWithoutACollectorAlsoReports() async throws {
        // Every fetch 404s, so the family stays unresolved — `shot`'s case exactly,
        // since it passes no collector.
        let resolver = Self.makeResolver()

        try await resolver.prepareFonts(for: Self.document("font-missing.pen"))

        #expect(resolver.fallbackNoticeCount == 1)
    }

    @Test("An offline miss does not stop a later download of the same family")
    func offlineMissDoesNotPoisonTheSession() async throws {
        let cache = GoogleFontCache(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("OfflineMiss-\(UUID().uuidString)", isDirectory: true)
        )
        let fetcher = MockFontFetcher(responses: [
            "METADATA.pb": .success(Data(GoogleFontResolverTests.sampleMetadata.utf8)),
            "Manrope[wght].ttf": .success(GoogleFontResolverTests.fakeTTFData),
        ])
        let resolver = GoogleFontResolver(cache: cache, fetcher: fetcher)
        let document = try GoogleFontResolverTests.measuringDocument(in: "Manrope")

        // A read misses: Manrope is neither installed nor cached.
        #expect(resolver.prepareCachedFonts(for: document) == ["Manrope"])

        // A render in the same process must still be able to fetch it — the miss is
        // not an attempt, so it must not have been recorded as one.
        #expect(await !resolver.resolve([PenFontFace.regular(of: "Manrope")]).isEmpty)
    }
}
