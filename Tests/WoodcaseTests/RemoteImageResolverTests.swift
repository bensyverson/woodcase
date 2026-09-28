//
//  RemoteImageResolverTests.swift
//  Woodcase
//

import Foundation
import os
import Testing
@testable import Woodcase

/// A fetcher that answers from a canned table and records what it was asked for.
///
/// The recording is the point: several tests below prove that a *cache* answered, which
/// can only be shown by the network never being reached.
final class MockImageFetcher: RemoteDataFetching {
    private let requestLog = OSAllocatedUnfairLock<[String]>(initialState: [])
    let responses: [String: Data]

    init(responses: [String: Data] = [:]) {
        self.responses = responses
    }

    /// Every URL string this fetcher has been asked for, in order.
    var requested: [String] {
        requestLog.withLock { $0 }
    }

    func fetch(url: URL) async throws -> Data {
        requestLog.withLock { $0.append(url.absoluteString) }
        guard let data = responses[url.absoluteString] else {
            throw RemoteFetchError.httpError(statusCode: 404)
        }
        return data
    }
}

@Suite("RemoteImageResolver")
struct RemoteImageResolverTests {
    static let remoteURL = "https://images.example.com/photo-1.jpg?w=800"
    static let otherRemoteURL = "https://images.example.com/photo-2.jpg"

    static func imageFill(_ url: String?) -> PenFills {
        .single(.image(PenFill.PenImageFill(url: url)))
    }

