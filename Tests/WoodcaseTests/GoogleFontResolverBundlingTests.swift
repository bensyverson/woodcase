//
//  GoogleFontResolverBundlingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Which files a generated package bundles for the text faces its views set
/// (``GoogleFontResolver/fontBundle(for:declaredIn:relativeTo:)``): a declared family's
/// own files, the Google Fonts file of each face drawn (from the cache, or downloaded
/// into it), nothing for a family the OS ships, and a reason for each family no file was
/// found for.
///
/// Nothing here registers a font: the bundle is files to copy, and Core Text
/// registration is process-global (`project/gotchas.md`, 2026-09-02).
@Suite("GoogleFontResolver bundling")
struct GoogleFontResolverBundlingTests {
    private static let fontsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fonts")

    private static func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoogleFontResolverBundlingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func resolver(cache: URL, responses: [String: Result<Data, Error>] = [:]) -> GoogleFontResolver {
        GoogleFontResolver(cache: GoogleFontCache(rootDirectory: cache), fetcher: MockFontFetcher(responses: responses))
    }

    /// Each family's regular face.
    private static func regular(_ families: String...) -> Set<PenFontFace> {
        Set(families.map(PenFontFace.regular(of:)))
    }

    @Test("A declared family bundles every file declared for it, resolved against the .pen file")
    func declaredFamily() async throws {
        let root = try Self.scratch()
        for name in ["IBMPlexMono-Regular.ttf", "IBMPlexMono-Bold.ttf"] {
            try FileManager.default.copyItem(
                at: Self.fontsDirectory.appendingPathComponent("GoogleFonts/\(name)"), to: root.appendingPathComponent(name)
            )
        }
        var document = PenDocument(children: [])
        document.fonts = [
            PenFontDeclaration(name: "Pack Declared", url: "IBMPlexMono-Regular.ttf"),
            PenFontDeclaration(name: "Pack Declared", url: "IBMPlexMono-Bold.ttf"),
            PenFontDeclaration(name: "Unused", url: "Unused.ttf"),
        ]
        let resolver = Self.resolver(cache: root.appendingPathComponent("cache"))
        let bundle = await resolver.fontBundle(
            for: Self.regular("Pack Declared"), declaredIn: document, relativeTo: root.appendingPathComponent("design.pen")
        )
        #expect(bundle.files.map(\.lastPathComponent) == ["IBMPlexMono-Bold.ttf", "IBMPlexMono-Regular.ttf"])
        #expect(bundle.missing.isEmpty)
    }

    @Test("A declared file that is not there is missing, naming where it was looked for")
    func declaredFileMissing() async throws {
        let root = try Self.scratch()
        var document = PenDocument(children: [])
        document.fonts = [PenFontDeclaration(name: "Pack Gone", url: "gone.ttf")]
        let resolver = Self.resolver(cache: root.appendingPathComponent("cache"))
        let bundle = await resolver.fontBundle(
            for: Self.regular("Pack Gone"), declaredIn: document, relativeTo: root.appendingPathComponent("design.pen")
        )
        #expect(bundle.files.isEmpty)
        #expect(bundle.missing.map(\.family) == ["Pack Gone"])
        #expect(bundle.missing.first?.reason.contains("gone.ttf") == true)
    }

