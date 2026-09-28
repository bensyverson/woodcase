//
//  DeclaredFontsTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import os
import Testing
@testable import Woodcase

/// A document's own `fonts` register before Google Fonts is consulted: a local file,
/// resolved against the .pen file's directory, on every settled read; a remote one
/// fetched into the font cache on the render path, and read back from that cache
/// offline.
///
/// Core Text registration is process-global and irreversible, so each family that goes
/// from absent to present here is owned by exactly one test and used by no other suite
/// (`project/gotchas.md`, 2026-09-02): "Woodcase Declared Mono" and "Woodcase Fetched
/// Mono", renamed copies of JetBrains Mono made by `scripts/rename-font-family`.
@Suite("Declared fonts")
struct DeclaredFontsTests {
    // MARK: - Helpers

    private static let fontsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fonts")

    /// A fetcher that answers one URL with a font's bytes, records every URL it is
    /// asked for, and refuses everything else.
    final class RecordingFetcher: RemoteDataFetching {
        let answers: [String: Data]
        private let asked = OSAllocatedUnfairLock<[String]>(initialState: [])

        init(answers: [String: Data] = [:]) {
            self.answers = answers
        }

        var requests: [String] {
            asked.withLock { $0 }
        }

        func fetch(url: URL) async throws -> Data {
            asked.withLock { $0.append(url.absoluteString) }
            guard let data = answers[url.absoluteString] else {
                throw RemoteFetchError.httpError(statusCode: 404)
            }
            return data
        }
    }

