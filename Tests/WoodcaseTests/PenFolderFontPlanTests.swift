//
//  PenFolderFontPlanTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Which of a document's font families a Pen Folder export can carry, and why the rest
/// cannot: the system's, Google's, the document's own, this Mac's, and none at all.
@Suite("PenFolderFontPlan")
struct PenFolderFontPlanTests {
    static let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fonts")
    static let declaredMono = fonts.appendingPathComponent("WoodcaseDeclaredMono.ttf")

    /// A resolver over a fresh temporary cache whose fetcher answers `responses` and 404s
    /// everything else.
    static func resolver(_ responses: [String: Result<Data, Error>] = [:]) -> GoogleFontResolver {
        GoogleFontResolver(
            cache: GoogleFontCache(rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("PenFolderFontPlanTests-\(UUID().uuidString)")),
            fetcher: MockFontFetcher(responses: responses)
        )
    }

    /// A resolver that knows Inter is on Google Fonts.
    static func googleKnowsInter() throws -> GoogleFontResolver {
        let metadata = try Data(contentsOf: fonts.appendingPathComponent("GoogleFonts/inter.METADATA.pb"))
        return resolver(["ofl/inter/METADATA.pb": .success(metadata)])
    }

    /// A document of one text node per `(family, weight, style)`, plus `extra` root JSON.
    static func document(_ texts: [(String, String?, String?)], extra: String = "") throws -> PenDocument {
        let nodes = texts.enumerated().map { index, text in
            var node = #"{"type": "text", "id": "t\#(index)", "content": "Aa", "fontFamily": "\#(text.0)""#
            if let weight = text.1 { node += #", "fontWeight": "\#(weight)""# }
            if let style = text.2 { node += #", "fontStyle": "\#(style)""# }
            return node + "}"
        }
        return try PenParser.parse("""
        {"version": "\(PenDocument.currentFormatVersion)", "children": [\(nodes.joined(separator: ", "))]\(extra)}
        """)
    }

    static func family(_ name: String, in plan: PenFolderFontPlan) throws -> PenFolderFontPlan.Family {
        try #require(plan.families.first { $0.name == name })
    }

    @Test("An Apple system font is listed, unchecked and disabled, as a system font")
    func systemFont() async throws {
        let plan = try await PenFolderFontPlan.make(
            for: Self.document([("Helvetica", nil, nil)]), relativeTo: nil, fonts: Self.resolver()
        )
        let helvetica = try Self.family("Helvetica", in: plan)
        #expect(helvetica.source == .system)
        #expect(helvetica.reason == .systemFont)
        #expect(!helvetica.isBundleable)
        #expect(!helvetica.startsChecked)
        #expect(helvetica.files.isEmpty)
    }

    @Test("A Google Fonts family is listed, unchecked and disabled: Pen downloads it by name")
    func googleFont() async throws {
        let plan = try await PenFolderFontPlan.make(
            for: Self.document([("Inter", "600", nil)]), relativeTo: nil, fonts: Self.googleKnowsInter()
        )
        let inter = try Self.family("Inter", in: plan)
        #expect(inter.source == .googleFonts)
        #expect(inter.reason == .googleFonts)
        #expect(!inter.isBundleable)
        #expect(!inter.startsChecked)
        #expect(inter.faces == [PenFontFace(family: "Inter", weight: 600, style: .normal)])
    }

    @Test("A declared font is bundleable and checked, with its file, fsType and license")
    func declaredFont() async throws {
        let extra = #", "fonts": [{"name": "Woodcase Declared Mono", "url": "\#(Self.declaredMono.path)"}]"#
        let plan = try await PenFolderFontPlan.make(
            for: Self.document([("Woodcase Declared Mono", nil, nil)], extra: extra),
            relativeTo: nil, fonts: Self.resolver()
        )
        let mono = try Self.family("Woodcase Declared Mono", in: plan)
        #expect(mono.source == .declared)
        #expect(mono.reason == nil)
        #expect(mono.isBundleable)
        #expect(mono.startsChecked)
        let file = try #require(mono.files.first)
        #expect(mono.files.count == 1)
        #expect(file.url.standardizedFileURL == Self.declaredMono.standardizedFileURL)
        #expect(file.familyName == "Woodcase Declared Mono")
        #expect(file.embedding?.permission == .installable)
        #expect(file.license?.url == URL(string: "https://scripts.sil.org/OFL"))
        #expect(file.license?.description?.hasPrefix("This Font Software is licensed under the SIL Open Font License") == true)
        #expect(mono.permission == .installable)
    }

    @Test("A declared font is declared even when Google Fonts has a family of the name")
    func declaredBeatsGoogle() async throws {
        let inter = Self.fonts.appendingPathComponent("Inter[opsz,wght].ttf")
        let extra = #", "fonts": [{"name": "Inter", "url": "\#(inter.path)", "weight": [100, 900]}]"#
        let plan = try await PenFolderFontPlan.make(
            for: Self.document([("Inter", nil, nil)], extra: extra), relativeTo: nil, fonts: Self.googleKnowsInter()
        )
        let family = try Self.family("Inter", in: plan)
        #expect(family.source == .declared)
        #expect(family.files.first?.weight == .range(from: 100, to: 900))
    }

    @Test("A relative declared url resolves against the document's file")
    func relativeDeclaredFont() async throws {
        let extra = #", "fonts": [{"name": "Woodcase Declared Mono", "url": "WoodcaseDeclaredMono.ttf"}]"#
        let plan = try await PenFolderFontPlan.make(
            for: Self.document([("Woodcase Declared Mono", nil, nil)], extra: extra),
            relativeTo: Self.fonts.appendingPathComponent("design.pen"), fonts: Self.resolver()
        )
        let mono = try Self.family("Woodcase Declared Mono", in: plan)
        #expect(mono.source == .declared)
        #expect(mono.files.map(\.url.lastPathComponent) == ["WoodcaseDeclaredMono.ttf"])
    }

    @Test("A font declared only at a web address is kept as written, not bundled")
    func remoteDeclaredFont() async throws {
        let extra = #", "fonts": [{"name": "Brand Sans", "url": "https://fonts.example.com/Brand.ttf"}]"#
        let plan = try await PenFolderFontPlan.make(
            for: Self.document([("Brand Sans", nil, nil)], extra: extra), relativeTo: nil, fonts: Self.resolver()
        )
        let brand = try Self.family("Brand Sans", in: plan)
        #expect(brand.source == .declared)
        #expect(brand.reason == .declaredRemotely)
        #expect(!brand.isBundleable)
        #expect(!brand.startsChecked)
    }

    @Test("A font declared at a local file that is not there is missing")
    func declaredFileMissing() async throws {
        let extra = #", "fonts": [{"name": "Brand Sans", "url": "/nowhere/Brand.ttf"}]"#
        let plan = try await PenFolderFontPlan.make(
            for: Self.document([("Brand Sans", nil, nil)], extra: extra), relativeTo: nil, fonts: Self.resolver()
        )
        let brand = try Self.family("Brand Sans", in: plan)
        #expect(brand.source == .missing)
        #expect(brand.reason == .notFound)
        #expect(!brand.isBundleable)
    }

    @Test("An installed static family lists the file of each face the document draws, under its real name")
    func installedStaticFamily() async throws {
        TestFontRegistration.registerTestFonts()
        let plan = try await PenFolderFontPlan.make(
            for: Self.document([("Woodcase Static Sans", nil, nil), ("Woodcase Static Sans", "700", nil)]),
            relativeTo: nil, fonts: Self.resolver()
        )
        let sans = try Self.family("Woodcase Static Sans", in: plan)
        #expect(sans.source == .installed)
        #expect(sans.reason == nil)
        #expect(sans.isBundleable)
        #expect(sans.startsChecked)
        #expect(sans.faces == [
            PenFontFace(family: "Woodcase Static Sans", weight: 400, style: .normal),
            PenFontFace(family: "Woodcase Static Sans", weight: 700, style: .normal),
        ])
        #expect(sans.files.map(\.url.lastPathComponent) == ["WoodcaseStaticSans-Bold.ttf", "WoodcaseStaticSans-Regular.ttf"])
        #expect(sans.files.map(\.weight) == [.single(700), .single(400)])
        #expect(sans.files.allSatisfy { $0.familyName == "Woodcase Static Sans" && $0.style == .normal })
        #expect(sans.files.allSatisfy { $0.embedding?.permission == .installable })
    }

