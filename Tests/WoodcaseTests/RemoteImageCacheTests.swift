//
//  RemoteImageCacheTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

@Suite("RemoteImageCache")
struct RemoteImageCacheTests {
    // MARK: - filename

    @Test("The same URL always produces the same filename")
    func filenameIsDeterministic() {
        let url = "https://images.unsplash.com/photo-1234?w=800"
        #expect(RemoteImageCache.filename(for: url) == RemoteImageCache.filename(for: url))
    }

    @Test("Different URLs produce different filenames")
    func filenameDiscriminates() {
        let first = RemoteImageCache.filename(for: "https://example.com/a.png")
        let second = RemoteImageCache.filename(for: "https://example.com/b.png")
        #expect(first != second)
    }

    @Test("A query string is part of the identity, not noise")
    func filenameIncludesQuery() {
        let plain = RemoteImageCache.filename(for: "https://example.com/a.png")
        let sized = RemoteImageCache.filename(for: "https://example.com/a.png?w=400")
        #expect(plain != sized)
    }

    @Test("The filename is sixteen lowercase hex characters and the .img extension")
    func filenameShape() {
        let name = RemoteImageCache.filename(for: "https://example.com/photo.jpg")
        #expect(name.hasSuffix(".img"))
        let stem = String(name.dropLast(4))
        #expect(stem.count == 16)
        #expect(stem.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    // MARK: - Cache read/write

    @Test("Cache miss returns nil")
    func cacheMissReturnsNil() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cache = RemoteImageCache(rootDirectory: tempDir)
        #expect(cache.cachedImageData(for: "https://example.com/nothing.png") == nil)
    }

    @Test("Round-trips image data through the cache")
    func roundTripsData() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = RemoteImageCache(rootDirectory: tempDir)

        let bytes = Data("pretend-png-bytes".utf8)
        try cache.cache(data: bytes, for: "https://example.com/photo.png")

        #expect(cache.cachedImageData(for: "https://example.com/photo.png") == bytes)
    }

    @Test("Caching one URL does not answer for another")
    func cacheIsKeyedByURL() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cache = RemoteImageCache(rootDirectory: tempDir)

        try cache.cache(data: Data("a".utf8), for: "https://example.com/a.png")
        #expect(cache.cachedImageData(for: "https://example.com/b.png") == nil)
    }

    @Test("The file URL is a flat entry directly under the root directory")
    func fileURLIsUnderRoot() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cache = RemoteImageCache(rootDirectory: tempDir)

        let fileURL = cache.imageFileURL(for: "https://example.com/photo.png")
        #expect(fileURL.deletingLastPathComponent().standardizedFileURL.path == tempDir.standardizedFileURL.path)
        #expect(fileURL.lastPathComponent == RemoteImageCache.filename(for: "https://example.com/photo.png"))
    }

    // MARK: - Default cache directory

    @Test("Default cache directory is the images directory in $WOODCASE_HOME")
    func defaultCacheDirectoryFollowsTheHomeOverride() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteImageCache-\(UUID().uuidString)", isDirectory: true)
        let environment = [WoodcaseHome.environmentVariable: home.path]

        let directory = RemoteImageCache.defaultCacheDirectory(in: environment)

        #expect(directory.path == home.appendingPathComponent("images").path)
        #expect(RemoteImageCache(environment: environment).rootDirectory.path == directory.path)
    }

    @Test("With no override the default cache directory is ~/.woodcase/images")
    func defaultCacheDirectoryWithNoOverride() {
        let directory = RemoteImageCache.defaultCacheDirectory(in: [:])

        #expect(directory.path.hasSuffix("/.woodcase/images"))
        #expect(directory.path.hasPrefix(NSHomeDirectory()))
    }
}