    /// A fresh directory for one test.
    private static func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeclaredFontsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A one-text document in `family`, declaring `fonts` when given.
    private static func document(family: String, fonts: String? = nil) -> String {
        let declared = fonts.map { #","fonts":\#($0)"# } ?? ""
        return #"""
        {"version":"2.19"\#(declared),"children":[
          {"id":"Board","type":"frame","layout":"none","x":0,"y":0,"width":400,"height":60,"fill":"#FFFFFF","children":[
            {"id":"Label","type":"text","x":0,"y":0,"content":"iiiiiiiiii","fontFamily":"\#(family)","fontSize":20,"fill":"#000000"}]}]}
        """#
    }

    /// The width a settled read measures the label at, reading `url` as the CLI does.
    private static func settledWidth(of url: URL, fonts: GoogleFontResolver? = nil) async throws -> Double {
        try await PenFileTransaction.read(at: url, fonts: fonts) { document in
            SettledTree(document: document, theme: [:]).rects["Label"]?.width ?? -1
        }.value
    }

    /// How many columns of the board's render hold dark ink.
    private static func inkColumns(of url: URL) throws -> Int {
        let document = try PenParser.parse(contentsOf: url)
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(document, layoutRects: rects, size: CGSize(width: 400, height: 60)))
        var buffer = [UInt8](repeating: 0, count: 400 * 60 * 4)
        let context = try #require(CGContext(
            data: &buffer, width: 400, height: 60, bitsPerComponent: 8, bytesPerRow: 1600,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 400, height: 60))
        return (0 ..< 400).count(where: { x in
            (0 ..< 60).contains { y in buffer[(y * 400 + x) * 4] < 128 }
        })
    }

    // MARK: - A local file, on the settled read

    @Test("A declared local font is what tree measures and the renderer draws, ahead of the fallback")
    func localDeclaredFontIsMeasuredAndDrawn() async throws {
        let family = "Woodcase Declared Mono"
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("fonts"), withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: Self.fontsDirectory.appendingPathComponent("WoodcaseDeclaredMono.ttf"),
            to: directory.appendingPathComponent("fonts/declared.ttf")
        )
        #expect(!PenTextMeasurer.fontFamilyAvailable(family), "\(family) is already registered in this process")

        let undeclared = directory.appendingPathComponent("undeclared.pen")
        try Data(Self.document(family: family).utf8).write(to: undeclared)
        let fallbackWidth = try await Self.settledWidth(of: undeclared)
        let fallbackInk = try Self.inkColumns(of: undeclared)
        #expect(!PenTextMeasurer.fontFamilyAvailable(family))

        let declared = directory.appendingPathComponent("declared.pen")
        let fonts = #"[{"name":"\#(family)","url":"fonts/declared.ttf"}]"#
        try Data(Self.document(family: family, fonts: fonts).utf8).write(to: declared)
        let declaredWidth = try await Self.settledWidth(of: declared)

        #expect(PenTextMeasurer.fontFamilyAvailable(family))
        // Ten i's in a monospace face are far wider than in the proportional fallback.
        #expect(declaredWidth > fallbackWidth * 1.5, "declared \(declaredWidth), fallback \(fallbackWidth)")
        #expect(try Self.inkColumns(of: declared) > fallbackInk * 3 / 2, "the render still draws the fallback")
    }

    // MARK: - A remote file, on the render path

    @Test("A declared remote font is fetched into the cache before Google Fonts is asked for anything")
    func remoteDeclaredFontIsFetchedAheadOfGoogle() async throws {
        let family = "Woodcase Fetched Mono"
        let address = "https://fonts.example.com/fetched.ttf"
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try Data(contentsOf: Self.fontsDirectory.appendingPathComponent("WoodcaseFetchedMono.ttf"))
        let fetcher = RecordingFetcher(answers: [address: bytes])
        let resolver = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: directory.appendingPathComponent("cache")), fetcher: fetcher
        )
        let url = directory.appendingPathComponent("remote.pen")
        let fonts = #"[{"name":"\#(family)","url":"\#(address)"}]"#
        try Data(Self.document(family: family, fonts: fonts).utf8).write(to: url)
        let document = try PenParser.parse(contentsOf: url)
        #expect(!PenTextMeasurer.fontFamilyAvailable(family), "\(family) is already registered in this process")
        let before = try #require(PenLayoutEngine.layout(document)["Label"]?.width)

        await resolver.prepareFonts(for: document, relativeTo: url)

        #expect(fetcher.requests == [address], "only the declared file is fetched, never Google's metadata")
        #expect(PenTextMeasurer.fontFamilyAvailable(family))
        let after = try #require(PenLayoutEngine.layout(document)["Label"]?.width)
        #expect(after > before * 1.5, "after \(after), before \(before)")
        let declaration = try #require(document.fonts?.first)
        let cached = try #require(resolver.cachedDeclaredFontURL(for: declaration))
        #expect(try Data(contentsOf: cached) == bytes)
    }

    // MARK: - Offline, and failures

    @Test("A settled read never fetches a declared remote font")
    func settledReadStaysOffline() async throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = RecordingFetcher()
        let resolver = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: directory.appendingPathComponent("cache")), fetcher: fetcher
        )
        let url = directory.appendingPathComponent("remote.pen")
        let fonts = #"[{"name":"Woodcase Never Fetched","url":"https://fonts.example.com/never.ttf"}]"#
        try Data(Self.document(family: "Woodcase Never Fetched", fonts: fonts).utf8).write(to: url)

        _ = try await Self.settledWidth(of: url, fonts: resolver)

        #expect(fetcher.requests.isEmpty)
    }

    @Test("A declared file that is not there is reported by name and path, not as a missing Google font")
    func missingLocalFileIsReported() throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: directory.appendingPathComponent("cache")), fetcher: RecordingFetcher()
        )
        let url = directory.appendingPathComponent("missing.pen")
        let fonts = #"[{"name":"Woodcase Missing Face","url":"fonts/missing.ttf"}]"#
        try Data(Self.document(family: "Woodcase Missing Face", fonts: fonts).utf8).write(to: url)
        let document = try PenParser.parse(contentsOf: url)
        let diagnostics = PenDiagnosticCollector()

        resolver.registerDeclaredFonts(of: document, relativeTo: url, diagnostics: diagnostics)

        let warning = try #require(diagnostics.diagnostics.first)
        #expect(warning.message.contains("Woodcase Missing Face"))
        #expect(warning.message.contains(directory.appendingPathComponent("fonts/missing.ttf").path))
        #expect(warning.stage == .fontResolution)
    }

    @Test("A relative url with no file to resolve it against is reported, not guessed")
    func relativeURLWithoutASourceIsReported() {
        let resolver = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: FileManager.default.temporaryDirectory), fetcher: RecordingFetcher()
        )
        let document = PenDocument(fonts: [PenFontDeclaration(name: "Woodcase Nowhere", url: "fonts/n.ttf")], children: [])
        let diagnostics = PenDiagnosticCollector()

        resolver.registerDeclaredFonts(of: document, relativeTo: nil, diagnostics: diagnostics)

        #expect(diagnostics.diagnostics.first?.message.contains("Woodcase Nowhere") == true)
    }
}