    @Test("An installed variable family's file declares its whole weight range")
    func installedVariableFamily() async throws {
        TestFontRegistration.registerTestFonts()
        let plan = try await PenFolderFontPlan.make(
            for: Self.document([("IBM Plex Sans", "500", nil)]), relativeTo: nil, fonts: Self.resolver()
        )
        let plex = try Self.family("IBM Plex Sans", in: plan)
        #expect(plex.source == .installed)
        #expect(plex.files.map(\.url.lastPathComponent) == ["IBMPlexSans[wdth,wght].ttf"])
        #expect(plex.files.first?.weight == .range(from: 100, to: 700))
    }

    @Test("A family nothing provides is missing, disabled, not found")
    func missingFamily() async throws {
        let plan = try await PenFolderFontPlan.make(
            for: Self.document([("Woodcase Nowhere Sans", nil, nil)]), relativeTo: nil, fonts: Self.resolver()
        )
        let nowhere = try Self.family("Woodcase Nowhere Sans", in: plan)
        #expect(nowhere.source == .missing)
        #expect(nowhere.reason == .notFound)
        #expect(!nowhere.isBundleable)
        #expect(!nowhere.startsChecked)
    }

    @Test("A missing family Google Fonts could not be asked about says so")
    func googleUnreachable() async throws {
        let offline = Self.resolver(["METADATA.pb": .failure(URLError(.notConnectedToInternet))])
        let plan = try await PenFolderFontPlan.make(
            for: Self.document([("Woodcase Nowhere Sans", nil, nil)]), relativeTo: nil, fonts: offline
        )
        let nowhere = try Self.family("Woodcase Nowhere Sans", in: plan)
        #expect(nowhere.source == .missing)
        #expect(nowhere.reason == .googleFontsUnreachable)
    }

