//
//  PenBundleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `woodcase bundle` and `woodcase unbundle` in the library: a bare `.pen` and its local
/// images and fonts become a bundle, and a bundle becomes a plain folder again.
struct PenBundleTests {
    /// A folder holding `Design.pen`, the images and the font it points at — one beside
    /// it, one in its `images/`, one outside the folder — and a font under `type/`.
    struct Project {
        let root: URL
        let folder: URL
        let file: URL

        static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("PenBundleTests-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            folder = root.appendingPathComponent("project")
            file = folder.appendingPathComponent("Design.pen")
            let manager = FileManager.default
            for directory in ["project/images", "project/type", "shared"] {
                try manager.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
            }
            let png = Self.fixtures.appendingPathComponent("Fixtures/blur1.png")
            try manager.copyItem(at: png, to: folder.appendingPathComponent("hero.png"))
            try manager.copyItem(at: png, to: folder.appendingPathComponent("images/other.png"))
            try manager.copyItem(at: png, to: root.appendingPathComponent("shared/photo.png"))
            try manager.copyItem(
                at: Self.fixtures.appendingPathComponent("Fonts/WoodcaseDeclaredMono.ttf"),
                to: folder.appendingPathComponent("type/Mono.ttf")
            )
            try Data(Self.document.utf8).write(to: file)
        }

        static let document = """
        {"version": "\(PenDocument.currentFormatVersion)", "children": [
          {"type": "frame", "id": "card", "name": "Card", "reusable": true, "width": 100, "height": 100,
           "fill": {"type": "image", "url": "./hero.png", "mode": "cover"},
           "children": [
             {"type": "rectangle", "id": "photo", "width": 10, "height": 10,
              "fill": {"type": "image", "url": "../shared/photo.png", "mode": "cover"}},
             {"type": "rectangle", "id": "web", "width": 10, "height": 10,
              "fill": {"type": "image", "url": "https://example.com/web.png", "mode": "cover"}},
             {"type": "rectangle", "id": "gone", "width": 10, "height": 10,
              "fill": {"type": "image", "url": "./missing.png", "mode": "cover"}}
           ]},
          {"type": "ref", "id": "inst", "ref": "card", "x": 200, "y": 0,
           "descendants": {"photo": {"fill": {"type": "image", "url": "images/other.png", "mode": "cover"}}}},
          {"type": "text", "id": "label", "content": "Hi", "fontFamily": "Woodcase Declared Mono"}
        ],
        "fonts": [{"name": "Woodcase Declared Mono", "url": "type/Mono.ttf"}]}
        """

        func references(in url: URL) throws -> [String] {
            try PenAssetReferences.collect(from: PenParser.parse(contentsOf: url)).map(\.value)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - bundle

    @Test("bundle moves the file in and copies its local images and fonts, rewriting their paths")
    func convertCopiesAssets() async throws {
        let project = try Project()
        defer { project.remove() }

        let report = try await PenBundle.convert(project.file, identity: "ana")

        let bundle = project.folder.appendingPathComponent("Design.umbra")
        #expect(report.document.path == bundle.path + "/document.pen")
        #expect(!FileManager.default.fileExists(atPath: project.file.path))
        #expect(try project.references(in: bundle).sorted() == [
            "./fonts/Mono.ttf", "./images/hero.png", "./images/other.png", "./images/photo.png",
            "./missing.png", "https://example.com/web.png",
        ])
        for asset in ["images/hero.png", "images/other.png", "images/photo.png", "fonts/Mono.ttf"] {
            #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent(asset).path))
        }
        #expect(report.copied == 4)
        #expect(report.missing == ["./missing.png"])
    }

    @Test("bundle starts the bundle's log with a `new` row and records where it came from")
    func convertLogsAndRecords() async throws {
        let project = try Project()
        defer { project.remove() }
        let originalRevision = try EditableDocument(from: PenParser.parse(contentsOf: project.file)).documentRevision

        let report = try await PenBundle.convert(project.file, identity: "ana")

        let bundle = project.folder.appendingPathComponent("Design.umbra")
        let log = ActivityLogLocation.log(for: bundle, environment: [:])
        let rows = try ActivityReader(log: log).read().events
        #expect(rows.map(\.op) == [.new])
        #expect(rows.first?.identity == "ana")
        #expect(rows.first?.revision == report.revision)
        let record = try #require(PenBundle.ConvertedFrom.read(in: bundle))
        #expect(record.file == "Design.pen")
        #expect(record.revision == originalRevision)
    }

