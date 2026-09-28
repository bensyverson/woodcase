//
//  GoogleFontResolverFacesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Which files ``GoogleFontResolver/resolve(_:)`` fetches, caches and registers for the
/// faces a document draws: each static face's own file, a variable family's italic file
/// only when italic is drawn, nothing from the network that the cache already answers.
///
/// Every family here is made up and every font file is fake bytes, so Core Text never
/// places any of them: these tests pin which files move, and
/// `GoogleFontFacesSnapshotTests` pins what real files draw.
@Suite("GoogleFontResolver faces")
struct GoogleFontResolverFacesTests {
    /// A static family shipping 300 to 700, upright and italic.
    static let staticMetadata = "name: \"Facecheck Mono\"\n" + [
        ("normal", 300, "Light"), ("italic", 300, "LightItalic"), ("normal", 400, "Regular"),
        ("italic", 400, "Italic"), ("normal", 700, "Bold"), ("italic", 700, "BoldItalic"),
    ].map { style, weight, name in
        "fonts {\n  style: \"\(style)\"\n  weight: \(weight)\n  filename: \"FacecheckMono-\(name).ttf\"\n}\n"
    }.joined()

    /// A variable family with a separate italic file.
    static let variableMetadata = """
    name: "Facecheck Serif"
    fonts {
      style: "normal"
      weight: 400
      filename: "FacecheckSerif[wght].ttf"
    }
    fonts {
      style: "italic"
      weight: 400
      filename: "FacecheckSerif-Italic[wght].ttf"
    }
    """

    static let staticFiles = [
        "FacecheckMono-Light.ttf", "FacecheckMono-LightItalic.ttf", "FacecheckMono-Regular.ttf",
        "FacecheckMono-Italic.ttf", "FacecheckMono-Bold.ttf", "FacecheckMono-BoldItalic.ttf",
    ]

    /// A scratch directory holding a fake google/fonts tree for both families, and an
    /// empty cache root beside it.
    struct Stage {
        let remote: URL
        let cache: URL

        init() throws {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("GoogleFontResolverFacesTests-\(UUID().uuidString)", isDirectory: true)
            remote = root.appendingPathComponent("remote", isDirectory: true)
            cache = root.appendingPathComponent("cache", isDirectory: true)
            try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
            try Data(GoogleFontResolverFacesTests.staticMetadata.utf8)
                .write(to: remote.appendingPathComponent("facecheckmono.METADATA.pb"))
            try Data(GoogleFontResolverFacesTests.variableMetadata.utf8)
                .write(to: remote.appendingPathComponent("facecheckserif.METADATA.pb"))
            for file in GoogleFontResolverFacesTests.staticFiles + ["FacecheckSerif[wght].ttf", "FacecheckSerif-Italic[wght].ttf"] {
                try Data("fake \(file)".utf8).write(to: remote.appendingPathComponent(file))
            }
        }

        /// Copies `files` (METADATA.pb included, by that name) from the remote into the
        /// cache, as an earlier run would have left them.
        func warm(_ directory: String, _ files: [String]) throws {
            let target = cache.appendingPathComponent(directory, isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for file in files {
                let source = file == "METADATA.pb" ? "\(directory).METADATA.pb" : file
                try FileManager.default.copyItem(
                    at: remote.appendingPathComponent(source), to: target.appendingPathComponent(file)
                )
            }
        }

        /// The file names in a family's cache directory, sorted.
        func cached(_ directory: String) -> [String] {
            let names = try? FileManager.default.contentsOfDirectory(atPath: cache.appendingPathComponent(directory).path)
            return (names ?? []).sorted()
        }
    }

    static func mono(_ weight: Int, _ style: PenFontFace.Style = .normal) -> PenFontFace {
        PenFontFace(family: "Facecheck Mono", weight: weight, style: style)
    }

    static func serif(_ weight: Int, _ style: PenFontFace.Style = .normal) -> PenFontFace {
        PenFontFace(family: "Facecheck Serif", weight: weight, style: style)
    }

    @Test("On an empty cache, a static family fetches exactly the file of each face drawn, and caches its METADATA")
    func coldStaticFetchesEachFace() async throws {
        let stage = try Stage()
        let fetcher = LocalGoogleFontsFetcher(directory: stage.remote)
        let resolver = GoogleFontResolver(cache: GoogleFontCache(rootDirectory: stage.cache), fetcher: fetcher)

        let files = await resolver.resolve([Self.mono(400), Self.mono(700), Self.mono(400, .italic), Self.mono(700, .italic)])

        let expected = ["FacecheckMono-Bold.ttf", "FacecheckMono-BoldItalic.ttf", "FacecheckMono-Italic.ttf", "FacecheckMono-Regular.ttf"]
        #expect(fetcher.requestedFontFiles.map { $0.replacingOccurrences(of: "facecheckmono/", with: "") }.sorted() == expected)
        #expect(stage.cached("facecheckmono") == ["FacecheckMono-Bold.ttf", "FacecheckMono-BoldItalic.ttf", "FacecheckMono-Italic.ttf", "FacecheckMono-Regular.ttf", "METADATA.pb"])
        #expect(files.map(\.lastPathComponent).sorted() == expected)
    }