    @Test("Families are listed once each, sorted, and a node with no family adds none")
    func listsFamiliesSorted() async throws {
        TestFontRegistration.registerTestFonts()
        let document = try PenParser.parse("""
        {"version": "\(PenDocument.currentFormatVersion)", "children": [
          {"type": "text", "id": "a", "content": "a", "fontFamily": "Woodcase Static Sans"},
          {"type": "text", "id": "b", "content": "b", "fontFamily": "Helvetica"},
          {"type": "text", "id": "c", "content": "c", "fontFamily": "Woodcase Static Sans", "fontWeight": "700"},
          {"type": "text", "id": "d", "content": "d"}
        ]}
        """)
        let plan = await PenFolderFontPlan.make(for: document, relativeTo: nil, fonts: Self.resolver())
        #expect(plan.families.map(\.name) == ["Helvetica", "Woodcase Static Sans"])
    }

    @Test("A family variable contributes the family it takes under every theme")
    func everyTheme() async throws {
        let document = try PenParser.parse("""
        {"version": "\(PenDocument.currentFormatVersion)",
         "themes": {"mode": ["light", "dark"], "size": ["s", "l"]},
         "variables": {
           "face": {"type": "string", "value": [
             {"value": "Woodcase Nowhere Sans", "theme": {"mode": "light"}},
             {"value": "Woodcase Elsewhere Sans", "theme": {"mode": "dark"}}]},
           "heavy": {"type": "string", "value": [
             {"value": "400", "theme": {"size": "s"}},
             {"value": "700", "theme": {"size": "l"}}]}
         },
         "children": [{"type": "text", "id": "a", "content": "a", "fontFamily": "$face", "fontWeight": "$heavy"}]}
        """)
        let plan = await PenFolderFontPlan.make(for: document, relativeTo: nil, fonts: Self.resolver())
        #expect(plan.families.map(\.name) == ["Woodcase Elsewhere Sans", "Woodcase Nowhere Sans"])
        #expect(try Self.family("Woodcase Nowhere Sans", in: plan).faces.map(\.weight) == [400, 700])
        #expect(plan.themeCoverage == .everyCombination(count: 4))
    }