    @Test("bundle refuses when the bundle's path is taken, and leaves the original alone")
    func convertRefusesAnExistingBundle() async throws {
        let project = try Project()
        defer { project.remove() }
        try FileManager.default.createDirectory(
            at: project.folder.appendingPathComponent("Design.umbra"), withIntermediateDirectories: true
        )

        await #expect(throws: PenBundleError.self) {
            try await PenBundle.convert(project.file, identity: nil)
        }
        #expect(FileManager.default.fileExists(atPath: project.file.path))
    }

    @Test("bundle refuses a file that is already in a bundle")
    func convertRefusesABundle() async throws {
        let project = try Project()
        defer { project.remove() }
        try await PenBundle.convert(project.file, identity: nil)

        await #expect(throws: PenBundleError.self) {
            try await PenBundle.convert(project.folder.appendingPathComponent("Design.umbra/document.pen"), identity: nil)
        }
    }

    // MARK: - unbundle

    @Test("unbundle writes a folder whose relative paths resolve, and leaves the bundle")
    func exportRoundTrips() async throws {
        let project = try Project()
        defer { project.remove() }
        try await PenBundle.convert(project.file, identity: nil)
        let bundle = project.folder.appendingPathComponent("Design.umbra")
        let folder = project.root.appendingPathComponent("exported")

        let report = try await PenBundle.export(bundle, to: folder, identity: "ana")

        #expect(report.document.path == folder.path + "/Design.pen")
        #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("document.pen").path))
        let exported = try PenParser.parse(contentsOf: report.document)
        #expect(try exported.children == PenParser.parse(contentsOf: bundle).children)
        for reference in try project.references(in: report.document) where reference.hasPrefix("./") && reference != "./missing.png" {
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(reference).path), "\(reference)")
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(PenBundle.ConvertedFrom.fileName).path))
    }

    @Test("unbundle copies in a file the bundle reached outside itself for")
    func exportGathersOutsideFiles() async throws {
        let project = try Project()
        defer { project.remove() }
        let bundle = project.root.appendingPathComponent("Loose.umbra")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data(Project.document.utf8).write(to: bundle.appendingPathComponent("document.pen"))
        try FileManager.default.copyItem(
            at: project.folder.appendingPathComponent("hero.png"), to: bundle.appendingPathComponent("hero.png")
        )
        let folder = project.root.appendingPathComponent("out")

        let report = try await PenBundle.export(bundle, to: folder, identity: nil)

        let references = try project.references(in: report.document)
        #expect(references.contains("./images/photo.png"))
        #expect(references.contains("./images/hero.png"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("images/photo.png").path))
    }

    @Test("unbundle refuses to overwrite a .pen in the folder")
    func exportRefusesToOverwrite() async throws {
        let project = try Project()
        defer { project.remove() }
        try await PenBundle.convert(project.file, identity: nil)
        try Data("{}".utf8).write(to: project.folder.appendingPathComponent("Design.pen"))

        await #expect(throws: PenBundleError.self) {
            try await PenBundle.export(project.folder.appendingPathComponent("Design.umbra"), to: project.folder, identity: nil)
        }
    }

    @Test("unbundle refuses a bare .pen")
    func exportRefusesABareFile() async throws {
        let project = try Project()
        defer { project.remove() }

        await #expect(throws: PenBundleError.self) {
            try await PenBundle.export(project.file, to: project.root, identity: nil)
        }
    }

    // MARK: - converted from

    @Test("a .pen a bundle beside it was converted from gets a warning naming the bundle and the date")
    func convertedFromWarning() async throws {
        let project = try Project()
        defer { project.remove() }
        try await PenBundle.convert(project.file, identity: nil)
        // The original comes back — a checkout, or an app that converted without moving.
        try Data(Project.document.utf8).write(to: project.file)

        let warning = try #require(PenBundle.ConvertedFrom.warning(for: project.file))

        #expect(warning.hasPrefix("Design.pen was converted to Design.umbra on "))
        #expect(warning.contains("; edit that instead."))
        #expect(!warning.contains("changed since"))
    }

    @Test("the warning says when the original changed after the conversion")
    func convertedFromWarningNotesChanges() async throws {
        let project = try Project()
        defer { project.remove() }
        try await PenBundle.convert(project.file, identity: nil)
        try Data(Project.document.replacingOccurrences(of: "\"Hi\"", with: "\"Changed\"").utf8).write(to: project.file)

        let warning = try #require(PenBundle.ConvertedFrom.warning(for: project.file))

        #expect(warning.contains("Design.pen has changed since"))
    }

    @Test("no warning for a .pen no bundle was converted from")
    func noWarningOtherwise() throws {
        let project = try Project()
        defer { project.remove() }

        #expect(PenBundle.ConvertedFrom.warning(for: project.file) == nil)
    }
}