    static func rectangle(id: String, fill: PenFills?) -> PenNode {
        PenNode(
            id: id,
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: fill))
        )
    }

    static func makeResolver(
        responses: [String: Data] = [:]
    ) -> (RemoteImageResolver, MockImageFetcher, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let fetcher = MockImageFetcher(responses: responses)
        let resolver = RemoteImageResolver(
            cache: RemoteImageCache(rootDirectory: tempDir), fetcher: fetcher
        )
        return (resolver, fetcher, tempDir)
    }

    // MARK: - Collection

    @Test("Collects a remote image URL from a rectangle fill")
    func collectsFromRectangle() {
        let doc = PenDocument(children: [Self.rectangle(id: "1", fill: Self.imageFill(Self.remoteURL))])
        #expect(RemoteImageResolver.collectRemoteImageURLs(from: doc) == [Self.remoteURL])
    }

    @Test("Collects through nested frames and groups, not only top-level nodes")
    func collectsThroughNesting() {
        let leaf = Self.rectangle(id: "leaf", fill: Self.imageFill(Self.remoteURL))
        let group = PenNode(
            id: "group", common: PenNodeCommon(),
            kind: .group(PenNode.GroupData(children: [leaf]))
        )
        let frame = PenNode(
            id: "frame", common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(children: [group]))
        )
        let doc = PenDocument(children: [frame])
        #expect(RemoteImageResolver.collectRemoteImageURLs(from: doc) == [Self.remoteURL])
    }

    @Test("Collects image fills from every kind that carries them")
    func collectsFromEveryFilledKind() {
        let doc = PenDocument(children: [
            PenNode(id: "r", common: PenNodeCommon(),
                    kind: .rectangle(PenNode.RectangleData(fills: Self.imageFill("https://e.com/r.png")))),
            PenNode(id: "e", common: PenNodeCommon(),
                    kind: .ellipse(PenNode.EllipseData(fills: Self.imageFill("https://e.com/e.png")))),
            PenNode(id: "p", common: PenNodeCommon(),
                    kind: .polygon(PenNode.PolygonData(fills: Self.imageFill("https://e.com/p.png")))),
            PenNode(id: "a", common: PenNodeCommon(),
                    kind: .path(PenNode.PathData(fills: Self.imageFill("https://e.com/a.png")))),
            PenNode(id: "f", common: PenNodeCommon(),
                    kind: .frame(PenNode.FrameData(fills: Self.imageFill("https://e.com/f.png")))),
            PenNode(id: "i", common: PenNodeCommon(),
                    kind: .icon(PenNode.IconData(fills: Self.imageFill("https://e.com/i.png")))),
            PenNode(id: "t", common: PenNodeCommon(),
                    kind: .text(PenNode.TextData(fills: Self.imageFill("https://e.com/t.png")))),
        ])
        #expect(RemoteImageResolver.collectRemoteImageURLs(from: doc).count == 7)
    }

    @Test("Ignores relative paths, which the file provider still handles")
    func ignoresRelativePaths() {
        let doc = PenDocument(children: [
            Self.rectangle(id: "1", fill: Self.imageFill("./images/hero.png")),
            Self.rectangle(id: "2", fill: Self.imageFill("images/nested/texture.png")),
        ])
        #expect(RemoteImageResolver.collectRemoteImageURLs(from: doc).isEmpty)
    }

    @Test("Ignores an image fill with no URL assigned yet")
    func ignoresMissingURL() {
        let doc = PenDocument(children: [Self.rectangle(id: "1", fill: Self.imageFill(nil))])
        #expect(RemoteImageResolver.collectRemoteImageURLs(from: doc).isEmpty)
    }

    @Test("Ignores non-image fills")
    func ignoresNonImageFills() {
        let doc = PenDocument(children: [
            Self.rectangle(id: "1", fill: .single(.shorthand("#FF0000"))),
        ])
        #expect(RemoteImageResolver.collectRemoteImageURLs(from: doc).isEmpty)
    }

    @Test("Deduplicates a URL used by several nodes")
    func deduplicates() {
        let doc = PenDocument(children: [
            Self.rectangle(id: "1", fill: Self.imageFill(Self.remoteURL)),
            Self.rectangle(id: "2", fill: Self.imageFill(Self.remoteURL)),
        ])
        #expect(RemoteImageResolver.collectRemoteImageURLs(from: doc).count == 1)
    }

    // MARK: - Downloading and caching

    @Test("Downloads a remote image and caches it to disk")
    func downloadsAndCaches() async {
        let bytes = TestPNGBytes.solid(width: 4, height: 2)
        let (resolver, _, tempDir) = Self.makeResolver(responses: [Self.remoteURL: bytes])
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let data = await resolver.resolve(urlString: Self.remoteURL)
        #expect(data == bytes)

        let cache = RemoteImageCache(rootDirectory: tempDir)
        #expect(cache.cachedImageData(for: Self.remoteURL) == bytes)
    }

    @Test("A second resolver sharing the disk cache never reaches the network")
    func secondResolverUsesDiskCache() async throws {
        let bytes = TestPNGBytes.solid(width: 4, height: 2)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = RemoteImageCache(rootDirectory: tempDir)
        try cache.cache(data: bytes, for: Self.remoteURL)

        // A fetcher with no responses throws for anything it is asked.
        let fetcher = MockImageFetcher()
        let resolver = RemoteImageResolver(cache: cache, fetcher: fetcher)

        #expect(await resolver.resolve(urlString: Self.remoteURL) == bytes)
        #expect(fetcher.requested.isEmpty)
    }

    @Test("A failed download is not retried for the life of the resolver")
    func failedDownloadIsNotRetried() async {
        let (resolver, fetcher, tempDir) = Self.makeResolver()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(await resolver.resolve(urlString: Self.remoteURL) == nil)
        #expect(await resolver.resolve(urlString: Self.remoteURL) == nil)
        #expect(fetcher.requested.count == 1)
    }

    @Test("prepareImages downloads every remote fill in the document, once each")
    func prepareImagesDownloadsAll() async {
        let first = TestPNGBytes.solid(width: 2, height: 2)
        let second = TestPNGBytes.solid(width: 3, height: 3)
        let (resolver, fetcher, tempDir) = Self.makeResolver(responses: [
            Self.remoteURL: first,
            Self.otherRemoteURL: second,
        ])
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let doc = PenDocument(children: [
            Self.rectangle(id: "1", fill: Self.imageFill(Self.remoteURL)),
            Self.rectangle(id: "2", fill: Self.imageFill(Self.remoteURL)),
            Self.rectangle(id: "3", fill: Self.imageFill(Self.otherRemoteURL)),
            Self.rectangle(id: "4", fill: Self.imageFill("./local.png")),
        ])
        await resolver.prepareImages(for: doc)

        #expect(Set(fetcher.requested) == [Self.remoteURL, Self.otherRemoteURL])
        #expect(fetcher.requested.count == 2)
        #expect(resolver.cachedImage(for: Self.remoteURL)?.width == 2)
        #expect(resolver.cachedImage(for: Self.otherRemoteURL)?.width == 3)
    }

    @Test("prepareImages warns through the collector when an image cannot be fetched")
    func prepareImagesWarns() async {
        let (resolver, _, tempDir) = Self.makeResolver()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let doc = PenDocument(children: [Self.rectangle(id: "1", fill: Self.imageFill(Self.remoteURL))])
        let diagnostics = PenDiagnosticCollector()
        await resolver.prepareImages(for: doc, diagnostics: diagnostics)

        let warnings = diagnostics.diagnostics
        #expect(warnings.count == 1)
        #expect(warnings.first?.stage == .imageResolution)
        #expect(warnings.first?.severity == .warning)
        #expect(warnings.first?.message.contains(Self.remoteURL) == true)
    }

    // MARK: - cachedImage

    @Test("cachedImage decodes a cached PNG into a CGImage of the right size")
    func cachedImageDecodes() async {
        let bytes = TestPNGBytes.solid(width: 12, height: 7)
        let (resolver, _, tempDir) = Self.makeResolver(responses: [Self.remoteURL: bytes])
        defer { try? FileManager.default.removeItem(at: tempDir) }

        _ = await resolver.resolve(urlString: Self.remoteURL)

        let image = resolver.cachedImage(for: Self.remoteURL)
        #expect(image?.width == 12)
        #expect(image?.height == 7)
    }

    @Test("cachedImage returns nil for a URL nothing has fetched")
    func cachedImageMissReturnsNil() {
        let (resolver, _, tempDir) = Self.makeResolver()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        #expect(resolver.cachedImage(for: Self.remoteURL) == nil)
    }

    @Test("cachedImage returns nil for cached bytes that are not an image")
    func cachedImageRejectsNonImage() async {
        let (resolver, _, tempDir) = Self.makeResolver(responses: [
            Self.remoteURL: Data("<html>404</html>".utf8),
        ])
        defer { try? FileManager.default.removeItem(at: tempDir) }

        _ = await resolver.resolve(urlString: Self.remoteURL)
        #expect(resolver.cachedImage(for: Self.remoteURL) == nil)
    }

    // MARK: - Best-effort caching

    /// A root directory that is a plain file, so ``RemoteImageCache/cache(data:for:)``
    /// cannot create it — the same failure a read-only cache volume or a sandboxed
    /// process produces, without needing either.
    private static func makeUnwritableCacheRoot() throws -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: path)
        return path
    }

    @Test("An unwritable cache still resolves and still decodes the image")
    func unwritableCacheStillResolves() async throws {
        let blockedRoot = try Self.makeUnwritableCacheRoot()
        defer { try? FileManager.default.removeItem(at: blockedRoot) }

        let bytes = TestPNGBytes.solid(width: 9, height: 4)
        let resolver = RemoteImageResolver(
            cache: RemoteImageCache(rootDirectory: blockedRoot),
            fetcher: MockImageFetcher(responses: [Self.remoteURL: bytes])
        )

        #expect(await resolver.resolve(urlString: Self.remoteURL) == bytes)
        #expect(resolver.cachedImage(for: Self.remoteURL)?.width == 9)
    }

    @Test("An unwritable cache prints its notice once, not once per image")
    func unwritableCacheLogsOnce() async throws {
        let blockedRoot = try Self.makeUnwritableCacheRoot()
        defer { try? FileManager.default.removeItem(at: blockedRoot) }

        let resolver = RemoteImageResolver(
            cache: RemoteImageCache(rootDirectory: blockedRoot),
            fetcher: MockImageFetcher(responses: [
                Self.remoteURL: TestPNGBytes.solid(width: 2, height: 2),
                Self.otherRemoteURL: TestPNGBytes.solid(width: 2, height: 2),
            ])
        )

        #expect(resolver.cacheFallbackNoticeCount == 0)
        _ = await resolver.resolve(urlString: Self.remoteURL)
        #expect(resolver.cacheFallbackNoticeCount == 1)
        _ = await resolver.resolve(urlString: Self.otherRemoteURL)
        #expect(resolver.cacheFallbackNoticeCount == 1)
    }

    @Test("An image that fell back to memory is not re-downloaded by a second resolver")
    func memoryFallbackIsSharedAcrossResolvers() async throws {
        let blockedRoot = try Self.makeUnwritableCacheRoot()
        defer { try? FileManager.default.removeItem(at: blockedRoot) }

        let bytes = TestPNGBytes.solid(width: 5, height: 5)
        let cache = RemoteImageCache(rootDirectory: blockedRoot)
        let first = RemoteImageResolver(
            cache: cache, fetcher: MockImageFetcher(responses: [Self.remoteURL: bytes])
        )
        #expect(await first.resolve(urlString: Self.remoteURL) == bytes)

        let secondFetcher = MockImageFetcher()
        let second = RemoteImageResolver(cache: cache, fetcher: secondFetcher)
        #expect(await second.resolve(urlString: Self.remoteURL) == bytes)
        #expect(secondFetcher.requested.isEmpty)
    }
}