    @Test("Past the combination limit, each option of each axis is resolved alone, and the plan says so")
    func tooManyThemes() {
        let options = ["a", "b", "c", "d", "e"]
        let (themes, coverage) = PenFolderFontPlan.themeSelections(["x": options, "y": options, "z": options])
        #expect(coverage == .eachOptionAlone(count: 13))
        #expect(themes.first == [:])
        #expect(themes.contains(["y": "e"]))
        let (small, smallCoverage) = PenFolderFontPlan.themeSelections(["x": ["a", "b"], "y": ["c", "d", "e"]])
        #expect(smallCoverage == .everyCombination(count: 6))
        #expect(small.contains(["x": "b", "y": "e"]))
        #expect(PenFolderFontPlan.themeSelections([:]).coverage == .everyCombination(count: 1))
    }

    @Test("Text inside an instance of a component counts")
    func instances() async throws {
        let document = try PenParser.parse("""
        {"version": "\(PenDocument.currentFormatVersion)", "children": [
          {"type": "frame", "id": "card", "reusable": true, "children": [
            {"type": "text", "id": "label", "content": "a", "fontFamily": "Woodcase Nowhere Sans"}]},
          {"type": "ref", "id": "inst", "ref": "card", "descendants": {"label": {"fontFamily": "Woodcase Elsewhere Sans"}}}
        ]}
        """)
        let plan = await PenFolderFontPlan.make(for: document, relativeTo: nil, fonts: Self.resolver())
        #expect(plan.families.map(\.name) == ["Woodcase Elsewhere Sans", "Woodcase Nowhere Sans"])
    }

    @Test("A restricted or preview-only font starts checked, flagged; an unreadable one is flagged too")
    func embeddingFlags() {
        func family(_ embeddings: [PenFontEmbedding?]) -> PenFolderFontPlan.Family {
            PenFolderFontPlan.Family(
                name: "Brand Sans", faces: [], source: .installed,
                files: embeddings.map {
                    PenFolderFontPlan.FontFile(
                        url: URL(fileURLWithPath: "/fonts/Brand.ttf"), familyName: "Brand Sans",
                        style: .normal, weight: .single(400), embedding: $0, license: nil
                    )
                }
            )
        }
        let restricted = family([PenFontEmbedding(fsType: 0x2)])
        #expect(restricted.reason == .restrictedEmbedding)
        #expect(restricted.startsChecked)
        #expect(restricted.permission == .restricted)
        let preview = family([PenFontEmbedding(fsType: 0x8), PenFontEmbedding(fsType: 0x4)])
        #expect(preview.reason == .previewAndPrintEmbedding)
        #expect(preview.startsChecked)
        #expect(preview.permission == .previewAndPrint)
        let unreadable = family([PenFontEmbedding(fsType: 0), nil])
        #expect(unreadable.reason == .unreadableEmbedding)
        #expect(unreadable.startsChecked)
        let editable = family([PenFontEmbedding(fsType: 0x8)])
        #expect(editable.reason == nil)
        #expect(editable.permission == .editable)
    }
}
