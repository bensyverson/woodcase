//
//  PenFolderFontPlanExportTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a Pen Folder export writes for the families the designer checked: declarations
/// under each font's real family name, the files copied into `fonts/` beside the .pen,
/// every url relative to it, and nothing for a family left unchecked.
@Suite("PenFolderFontPlan export")
struct PenFolderFontPlanExportTests {
    private static let fonts = PenFolderFontPlanTests.fonts
    private static let staticSans = fonts.appendingPathComponent("StaticSans")

    /// One installed static family of two files, and a declared one.
    private static func plan() -> PenFolderFontPlan {
        let file = { (name: String, weight: Double) in
            PenFolderFontPlan.FontFile(
                url: staticSans.appendingPathComponent(name), familyName: "Woodcase Static Sans",
                style: .normal, weight: .single(weight), embedding: PenFontEmbedding(fsType: 0), license: nil
            )
        }
        return PenFolderFontPlan(families: [
            PenFolderFontPlan.Family(
                name: "Woodcase Declared Mono", faces: [.regular(of: "Woodcase Declared Mono")], source: .declared,
                files: [PenFolderFontPlan.FontFile(
                    url: fonts.appendingPathComponent("WoodcaseDeclaredMono.ttf"), familyName: "Woodcase Declared Mono",
                    style: .normal, weight: .single(400), embedding: PenFontEmbedding(fsType: 0), license: nil
                )]
            ),
            PenFolderFontPlan.Family(
                name: "woodcase static sans", faces: [.regular(of: "woodcase static sans")], source: .installed,
                files: [file("WoodcaseStaticSans-Regular.ttf", 400), file("WoodcaseStaticSans-Bold.ttf", 700)]
            ),
            PenFolderFontPlan.Family(name: "Helvetica", faces: [.regular(of: "Helvetica")], source: .system, files: []),
        ], themeCoverage: .everyCombination(count: 1))
    }

    private static let source = """
    {"version": "\(PenDocument.currentFormatVersion)", "children": [
      {"type": "text", "id": "a", "content": "a", "fontFamily": "Woodcase Declared Mono"},
      {"type": "text", "id": "b", "content": "b", "fontFamily": "woodcase static sans"}
    ], "fonts": [
      {"name": "Woodcase Declared Mono", "url": "mono/WoodcaseDeclaredMono.ttf"},
      {"name": "Woodcase Declared Mono", "url": "https://fonts.example.com/Mono-Bold.ttf", "weight": 700}
    ]}
    """