    @Test("With several faces cached, every cached file is registered and nothing is fetched")
    func warmCacheRegistersEveryFile() async throws {
        let stage = try Stage()
        try stage.warm("facecheckmono", ["METADATA.pb", "FacecheckMono-Italic.ttf", "FacecheckMono-Regular.ttf", "FacecheckMono-Bold.ttf"])
        let fetcher = LocalGoogleFontsFetcher(directory: stage.remote)
        let resolver = GoogleFontResolver(cache: GoogleFontCache(rootDirectory: stage.cache), fetcher: fetcher)

        let files = await resolver.resolve([Self.mono(400), Self.mono(700)])

        #expect(fetcher.requested.isEmpty)
        #expect(files.map(\.lastPathComponent).sorted() == ["FacecheckMono-Bold.ttf", "FacecheckMono-Italic.ttf", "FacecheckMono-Regular.ttf"])
    }

    @Test("A face the family does not ship is answered by the cached METADATA's nearest face, offline")
    func missingWeightAnsweredFromCachedMetadata() async throws {
        let stage = try Stage()
        try stage.warm("facecheckmono", ["METADATA.pb", "FacecheckMono-Bold.ttf"])
        let fetcher = LocalGoogleFontsFetcher(directory: stage.remote)
        let resolver = GoogleFontResolver(cache: GoogleFontCache(rootDirectory: stage.cache), fetcher: fetcher)

        let files = await resolver.resolve([Self.mono(900)])

        #expect(fetcher.requested.isEmpty)
        #expect(files.map(\.lastPathComponent) == ["FacecheckMono-Bold.ttf"])
    }

    @Test("A cache from before faces (no METADATA) fetches the METADATA and only the files it lacks")
    func legacyCacheFetchesOnlyWhatItLacks() async throws {
        let stage = try Stage()
        try stage.warm("facecheckmono", ["FacecheckMono-Regular.ttf"])
        let fetcher = LocalGoogleFontsFetcher(directory: stage.remote)
        let resolver = GoogleFontResolver(cache: GoogleFontCache(rootDirectory: stage.cache), fetcher: fetcher)

        _ = await resolver.resolve([Self.mono(400), Self.mono(700)])

        #expect(fetcher.requestedFontFiles == ["facecheckmono/FacecheckMono-Bold.ttf"])
        #expect(stage.cached("facecheckmono").contains("METADATA.pb"))
    }

    @Test("A variable family fetches its italic file when, and only when, italic is drawn")
    func variableFamilyFetchesItalicWhenDrawn() async throws {
        let stage = try Stage()
        let fetcher = LocalGoogleFontsFetcher(directory: stage.remote)
        let resolver = GoogleFontResolver(cache: GoogleFontCache(rootDirectory: stage.cache), fetcher: fetcher)

        _ = await resolver.resolve([Self.serif(400), Self.serif(700)])
        #expect(fetcher.requestedFontFiles == ["facecheckserif/FacecheckSerif[wght].ttf"])

        _ = await resolver.resolve([Self.serif(400, .italic)])
        #expect(fetcher.requestedFontFiles == [
            "facecheckserif/FacecheckSerif[wght].ttf", "facecheckserif/FacecheckSerif-Italic[wght].ttf",
        ])
    }

    @Test("prepareFonts resolves the faces the document draws, not just its families' regular face")
    func prepareFontsResolvesDrawnFaces() async throws {
        let stage = try Stage()
        let fetcher = LocalGoogleFontsFetcher(directory: stage.remote)
        let resolver = GoogleFontResolver(cache: GoogleFontCache(rootDirectory: stage.cache), fetcher: fetcher)
        let document = try PenParser.parse("""
        {"version": "2.17", "children": [
          {"type": "text", "id": "a", "content": "a", "fontFamily": "Facecheck Mono", "fontWeight": "700", "fontStyle": "italic"}
        ]}
        """)

        await resolver.prepareFonts(for: document, diagnostics: PenDiagnosticCollector())

        #expect(fetcher.requestedFontFiles == ["facecheckmono/FacecheckMono-BoldItalic.ttf"])
    }
}
