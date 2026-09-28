//
//  GoogleFontResolverTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

/// Mock fetcher that returns canned responses for specific URL patterns.
struct MockFontFetcher: RemoteDataFetching {
    var responses: [String: Result<Data, Error>] = [:]

    func fetch(url: URL) async throws -> Data {
        // Match on the last path components to keep tests readable.
        // Use removingPercentEncoding so patterns can use raw brackets.
        let decoded = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        for (pattern, result) in responses {
            if decoded.contains(pattern) {
                switch result {
                case let .success(data): return data
                case let .failure(error): throw error
                }
            }
        }
        throw RemoteFetchError.httpError(statusCode: 404)
    }
}

@Suite("GoogleFontResolver")
struct GoogleFontResolverTests {
    static let sampleMetadata = """
    name: "Manrope"
    designer: "Mikhail Sharanda"
    license: "OFL"
    fonts {
      name: "Manrope"
      style: "normal"
      weight: 400
      filename: "Manrope[wght].ttf"
      post_script_name: "Manrope-Regular"
      full_name: "Manrope Regular"
    }
    axes {
      tag: "wght"
      min_value: 200.0
      max_value: 800.0
    }
    """

    static let fakeTTFData = Data("fake-ttf-data-for-testing".utf8)

    /// Creates a resolver with a mock fetcher and a temporary cache directory.
    static func makeResolver(
        responses: [String: Result<Data, Error>] = [:]
    ) -> (GoogleFontResolver, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cache = GoogleFontCache(rootDirectory: tempDir)
        let fetcher = MockFontFetcher(responses: responses)
        let resolver = GoogleFontResolver(cache: cache, fetcher: fetcher)
        return (resolver, tempDir)
    }

    // MARK: - collectFontFamilies

