//
//  PenBundleEmbedTests.swift
//  WoodcaseTests
//

import Foundation
import os
import Testing
@testable import Woodcase

/// `woodcase embed`: a bundle's remote images and Google Fonts are downloaded into it,
/// through an injected fetcher, so it renders without the network.
struct PenBundleEmbedTests {
    /// A fetcher that answers from a table and remembers every request.
    final class TableFetcher: RemoteDataFetching, Sendable {
        let answers: [String: Data]
        private let asked = OSAllocatedUnfairLock<[String]>(initialState: [])

        init(_ answers: [String: Data] = [:]) {
            self.answers = answers
        }

        var requests: [String] {
            asked.withLock { $0 }
        }

        func fetch(url: URL) async throws -> Data {
            asked.withLock { $0.append(url.absoluteString) }
            guard let data = answers[url.absoluteString] else { throw RemoteFetchError.httpError(statusCode: 404) }
            return data
        }
    }

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    private static let photo = "https://images.example.com/photo-1522?w=1600"
    private static let fontURL = "https://fonts.example.com/Fetched.ttf"

    private static let document = """
    {"version": "\(PenDocument.currentFormatVersion)", "children": [
      {"type": "frame", "id": "card", "width": 100, "height": 100,
       "fill": {"type": "image", "url": "\(photo)", "mode": "cover"},
       "children": [
         {"type": "text", "id": "label", "content": "Hi", "fontFamily": "IBM Plex Mono", "fontWeight": "700"},
         {"type": "rectangle", "id": "dead", "width": 10, "height": 10,
          "fill": {"type": "image", "url": "https://images.example.com/dead.png", "mode": "cover"}}
       ]},
      {"type": "text", "id": "fetched", "content": "Yo", "fontFamily": "Woodcase Fetched Mono"}
    ],
    "fonts": [{"name": "Woodcase Fetched Mono", "url": "\(fontURL)"}]}
    """

    private struct Scratch {
        let root: URL
        let bundle: URL
        let cache: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("PenBundleEmbedTests-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            bundle = root.appendingPathComponent("Design.umbra")
            cache = root.appendingPathComponent("font-cache")
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data(PenBundleEmbedTests.document.utf8).write(to: bundle.appendingPathComponent("document.pen"))
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func onlineFetcher() throws -> TableFetcher {
        try TableFetcher([
            Self.photo: Data(contentsOf: Self.fixtures.appendingPathComponent("Fixtures/blur1.png")),
            Self.fontURL: Data(contentsOf: Self.fixtures.appendingPathComponent("Fonts/WoodcaseFetchedMono.ttf")),
        ])
    }

    @Test("embed downloads remote images and declared fonts into the bundle and points at them")
    func embedsRemoteFiles() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let fonts = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: scratch.cache), fetcher: LocalGoogleFontsFetcher.committed
        )

        let report = try await PenBundle.embed(scratch.bundle, identity: "ana", fetcher: onlineFetcher(), fonts: fonts)

