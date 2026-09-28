//
//  FontFallbackNoticeTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

/// The two reasons a font is missing, told apart.
///
/// One sentence used to cover both: a family nobody has downloaded, and a cache
/// directory that is right there and unreadable. A reader who followed its advice —
/// run `shot` once — saw the identical line again, with no path to check. The trial of
/// 2026-09-08 spent an hour on that; these tests pin the two sentences apart.
@Suite("What the font-fallback notice says, and why")
struct FontFallbackNoticeTests {
    /// A family name no font registry will ever answer to.
    static let missingFamily = "Woodcase No Such Face"

    @Test("A family nobody has downloaded names the directory the download lands in")
    func neverDownloadedNamesTheCacheDirectory() throws {
        let root = Self.makeCacheRoot()
        let resolver = Self.makeResolver(cacheRoot: root)
        let diagnostics = PenDiagnosticCollector()

        try resolver.prepareCachedFonts(for: Self.missingFontDocument(), diagnostics: diagnostics)

        let message = try #require(diagnostics.diagnostics.first).message
        #expect(message.contains(Self.missingFamily))
        #expect(message.contains(root.path), "the notice does not name the cache directory")
        #expect(message.contains("not in the font cache"))
        #expect(message.contains("woodcase shot"), "the notice no longer says how to fill the cache")
    }

    @Test("A cache directory that cannot be read says so, and does not suggest a download")
    func unreadableCacheSaysSoInstead() throws {
        let root = Self.makeCacheRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        try #require(
            !FileManager.default.isReadableFile(atPath: root.path),
            "this test needs a directory the test process cannot read; it must not run as root"
        )

        let resolver = Self.makeResolver(cacheRoot: root)
        let diagnostics = PenDiagnosticCollector()

        try resolver.prepareCachedFonts(for: Self.missingFontDocument(), diagnostics: diagnostics)

        let message = try #require(diagnostics.diagnostics.first).message
        #expect(message.contains(Self.missingFamily))
        #expect(message.contains(root.path), "the notice does not name the cache directory")
        #expect(message.contains("cannot be read"))
        #expect(
            !message.contains("woodcase shot"),
            "a download would not fix an unreadable cache, so the notice must not suggest one"
        )
    }

    // MARK: - Support

    /// A cache root inside the temporary directory, not created.
    private static func makeCacheRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FontFallbackNotice-\(UUID().uuidString)", isDirectory: true)
    }

    /// A resolver over that root whose fetcher answers nothing, so nothing resolves.
    private static func makeResolver(cacheRoot: URL) -> GoogleFontResolver {
        GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: cacheRoot),
            fetcher: MockFontFetcher()
        )
    }

    /// The fixture naming ``missingFamily``.
    private static func missingFontDocument() throws -> PenDocument {
        let url = try #require(
            Bundle.module.url(forResource: "font-missing", withExtension: "pen", subdirectory: "Fixtures")
        )
        return try PenParser.parse(contentsOf: url)
    }
}