    @Test("Collects font families from text nodes")
    func collectsFromTextNodes() {
        let doc = PenDocument(children: [
            PenNode(
                id: "1",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(fontFamily: .literal("Manrope")))
            ),
        ])
        let families = GoogleFontResolver.collectFontFamilies(from: doc)
        #expect(families.contains("Manrope"))
    }

    @Test("Collects font families from nested frame children")
    func collectsFromNestedFrames() {
        let doc = PenDocument(children: [
            PenNode(
                id: "1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(
                        id: "2",
                        common: PenNodeCommon(),
                        kind: .text(PenNode.TextData(fontFamily: .literal("Lato")))
                    ),
                ]))
            ),
        ])
        let families = GoogleFontResolver.collectFontFamilies(from: doc)
        #expect(families.contains("Lato"))
    }

    @Test("Deduplicates font families")
    func deduplicatesFamilies() {
        let doc = PenDocument(children: [
            PenNode(
                id: "1",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(fontFamily: .literal("Manrope")))
            ),
            PenNode(
                id: "2",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(fontFamily: .literal("Manrope")))
            ),
        ])
        let families = GoogleFontResolver.collectFontFamilies(from: doc)
        #expect(families.count == 1)
    }

    @Test("Ignores variable references")
    func ignoresVariableReferences() {
        let doc = PenDocument(children: [
            PenNode(
                id: "1",
                common: PenNodeCommon(),
                kind: .text(PenNode.TextData(fontFamily: .variable("myFont")))
            ),
        ])
        let families = GoogleFontResolver.collectFontFamilies(from: doc)
        #expect(families.isEmpty)
    }

    // MARK: - fetchMetadata

    @Test("Fetches metadata from ofl directory first")
    func fetchesFromOfl() async throws {
        let (resolver, tempDir) = Self.makeResolver(responses: [
            "ofl/manrope/METADATA.pb": .success(Data(Self.sampleMetadata.utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadata = try await resolver.fetchMetadata(family: "Manrope")
        #expect(metadata.name == "Manrope")
    }

    @Test("Falls back to apache directory")
    func fallsBackToApache() async throws {
        let (resolver, tempDir) = Self.makeResolver(responses: [
            "apache/roboto/METADATA.pb": .success(Data(Self.sampleMetadata.utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let metadata = try await resolver.fetchMetadata(family: "Roboto")
        #expect(metadata.name == "Manrope") // content is from our sample, name check is "found something"
    }

    @Test("Throws familyNotFound when all directories fail")
    func throwsFamilyNotFound() async {
        let (resolver, tempDir) = Self.makeResolver()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await #expect(throws: GoogleFontError.self) {
            try await resolver.fetchMetadata(family: "NonexistentFont")
        }
    }

    // MARK: - Caching

    @Test("Caches downloaded font data to disk")
    func cachesToDisk() async {
        let (resolver, tempDir) = Self.makeResolver(responses: [
            "ofl/manrope/METADATA.pb": .success(Data(Self.sampleMetadata.utf8)),
            "ofl/manrope/Manrope[wght].ttf": .success(Self.fakeTTFData),
        ])
        defer { try? FileManager.default.removeItem(at: tempDir) }

        await resolver.resolve([PenFontFace.regular(of: "Manrope")])

        // Verify data was cached
        let cache = GoogleFontCache(rootDirectory: tempDir)
        let cached = cache.cachedFontData(family: "Manrope", filename: "Manrope[wght].ttf")
        #expect(cached == Self.fakeTTFData)
    }

    @Test("Uses cached data on second resolve")
    func usesCachedData() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cache = GoogleFontCache(rootDirectory: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Pre-populate cache
        try cache.cache(data: Self.fakeTTFData, family: "Manrope", filename: "Manrope[wght].ttf")

        // Create resolver with no network responses — should still work from cache
        let fetcher = MockFontFetcher()
        let resolver = GoogleFontResolver(cache: cache, fetcher: fetcher)

        let files = await resolver.resolve([PenFontFace.regular(of: "Manrope")])
        #expect(files.map { FileManager.default.contents(atPath: $0.path) } == [Self.fakeTTFData])
    }

    // MARK: - Best-effort caching

    /// A root directory that is a plain file, so `GoogleFontCache.cache` cannot create
    /// a family subdirectory under it — the same failure a read-only cache volume or a
    /// sandboxed process would produce, without needing either. Always fresh (a UUID),
    /// so `GoogleFontMemoryFallback`'s root-scoped entries never collide across tests
    /// and none of them needs to reset the process-wide store.
    private static func makeUnwritableCacheRoot() throws -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: path)
        return path
    }

    @Test("An unwritable cache directory does not stop the font from resolving")
    func unwritableCacheStillResolves() async throws {
        let blockedRoot = try Self.makeUnwritableCacheRoot()
        defer { try? FileManager.default.removeItem(at: blockedRoot) }

        let cache = GoogleFontCache(rootDirectory: blockedRoot)
        let fetcher = MockFontFetcher(responses: [
            "ofl/manrope/METADATA.pb": .success(Data(Self.sampleMetadata.utf8)),
            "ofl/manrope/Manrope[wght].ttf": .success(Self.fakeTTFData),
        ])
        let resolver = GoogleFontResolver(cache: cache, fetcher: fetcher)

        let files = await resolver.resolve([PenFontFace.regular(of: "Manrope")])
        #expect(files.map { FileManager.default.contents(atPath: $0.path) } == [Self.fakeTTFData])
    }

    @Test("An unwritable cache directory prints its notice exactly once, not once per font")
    func unwritableCacheLogsOnce() async throws {
        let blockedRoot = try Self.makeUnwritableCacheRoot()
        defer { try? FileManager.default.removeItem(at: blockedRoot) }

        let cache = GoogleFontCache(rootDirectory: blockedRoot)
        let fetcher = MockFontFetcher(responses: [
            "ofl/manrope/METADATA.pb": .success(Data(Self.sampleMetadata.utf8)),
            "ofl/manrope/Manrope[wght].ttf": .success(Self.fakeTTFData),
            "ofl/lato/METADATA.pb": .success(Data(Self.sampleMetadata.utf8)),
            "ofl/lato/Manrope[wght].ttf": .success(Self.fakeTTFData),
        ])
        let resolver = GoogleFontResolver(cache: cache, fetcher: fetcher)

        #expect(resolver.cacheFallbackNoticeCount == 0)
        await resolver.resolve([PenFontFace.regular(of: "Manrope")])
        #expect(resolver.cacheFallbackNoticeCount == 1)
        await resolver.resolve([PenFontFace.regular(of: "Lato")])
        #expect(resolver.cacheFallbackNoticeCount == 1)
    }

    @Test("A font that fell back to memory is not re-downloaded by a second resolver sharing the same broken cache")
    func memoryFallbackIsReusedAcrossResolvers() async throws {
        let blockedRoot = try Self.makeUnwritableCacheRoot()
        defer { try? FileManager.default.removeItem(at: blockedRoot) }

        let cache = GoogleFontCache(rootDirectory: blockedRoot)
        let first = GoogleFontResolver(cache: cache, fetcher: MockFontFetcher(responses: [
            "ofl/manrope/METADATA.pb": .success(Data(Self.sampleMetadata.utf8)),
            "ofl/manrope/Manrope[wght].ttf": .success(Self.fakeTTFData),
        ]))
        let firstResolve = await first.resolve([PenFontFace.regular(of: "Manrope")])
        #expect(firstResolve.map { FileManager.default.contents(atPath: $0.path) } == [Self.fakeTTFData])

        // A second resolver, same broken cache, and a fetcher that would throw if it
        // were ever asked — proving the memory fallback answered, not the network.
        let second = GoogleFontResolver(cache: cache, fetcher: MockFontFetcher())
        let secondResolve = await second.resolve([PenFontFace.regular(of: "Manrope")])
        #expect(secondResolve.map { FileManager.default.contents(atPath: $0.path) } == [Self.fakeTTFData])
    }

    // MARK: - Registration

    /// A one-text-node document in `family`, sized to its own content, so its settled
    /// rect *is* the measured width.
    static func measuringDocument(in family: String) throws -> PenDocument {
        try PenParser.parse("""
        {
          "children": [
            {
              "content": "Handgloves",
              "fill": "#000000",
              "fontFamily": "\(family)",
              "fontSize": 32,
              "height": "fit_content",
              "id": "Txt01",
              "name": "Label",
              "type": "text",
              "width": "fit_content"
            }
          ],
          "version": "2.17"
        }
        """)
    }

    /// The one test in this package that may watch "JetBrains Mono" go from absent to
    /// present.
    ///
    /// CoreText registration is process-global and irreversible, so the transition
    /// happens once per run and only one test can observe it — a second test wanting
    /// the same family races this one and loses whichever way the scheduler goes. It
    /// therefore carries every claim that needs the transition: that the bytes come
    /// from the disk cache, that registration reaches CoreText (the regression from
    /// `project/2026-08-30-font-registration-from-data.md`), that the offline read path
    /// gets there too, and that a settled width *changes* once it does — which is the
    /// whole of D1, the reason `tree` and `shot` disagreed.
    @Test("A cached TTF on disk registers so the family becomes available to CoreText")
    func cachedFontRegistersWithCoreText() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // A real variable TTF, staged where resolveCached looks. The family must be
        // one no other suite registers, or a leak from another test would green this.
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fonts")
            .appendingPathComponent("JetBrainsMono[wght].ttf")
        let familyDir = tempDir.appendingPathComponent("jetbrainsmono")
        try FileManager.default.createDirectory(at: familyDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixture,
            to: familyDir.appendingPathComponent("JetBrainsMono[wght].ttf")
        )

        let resolver = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: tempDir),
            fetcher: MockFontFetcher()
        )

        // Before: nothing has this face, so the layout measures in the fallback.
        let document = try Self.measuringDocument(in: "JetBrains Mono")
        let fallbackWidth = try #require(PenLayoutEngine.layout(document)["Txt01"]).width

        let files = await resolver.resolve([PenFontFace.regular(of: "JetBrains Mono")])

        #expect(!files.isEmpty, "the cached TTF should resolve")
        #expect(
            PenTextMeasurer.fontFamilyAvailable("JetBrains Mono"),
            "resolving must actually register the font with CoreText"
        )

        // After: the same document settles to a different width. A read that never
        // registered would have reported the first number and said nothing.
        let facedWidth = try #require(PenLayoutEngine.layout(document)["Txt01"]).width
        #expect(abs(facedWidth - fallbackWidth) > 0.5)

        // And the read path — offline, no fetcher, a cache it has never seen — agrees
        // that the family is placed.
        let reader = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: tempDir.appendingPathComponent("empty")),
            fetcher: MockFontFetcher()
        )
        #expect(reader.prepareCachedFonts(for: document).isEmpty)
    }

    /// Proves `registerFont(data:)` stages through ``ScratchDirectory`` rather than
    /// `FileManager.default.temporaryDirectory` directly — the seam that fails inside
    /// the Claude Code sandbox, which allows `$TMPDIR` but not the per-user
    /// `/var/folders/…/T` the bare API resolves to (project/2026-09-26-sandbox-font-downloads.md).
    /// Bogus bytes are enough: this is about where the file lands, not whether CoreText
    /// accepts it, so it never touches the one-family-per-run constraint the tests above
    /// carry.
    @Test("Font registration from data stages the file at a set $TMPDIR")
    func registerFromDataHonoursTMPDIR() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("scratch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let resolver = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: scratch),
            fetcher: MockFontFetcher()
        )
        resolver.registerFont(data: Self.fakeTTFData, environment: [ScratchDirectory.environmentVariable: scratch.path])

        let staged = try FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("woodcase-font-") }
        #expect(staged.count == 1)
    }
}
