//
//  PenBundleHistoryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Whether a bundle's `history/` goes with a copy: `copy` (Save As, Duplicate, Save To)
/// and `export` (Export, `unbundle`) both take the choice.
struct PenBundleHistoryTests {
    typealias Project = PenBundleTests.Project

    /// The writers' files seeded beside the one `convert` wrote: a live file, an
    /// archive, and two files readers ignore.
    static let writerFiles = ["claude@mac.jsonl", "ben@grace.20260829T163104Z.jsonl"]
    static let ignoredFiles = ["activity.jsonl", "ben@grace 2.jsonl"]

    /// A bundle with three writers' history, local state and its own `.gitignore`.
    struct Source {
        let project: Project
        let bundle: URL
        let converted: String

        init() async throws {
            project = try Project()
            bundle = project.folder.appendingPathComponent("Design.umbra")
            try await PenBundle.convert(project.file, identity: "ana")
            let history = bundle.appendingPathComponent("history")
            converted = try #require(FileManager.default.contentsOfDirectory(atPath: history.path).first)
            for name in PenBundleHistoryTests.writerFiles + PenBundleHistoryTests.ignoredFiles {
                try Data("{\"from\":\"\(name)\"}\n".utf8).write(to: history.appendingPathComponent(name))
            }
            let state = bundle.appendingPathComponent(".woodcase")
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
            try Data("local".utf8).write(to: state.appendingPathComponent("views.json"))
            try Data(".woodcase/\n".utf8).write(to: bundle.appendingPathComponent(".gitignore"))
        }

        /// The writers' files a history-carrying copy must hold.
        var carried: [String] {
            ([converted] + PenBundleHistoryTests.writerFiles).sorted()
        }