    @Test("A checked installed family is declared file by file under its real name; the rest is left alone")
    func declaresInstalledFamily() throws {
        let document = try PenParser.parse(Self.source)
        let exported = Self.plan().exportedDocument(
            document, bundling: ["Woodcase Declared Mono", "woodcase static sans", "Helvetica"]
        )
        #expect(exported.fonts == (document.fonts ?? []) + [
            PenFontDeclaration(
                name: "Woodcase Static Sans", url: Self.staticSans.appendingPathComponent("WoodcaseStaticSans-Regular.ttf").path,
                style: .normal, weight: .single(400)
            ),
            PenFontDeclaration(
                name: "Woodcase Static Sans", url: Self.staticSans.appendingPathComponent("WoodcaseStaticSans-Bold.ttf").path,
                style: .normal, weight: .single(700)
            ),
        ])
        #expect(exported.children == document.children)
    }

    @Test("An unchecked installed family is not declared, and an unchecked declared one loses its local files")
    func uncheckedFamilies() throws {
        let document = try PenParser.parse(Self.source)
        let exported = Self.plan().exportedDocument(document, bundling: [])
        #expect(exported.fonts == [
            PenFontDeclaration(name: "Woodcase Declared Mono", url: "https://fonts.example.com/Mono-Bold.ttf", weight: .single(700)),
        ])
    }

    @Test("A declared family the plan classed as Apple's loses its local files, even when listed as checked")
    func appleMadeDeclaredFamily() throws {
        let document = try PenParser.parse("""
        {"version": "\(PenDocument.currentFormatVersion)", "children": [
          {"type": "text", "id": "a", "content": "a", "fontFamily": "SF Pro"}
        ], "fonts": [
          {"name": "SF Pro", "url": "/Library/Fonts/SF-Pro.ttf"},
          {"name": "SF Pro", "url": "https://fonts.example.com/SF-Pro.ttf"}
        ]}
        """)
        let plan = PenFolderFontPlan(families: [
            PenFolderFontPlan.Family(name: "SF Pro", faces: [.regular(of: "SF Pro")], source: .system, files: []),
        ], themeCoverage: .everyCombination(count: 1))
        for bundling: Set<String> in [[], ["SF Pro"]] {
            #expect(plan.exportedDocument(document, bundling: bundling).fonts == [
                PenFontDeclaration(name: "SF Pro", url: "https://fonts.example.com/SF-Pro.ttf"),
            ])
        }
    }

    @Test("A variable file is declared with its weight range")
    func variableRange() throws {
        let plan = PenFolderFontPlan(families: [PenFolderFontPlan.Family(
            name: "IBM Plex Sans", faces: [], source: .installed,
            files: [PenFolderFontPlan.FontFile(
                url: URL(fileURLWithPath: "/fonts/Plex.ttf"), familyName: "IBM Plex Sans",
                style: .italic, weight: .range(from: 100, to: 700), embedding: nil, license: nil
            )]
        )], themeCoverage: .everyCombination(count: 1))
        let exported = try plan.exportedDocument(PenParser.parse(#"{"version": "2.17", "children": []}"#), bundling: ["IBM Plex Sans"])
        #expect(exported.fonts == [PenFontDeclaration(
            name: "IBM Plex Sans", url: "/fonts/Plex.ttf", style: .italic, weight: .range(from: 100, to: 700)
        )])
    }

    @Test("Exporting a bundle copies the checked families' files into fonts/ and points every declaration there")
    func exportsBundle() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFolderFontPlanExportTests-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Design.umbra")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("mono"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: Self.fonts.appendingPathComponent("WoodcaseDeclaredMono.ttf"),
            to: bundle.appendingPathComponent("mono/WoodcaseDeclaredMono.ttf")
        )
        try Data(Self.source.utf8).write(to: bundle.appendingPathComponent("document.pen"))
        let folder = root.appendingPathComponent("Out")

        let report = try await PenBundle.export(
            bundle, to: folder, identity: nil,
            fontPlan: Self.plan(), bundling: ["Woodcase Declared Mono", "woodcase static sans"]
        )

        let exported = try PenParser.parse(contentsOf: report.document)
        #expect(exported.fonts?.map(\.url) == [
            "./fonts/WoodcaseDeclaredMono.ttf",
            "https://fonts.example.com/Mono-Bold.ttf",
            "./fonts/WoodcaseStaticSans-Regular.ttf",
            "./fonts/WoodcaseStaticSans-Bold.ttf",
        ])
        #expect(exported.fonts?.map(\.name).last == "Woodcase Static Sans")
        for name in ["WoodcaseDeclaredMono.ttf", "WoodcaseStaticSans-Regular.ttf", "WoodcaseStaticSans-Bold.ttf"] {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("fonts/\(name)").path))
        }
        #expect(report.copied == 3)
    }

    @Test("Exporting without a plan copies no font file Apple made, inside the bundle or out, and drops its declaration")
    func planlessExportSkipsAppleMadeFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFolderFontPlanExportTests-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Design.umbra")
        let elsewhere = root.appendingPathComponent("Library/Fonts")
        for directory in [bundle.appendingPathComponent("mono"), bundle.appendingPathComponent("brand"), elsewhere] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.copyItem(
            at: Self.fonts.appendingPathComponent("WoodcaseDeclaredMono.ttf"),
            to: bundle.appendingPathComponent("mono/WoodcaseDeclaredMono.ttf")
        )
        let appleMade = SyntheticFont.file(vendor: "APPL", names: [.windows(1, "SF Pro")])
        try appleMade.write(to: bundle.appendingPathComponent("brand/AppleSans.ttf"))
        try appleMade.write(to: elsewhere.appendingPathComponent("SF-Pro.ttf"))
        try Data("""
        {"version": "\(PenDocument.currentFormatVersion)", "children": [
          {"type": "text", "id": "a", "content": "a", "fontFamily": "Woodcase Declared Mono"},
          {"type": "text", "id": "b", "content": "b", "fontFamily": "SF Pro"}
        ], "fonts": [
          {"name": "Woodcase Declared Mono", "url": "mono/WoodcaseDeclaredMono.ttf"},
          {"name": "Woodcase Apple Sans", "url": "brand/AppleSans.ttf"},
          {"name": "SF Pro", "url": "\(elsewhere.appendingPathComponent("SF-Pro.ttf").path)"},
          {"name": "SF Pro", "url": "https://fonts.example.com/SF-Pro.ttf"}
        ]}
        """.utf8).write(to: bundle.appendingPathComponent("document.pen"))
        let folder = root.appendingPathComponent("Out")

        let report = try await PenBundle.export(bundle, to: folder, identity: nil)

        let exported = try PenParser.parse(contentsOf: report.document)
        #expect(exported.fonts?.map(\.url) == [
            "./fonts/WoodcaseDeclaredMono.ttf",
            "https://fonts.example.com/SF-Pro.ttf",
        ])
        let copied = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("fonts").path)
        #expect(copied == ["WoodcaseDeclaredMono.ttf"])
        #expect(report.copied == 1)
        #expect(report.missing.isEmpty)
    }

    @Test("The bundle's plan reads the document through the bundle")
    func plansBundle() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFolderFontPlanExportTests-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Design.umbra")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("mono"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: Self.fonts.appendingPathComponent("WoodcaseDeclaredMono.ttf"),
            to: bundle.appendingPathComponent("mono/WoodcaseDeclaredMono.ttf")
        )
        try Data(Self.source.utf8).write(to: bundle.appendingPathComponent("document.pen"))

        let plan = try await PenBundle.exportFontPlan(bundle, fonts: PenFolderFontPlanTests.resolver())
        let mono = try #require(plan.families.first { $0.name == "Woodcase Declared Mono" })
        #expect(mono.source == .declared)
        #expect(mono.files.map(\.url.lastPathComponent) == ["WoodcaseDeclaredMono.ttf"])
    }
}