    /// Until faces were resolved this bundled every file in the family's cache
    /// directory, whichever faces the views drew; now it bundles the file each drawn face
    /// needs, as the cached METADATA names it — and never a cached face nothing draws.
    @Test("A cached Google family bundles the file of each face drawn, and no other")
    func cachedFamily() async throws {
        let cache = try Self.scratch()
        let directory = cache.appendingPathComponent(GoogleFontCache.directoryName(for: "Pack Cached"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(Self.packCachedMetadata.utf8).write(to: directory.appendingPathComponent("METADATA.pb"))
        for name in ["PackCached[wght].ttf", "PackCached-Italic[wght].ttf", "notes.txt"] {
            try Data("x".utf8).write(to: directory.appendingPathComponent(name))
        }
        let upright = await Self.resolver(cache: cache).fontBundle(
            for: [PenFontFace(family: "Pack Cached", weight: 700, style: .normal)],
            declaredIn: PenDocument(children: []), relativeTo: nil
        )
        #expect(upright.files.map(\.lastPathComponent) == ["PackCached[wght].ttf"])
        let both = await Self.resolver(cache: cache).fontBundle(
            for: [PenFontFace(family: "Pack Cached", weight: 400, style: .normal), PenFontFace(family: "Pack Cached", weight: 400, style: .italic)],
            declaredIn: PenDocument(children: []), relativeTo: nil
        )
        #expect(both.files.map(\.lastPathComponent) == ["PackCached-Italic[wght].ttf", "PackCached[wght].ttf"])
    }

    @Test("A drawn face the cache lacks is downloaded into it and bundled beside the cached ones")
    func missingFaceDownloaded() async throws {
        let cache = try Self.scratch()
        let directory = cache.appendingPathComponent(GoogleFontCache.directoryName(for: "Pack Cached"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory.appendingPathComponent("PackCached[wght].ttf"))
        let resolver = Self.resolver(cache: cache, responses: [
            "ofl/packcached/METADATA.pb": .success(Data(Self.packCachedMetadata.utf8)),
            "ofl/packcached/PackCached-Italic[wght].ttf": .success(GoogleFontResolverTests.fakeTTFData),
        ])
        let bundle = await resolver.fontBundle(
            for: [PenFontFace(family: "Pack Cached", weight: 400, style: .normal), PenFontFace(family: "Pack Cached", weight: 400, style: .italic)],
            declaredIn: PenDocument(children: []), relativeTo: nil
        )
        #expect(bundle.missing.isEmpty)
        #expect(bundle.files.map(\.lastPathComponent) == ["PackCached-Italic[wght].ttf", "PackCached[wght].ttf"])
        #expect(FileManager.default.contents(atPath: directory.appendingPathComponent("PackCached-Italic[wght].ttf").path)
            == GoogleFontResolverTests.fakeTTFData)
    }

    /// A variable family with a separate italic file.
    private static let packCachedMetadata = """
    name: "Pack Cached"
    fonts {
      style: "normal"
      weight: 400
      filename: "PackCached[wght].ttf"
    }
    fonts {
      style: "italic"
      weight: 400
      filename: "PackCached-Italic[wght].ttf"
    }
    """

    @Test("A family the OS ships is left to the system and never fetched")
    func systemFamily() async throws {
        let cache = try Self.scratch()
        let bundle = await Self.resolver(cache: cache).fontBundle(
            for: Self.regular("Helvetica"), declaredIn: PenDocument(children: []), relativeTo: nil
        )
        #expect(bundle.systemFamilies == ["Helvetica"])
        #expect(bundle.files.isEmpty)
        #expect(bundle.missing.isEmpty)
    }

    @Test("A Google family not yet cached is downloaded into the cache, and that file is bundled")
    func downloadedFamily() async throws {
        let cache = try Self.scratch()
        let metadata = GoogleFontResolverTests.sampleMetadata.replacingOccurrences(of: "Manrope", with: "Packdl")
        let resolver = Self.resolver(cache: cache, responses: [
            "ofl/packdl/METADATA.pb": .success(Data(metadata.utf8)),
            "ofl/packdl/Packdl[wght].ttf": .success(GoogleFontResolverTests.fakeTTFData),
        ])
        let bundle = await resolver.fontBundle(for: Self.regular("Packdl"), declaredIn: PenDocument(children: []), relativeTo: nil)
        let file = try #require(bundle.files.first)
        #expect(bundle.files.count == 1)
        #expect(file.path.hasPrefix(cache.path))
        #expect(FileManager.default.contents(atPath: file.path) == GoogleFontResolverTests.fakeTTFData)
    }

    @Test("A family Google Fonts does not have is missing, with the reason")
    func unknownFamily() async throws {
        let cache = try Self.scratch()
        let bundle = await Self.resolver(cache: cache).fontBundle(
            for: Self.regular("Pack Nowhere"), declaredIn: PenDocument(children: []), relativeTo: nil
        )
        #expect(bundle.files.isEmpty)
        #expect(bundle.missing.map(\.family) == ["Pack Nowhere"])
        #expect(bundle.missing.first?.reason.contains("Google Fonts has no family") == true)
    }
}