        let document = try PenParser.parse(contentsOf: scratch.bundle)
        let references = try PenAssetReferences.collect(from: document).map(\.value)
        let photo = try Data(contentsOf: Self.fixtures.appendingPathComponent("Fixtures/blur1.png"))
        #expect(references.contains("./images/" + PenBundle.imageFileName(for: photo, fileExtension: nil)))
        #expect(references.contains("./fonts/Fetched.ttf"))
        #expect(references.contains("https://images.example.com/dead.png"))
        #expect(report.missing == ["https://images.example.com/dead.png"])
        for reference in references where reference.hasPrefix("./") {
            #expect(FileManager.default.fileExists(atPath: scratch.bundle.appendingPathComponent(reference).path))
        }
    }

    @Test("embed copies the Google Fonts file each face draws in, and declares it")
    func embedsGoogleFonts() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let fonts = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: scratch.cache), fetcher: LocalGoogleFontsFetcher.committed
        )

        try await PenBundle.embed(scratch.bundle, identity: "ana", fetcher: onlineFetcher(), fonts: fonts)

        let document = try PenParser.parse(contentsOf: scratch.bundle)
        let declaration = try #require(document.fonts?.first { $0.name == "IBM Plex Mono" })
        #expect(declaration.url == "./fonts/IBMPlexMono-Bold.ttf")
        #expect(declaration.weight == .single(700))
        #expect(declaration.style == .normal)
        #expect(FileManager.default.fileExists(atPath: scratch.bundle.appendingPathComponent("fonts/IBMPlexMono-Bold.ttf").path))
    }

    @Test("embed is one logged, undoable change")
    func embedIsLogged() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let fonts = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: scratch.cache), fetcher: LocalGoogleFontsFetcher.committed
        )

        try await PenBundle.embed(scratch.bundle, identity: "ana", fetcher: onlineFetcher(), fonts: fonts)

        let rows = try ActivityReader(log: ActivityLogLocation.log(for: scratch.bundle, environment: [:])).read().events
        #expect(Set(rows.map(\.op)) == [.replace, .set])
        #expect(Set(rows.compactMap(\.batch)).count == 1)
        #expect(rows.allSatisfy { !$0.inverse.isEmpty })
    }

    @Test("an embedded bundle resolves its fonts and images without asking the network")
    func embeddedBundleRendersOffline() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let fonts = GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: scratch.cache), fetcher: LocalGoogleFontsFetcher.committed
        )
        try await PenBundle.embed(scratch.bundle, identity: nil, fetcher: onlineFetcher(), fonts: fonts)
        let document = try PenParser.parse(contentsOf: scratch.bundle)
        let offline = TableFetcher()
        let images = RemoteImageResolver(
            cache: RemoteImageCache(rootDirectory: scratch.root.appendingPathComponent("empty-images")), fetcher: offline
        )
        let local = try #require(PenAssetReferences.collect(from: document).first { $0.value.hasPrefix("./images/") })

        await images.prepareImages(for: document, diagnostics: PenDiagnosticCollector())

        // Only the image whose download failed is still remote.
        #expect(offline.requests == ["https://images.example.com/dead.png"])
        #expect(PenRenderer.imageProvider(relativeTo: scratch.bundle, remote: images)(local.value) != nil)
        // Every family the text draws is declared by a file inside the bundle, so the
        // font chain registers it from disk before Google Fonts is ever asked. Nothing
        // is registered here: only one test per run may watch a family appear.
        let source = PenLocation(scratch.bundle).document
        let families = GoogleFontResolver.collectFontFamilies(from: document)
        for family in families {
            let declarations = (document.fonts ?? []).filter { $0.name == family }
            #expect(!declarations.isEmpty, "\(family)")
            for declaration in declarations {
                guard case let .local(url) = GoogleFontResolver.location(of: declaration, relativeTo: source) else {
                    Issue.record("\(family) is declared at \(declaration.url), which is not a local file")
                    continue
                }
                #expect(url.path.hasPrefix(scratch.bundle.path))
                #expect(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }

    @Test("embed stores two remote images with the same bytes as one file, both fills pointing at it")
    func embedDedupesImages() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let twin = "https://cdn.example.com/same-photo.png"
        try Data("""
        {"version": "\(PenDocument.currentFormatVersion)", "children": [
          {"type": "rectangle", "id": "a", "width": 10, "height": 10,
           "fill": {"type": "image", "url": "\(Self.photo)", "mode": "cover"}},
          {"type": "rectangle", "id": "b", "width": 10, "height": 10,
           "fill": {"type": "image", "url": "\(twin)", "mode": "cover"}}
        ]}
        """.utf8).write(to: scratch.bundle.appendingPathComponent("document.pen"))
        let photo = try Data(contentsOf: Self.fixtures.appendingPathComponent("Fixtures/blur1.png"))
        let fonts = GoogleFontResolver(cache: GoogleFontCache(rootDirectory: scratch.cache), fetcher: TableFetcher())

        try await PenBundle.embed(
            scratch.bundle, identity: nil, fetcher: TableFetcher([Self.photo: photo, twin: photo]), fonts: fonts
        )

        let stored = "./images/" + PenBundle.imageFileName(for: photo, fileExtension: nil)
        let saved = try String(decoding: Data(contentsOf: scratch.bundle.appendingPathComponent("document.pen")), as: UTF8.self)
        #expect(saved.components(separatedBy: "\"\(stored)\"").count - 1 == 2)
        #expect(!saved.contains("example.com"))
        let images = scratch.bundle.appendingPathComponent("images")
        #expect(try FileManager.default.contentsOfDirectory(atPath: images.path) == [String(stored.dropFirst(9))])
    }

    @Test("embed refuses a bare .pen")
    func embedRefusesABareFile() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let bare = scratch.root.appendingPathComponent("Bare.pen")
        try FileManager.default.copyItem(at: scratch.bundle.appendingPathComponent("document.pen"), to: bare)
        let fonts = GoogleFontResolver(cache: GoogleFontCache(rootDirectory: scratch.cache), fetcher: TableFetcher())

        await #expect(throws: PenBundleError.self) {
            try await PenBundle.embed(bare, identity: nil, fetcher: TableFetcher(), fonts: fonts)
        }
    }
}
