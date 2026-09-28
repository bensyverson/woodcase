//
//  GoogleFontCacheTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

@Suite("GoogleFontCache")
struct GoogleFontCacheTests {
    // MARK: - directoryName

    @Test("Maps simple family name to lowercase")
    func directoryNameSimple() {
        #expect(GoogleFontCache.directoryName(for: "Manrope") == "manrope")
    }

    @Test("Maps family name with spaces to lowercase without spaces")
    func directoryNameWithSpaces() {
        #expect(GoogleFontCache.directoryName(for: "IBM Plex Sans") == "ibmplexsans")
    }

    @Test("Maps family name with multiple spaces")
    func directoryNameMultipleSpaces() {
        #expect(GoogleFontCache.directoryName(for: "Fira Code") == "firacode")
    }

    @Test("Maps already lowercase name unchanged")
    func directoryNameAlreadyLowercase() {
        #expect(GoogleFontCache.directoryName(for: "roboto") == "roboto")
    }

    @Test("Maps name with numbers")
    func directoryNameWithNumbers() {
        #expect(GoogleFontCache.directoryName(for: "Source Sans 3") == "sourcesans3")
    }

    // MARK: - Cache read/write

    @Test("Cache miss returns nil")
    func cacheMissReturnsNil() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cache = GoogleFontCache(rootDirectory: tempDir)

        let result = cache.cachedFontData(family: "Nonexistent", filename: "Font.ttf")
        #expect(result == nil)
    }

    @Test("Round-trips font data through cache")
    func roundTripCacheData() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cache = GoogleFontCache(rootDirectory: tempDir)

        let fontData = Data("fake-font-data".utf8)
        try cache.cache(data: fontData, family: "Manrope", filename: "Manrope[wght].ttf")

        let retrieved = cache.cachedFontData(family: "Manrope", filename: "Manrope[wght].ttf")
        #expect(retrieved == fontData)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Caches to correct subdirectory based on family name")
    func cachesInCorrectSubdirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cache = GoogleFontCache(rootDirectory: tempDir)

        let fontData = Data("fake-font".utf8)
        try cache.cache(data: fontData, family: "IBM Plex Sans", filename: "IBMPlexSans[wdth,wght].ttf")

        let expectedPath = tempDir
            .appendingPathComponent("ibmplexsans")
            .appendingPathComponent("IBMPlexSans[wdth,wght].ttf")
        #expect(FileManager.default.fileExists(atPath: expectedPath.path))

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Default cache directory

    @Test("Default cache directory is the fonts directory in $WOODCASE_HOME")
    func defaultCacheDirectoryFollowsTheHomeOverride() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoogleFontCache-\(UUID().uuidString)", isDirectory: true)
        let environment = [WoodcaseHome.environmentVariable: home.path]

        let directory = GoogleFontCache.defaultCacheDirectory(in: environment)

        #expect(directory.path == home.appendingPathComponent("fonts").path)
        #expect(GoogleFontCache(environment: environment).rootDirectory.path == directory.path)
    }

    @Test("With no override the default cache directory is ~/.woodcase/fonts")
    func defaultCacheDirectoryWithNoOverride() {
        let directory = GoogleFontCache.defaultCacheDirectory(in: [:])

        #expect(directory.path.hasSuffix("/.woodcase/fonts"))
        #expect(directory.path.hasPrefix(NSHomeDirectory()))
    }
}