        func historyNames(in directory: URL) -> [String] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return names.sorted()
        }
    }

    // MARK: - copy

    @Test("copy with history included carries every writer's file, byte for byte, and not the rest of history/")
    func copyIncludedCarriesEveryWriter() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let destination = source.project.root.appendingPathComponent("Copy.umbra")

        let report = try await PenBundle.copy(source.bundle, to: destination, history: .included)

        let history = destination.appendingPathComponent("history")
        #expect(source.historyNames(in: history) == source.carried)
        #expect(report.historyCopied == 3)
        for name in source.carried {
            #expect(try Data(contentsOf: history.appendingPathComponent(name))
                == Data(contentsOf: source.bundle.appendingPathComponent("history/\(name)")))
        }
    }

    @Test("copy with history omitted carries no writer's file")
    func copyOmittedCarriesNone() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let destination = source.project.root.appendingPathComponent("Copy.umbra")

        let report = try await PenBundle.copy(source.bundle, to: destination, history: .omitted)

        #expect(source.historyNames(in: destination.appendingPathComponent("history")).isEmpty)
        #expect(report.historyCopied == 0)
    }

    @Test("copy carries the document, images and fonts either way, and leaves local state and .gitignore behind")
    func copyCarriesTheDesignNotTheLocalState() async throws {
        let source = try await Source()
        defer { source.project.remove() }

        for (index, history) in [HistoryInclusion.included, .omitted].enumerated() {
            let destination = source.project.root.appendingPathComponent("Copy\(index).umbra")
            let report = try await PenBundle.copy(source.bundle, to: destination, history: history)

            #expect(try Data(contentsOf: destination.appendingPathComponent("document.pen"))
                == Data(contentsOf: source.bundle.appendingPathComponent("document.pen")))
            for asset in ["images/hero.png", "images/other.png", "images/photo.png", "fonts/Mono.ttf"] {
                #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent(asset).path), "\(asset)")
            }
            #expect(report.copied == 4)
            #expect(report.document.path == destination.path + "/document.pen")
            #expect(try report.revision == EditableDocument(from: PenParser.parse(contentsOf: destination)).documentRevision)
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent(".woodcase").path))
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent(".gitignore").path))
        }
    }

    @Test("a copy with history reads as one history with the source's rows, and its next edit adds to it")
    func copyHistoryIsReadable() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let destination = source.project.root.appendingPathComponent("Copy.umbra")

        try await PenBundle.copy(source.bundle, to: destination, history: .included)

        let rows = try ActivityReader(log: ActivityLogLocation.log(for: destination, environment: [:])).read().events
        #expect(rows.map(\.op) == [.new])
        #expect(rows.first?.identity == "ana")
    }

    @Test("copy re-roots the converted-from record to the copy's folder")
    func copyRecordsTheOriginalFromTheNewFolder() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let destination = source.project.root.appendingPathComponent("elsewhere/Copy.umbra")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let original = try #require(PenBundle.ConvertedFrom.read(in: source.bundle))

        try await PenBundle.copy(source.bundle, to: destination, history: .omitted)

        let record = try #require(PenBundle.ConvertedFrom.read(in: destination))
        #expect(record.file == "../project/Design.pen")
        #expect(record.revision == original.revision)
    }

    @Test("copy refuses a taken destination, a non-bundle destination and a bare source, writing nothing")
    func copyRefusals() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let taken = source.project.root.appendingPathComponent("Taken.umbra")
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: true)
        let bare = source.project.root.appendingPathComponent("Bare.pen")

        await #expect(throws: PenBundleError.destinationExists(taken)) {
            try await PenBundle.copy(source.bundle, to: taken, history: .included)
        }
        await #expect(throws: PenBundleError.notABundle(bare)) {
            try await PenBundle.copy(source.bundle, to: bare, history: .included)
        }
        await #expect(throws: PenBundleError.notABundle(source.project.file)) {
            try await PenBundle.copy(
                source.project.file, to: source.project.root.appendingPathComponent("X.umbra"), history: .included
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: taken.path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: bare.path))
        #expect(!FileManager.default.fileExists(atPath: source.project.root.appendingPathComponent("X.umbra").path))
    }

    // MARK: - export

    @Test("export with history included copies every writer's file into the folder's history/")
    func exportIncluded() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let folder = source.project.root.appendingPathComponent("exported")

        let report = try await PenBundle.export(source.bundle, to: folder, identity: nil, history: .included)

        #expect(source.historyNames(in: folder.appendingPathComponent("history")) == source.carried)
        #expect(report.historyCopied == 3)
        #expect(FileManager.default.fileExists(atPath: report.document.path))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(".gitignore").path))
    }

    @Test("export with history omitted carries none")
    func exportOmitted() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let folder = source.project.root.appendingPathComponent("exported")

        let report = try await PenBundle.export(source.bundle, to: folder, identity: nil, history: .omitted)

        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("history").path))
        #expect(report.historyCopied == 0)
    }

    @Test("export with history refuses a folder that already holds one of the writer's files, and writes nothing")
    func exportRefusesAHistoryCollision() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let folder = source.project.root.appendingPathComponent("exported")
        let existing = folder.appendingPathComponent("history/claude@mac.jsonl")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("other".utf8).write(to: existing)

        await #expect(throws: PenBundleError.destinationExists(existing)) {
            try await PenBundle.export(source.bundle, to: folder, identity: nil, history: .included)
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Design.pen").path))
        #expect(try Data(contentsOf: existing) == Data("other".utf8))
    }

    @Test("export with a font plan takes the same choice")
    func exportWithPlanTakesTheChoice() async throws {
        let source = try await Source()
        defer { source.project.remove() }
        let plan = PenFolderFontPlan(families: [], themeCoverage: .everyCombination(count: 1))

        let folder = source.project.root.appendingPathComponent("planned")
        let report = try await PenBundle.export(
            source.bundle, to: folder, identity: nil, history: .included, fontPlan: plan, bundling: []
        )

        #expect(report.historyCopied == 3)
        #expect(source.historyNames(in: folder.appendingPathComponent("history")) == source.carried)
    }
}
