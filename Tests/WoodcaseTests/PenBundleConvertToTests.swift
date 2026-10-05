//
//  PenBundleConvertToTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An app's conversion: a bare `.pen` becomes a bundle where the user chose, and the
/// original stays where it was.
struct PenBundleConvertToTests {
    typealias Project = PenBundleTests.Project

    @Test("convert to a chosen bundle copies the local images and fonts and keeps the original")
    func convertToKeepsTheOriginal() async throws {
        let project = try Project()
        defer { project.remove() }
        let original = try Data(contentsOf: project.file)
        let bundle = project.folder.appendingPathComponent("Chosen.umbra")

        let report = try await PenBundle.convert(project.file, to: bundle, identity: "ana")

        #expect(report.document.path == bundle.path + "/document.pen")
        #expect(try Data(contentsOf: project.file) == original)
        #expect(try project.references(in: bundle).sorted() == [
            "./fonts/Mono.ttf", "./images/hero.png", "./images/other.png", "./images/photo.png",
            "./missing.png", "https://example.com/web.png",
        ])
        #expect(report.copied == 4)
        #expect(report.missing == ["./missing.png"])
        let rows = try ActivityReader(log: ActivityLogLocation.log(for: bundle, environment: [:])).read().events
        #expect(rows.map(\.op) == [.new])
    }

    @Test("convert to a bundle in another folder records the original relative to the bundle's folder")
    func convertToAnotherFolderRecordsTheRelativePath() async throws {
        let project = try Project()
        defer { project.remove() }
        let elsewhere = project.root.appendingPathComponent("shared")
        let bundle = elsewhere.appendingPathComponent("Design.umbra")
        let originalRevision = try EditableDocument(from: PenParser.parse(contentsOf: project.file)).documentRevision

        try await PenBundle.convert(project.file, to: bundle, identity: nil)

        let record = try #require(PenBundle.ConvertedFrom.read(in: bundle))
        #expect(record.file == "../project/Design.pen")
        #expect(record.revision == originalRevision)
        #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("images/hero.png").path))
    }

    @Test("convert to the default place beside the original still warns about the original")
    func convertBesideWarns() async throws {
        let project = try Project()
        defer { project.remove() }

        try await PenBundle.convert(project.file, to: project.folder.appendingPathComponent("Design.umbra"), identity: nil)

        let warning = try #require(PenBundle.ConvertedFrom.warning(for: project.file))
        #expect(warning.hasPrefix("Design.pen was converted to Design.umbra on "))
    }

    @Test("convert to refuses a destination that is taken, and writes nothing")
    func convertToRefusesATakenDestination() async throws {
        let project = try Project()
        defer { project.remove() }
        let bundle = project.folder.appendingPathComponent("Design.umbra")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        await #expect(throws: PenBundleError.destinationExists(bundle)) {
            try await PenBundle.convert(project.file, to: bundle, identity: nil)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: bundle.path).isEmpty)
    }

    @Test("convert to refuses a destination that is not a bundle")
    func convertToRefusesABareDestination() async throws {
        let project = try Project()
        defer { project.remove() }
        let destination = project.folder.appendingPathComponent("Other.pen")

        await #expect(throws: PenBundleError.notABundle(destination)) {
            try await PenBundle.convert(project.file, to: destination, identity: nil)
        }
    }

    @Test("convert to refuses a file already in a bundle")
    func convertToRefusesABundledFile() async throws {
        let project = try Project()
        defer { project.remove() }
        try await PenBundle.convert(project.file, identity: nil)
        let inner = project.folder.appendingPathComponent("Design.umbra/document.pen")

        await #expect(throws: PenBundleError.self) {
            try await PenBundle.convert(inner, to: project.folder.appendingPathComponent("Again.umbra"), identity: nil)
        }
    }

    @Test("a file that cannot be read is reported missing, and the rest is converted")
    func unreadableAssetIsMissing() async throws {
        let project = try Project()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: project.folder.appendingPathComponent("hero.png").path
            )
            project.remove()
        }
        let hero = project.folder.appendingPathComponent("hero.png")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: hero.path)
        let bundle = project.folder.appendingPathComponent("Design.umbra")

        let report = try await PenBundle.convert(project.file, to: bundle, identity: nil)

        #expect(report.missing.sorted() == ["./hero.png", "./missing.png"])
        #expect(report.copied == 3)
        #expect(try project.references(in: bundle).contains("./hero.png"))
    }
}
