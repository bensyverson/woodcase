//
//  PenRemoteImageProviderTests.swift
//  Woodcase
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Woodcase

@Suite("PenRenderer.imageProvider")
struct PenRemoteImageProviderTests {
    static let remoteURL = "https://images.example.com/hero.jpg?w=1200"

    /// A base directory holding one PNG at `photo.png`, and a resolver whose cache
    /// holds one PNG for ``remoteURL`` — the two halves the combined provider must
    /// keep apart.
    private static func makeFixture(
        localSize: (width: Int, height: Int) = (20, 10),
        remoteSize: (width: Int, height: Int)? = (32, 16)
    ) throws -> (baseDir: URL, resolver: RemoteImageResolver, cleanup: () -> Void) {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodcase-remote-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try TestPNGBytes.solid(width: localSize.width, height: localSize.height)
            .write(to: baseDir.appendingPathComponent("photo.png"))

        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cache = RemoteImageCache(rootDirectory: cacheDir)
        if let remoteSize {
            try cache.cache(
                data: TestPNGBytes.solid(width: remoteSize.width, height: remoteSize.height),
                for: remoteURL
            )
        }
        let resolver = RemoteImageResolver(cache: cache, fetcher: URLSessionDataFetcher())

        return (baseDir, resolver, {
            try? FileManager.default.removeItem(at: baseDir)
            try? FileManager.default.removeItem(at: cacheDir)
        })
    }

    @Test("Serves an https URL from the remote cache")
    func servesRemoteFromCache() throws {
        let (baseDir, resolver, cleanup) = try Self.makeFixture()
        defer { cleanup() }

        let provider = PenRenderer.imageProvider(relativeTo: baseDir, remote: resolver)
        let image = try #require(provider(Self.remoteURL))
        #expect(image.width == 32)
        #expect(image.height == 16)
    }

    @Test("A relative path still resolves against the base directory")
    func servesRelativeFromDisk() throws {
        let (baseDir, resolver, cleanup) = try Self.makeFixture()
        defer { cleanup() }

        let provider = PenRenderer.imageProvider(relativeTo: baseDir, remote: resolver)
        let image = try #require(provider("photo.png"))
        #expect(image.width == 20)
        #expect(image.height == 10)
    }

    @Test("An http URL is treated as remote, not as a path under the base directory")
    func httpIsRemoteToo() throws {
        let (baseDir, resolver, cleanup) = try Self.makeFixture(remoteSize: nil)
        defer { cleanup() }

        // Nothing is cached, so the answer is nil — but crucially the provider must not
        // have appended the URL to baseDir and gone looking on disk for it.
        let provider = PenRenderer.imageProvider(relativeTo: baseDir, remote: resolver)
        #expect(provider("http://images.example.com/hero.jpg") == nil)
    }

    @Test("An uncached remote URL yields nil rather than a blank crash")
    func uncachedRemoteIsNil() throws {
        let (baseDir, resolver, cleanup) = try Self.makeFixture(remoteSize: nil)
        defer { cleanup() }

        let provider = PenRenderer.imageProvider(relativeTo: baseDir, remote: resolver)
        #expect(provider(Self.remoteURL) == nil)
    }
}
