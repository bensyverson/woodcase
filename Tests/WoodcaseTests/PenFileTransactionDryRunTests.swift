//
//  PenFileTransactionDryRunTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Exercises ``WriteEffect/dryRun``: the transaction runs exactly as a write does —
/// same lock, same parse, same body, same settling — and then throws the result away.
///
/// The promise this suite pins is a negative one: after a dry run the file's bytes, its
/// revision and the activity log are what they were before. Everything else about the
/// transaction is unchanged, which is why ``LintPreview`` can be asked what the write
/// *would* have broken.
struct PenFileTransactionDryRunTests {
    // MARK: - Helpers

    private static let fixtureName = "layout-vertical.pen"

    /// The id of a rectangle in `layout-vertical.pen`, used as the edit target.
    private static let targetNodeID = "jSUCH"

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureLoadError.notFound(name)
        }
        return url
    }

    /// Runs `body` against a private copy of a fixture, with its own activity log.
    private func withCopiedFixture<T>(
        _ name: String = fixtureName,
        _ body: (URL, ActivityLog) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFileTransactionDryRunTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: fixtureURL(name), to: url)
        let log = ActivityLog(
            home: directory.appendingPathComponent("log", isDirectory: true),
            origin: .directory
        )
        return try await body(url, log)
    }

    /// Renames the target node by appending `suffix` to its current name.
    private static func rename(
        _ document: EditableDocument, through recorder: ActivityRecorder, suffix: String
    ) throws -> String {
        var node = try #require(document.nodes[targetNodeID])
        let renamed = (node.common.name ?? "") + suffix
        node.common.name = renamed
        try recorder.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: targetNodeID, common: node.common)))
        return renamed
    }

    // MARK: - What a dry run leaves behind

    @Test("A dry run leaves the file's bytes exactly as they were")
    func dryRunLeavesTheBytesAlone() async throws {
        try await withCopiedFixture { url, log in
            let before = try Data(contentsOf: url)

            let outcome = try await PenFileTransaction.run(
                at: url, identity: "ana", log: log, effect: .dryRun
            ) { document, recorder in
                try Self.rename(document, through: recorder, suffix: "-previewed")
            }

            #expect(outcome.value.hasSuffix("-previewed"))
            #expect(outcome.didWrite == false)
            try #expect(Data(contentsOf: url) == before)
        }
    }

    @Test("A dry run appends nothing to the activity log, and creates no log at all")
    func dryRunWritesNoLog() async throws {
        try await withCopiedFixture { url, log in
            _ = try await PenFileTransaction.run(
                at: url, identity: "ana", log: log, effect: .dryRun
            ) { document, recorder in
                try Self.rename(document, through: recorder, suffix: "-previewed")
            }

            #expect(!FileManager.default.fileExists(atPath: log.fileURL.path))
        }
    }

    @Test("A dry run that would have written reports itself as previewed, not as unchanged")
    func dryRunReportsWhatItWouldHaveDone() async throws {
        try await withCopiedFixture { url, log in
            let outcome = try await PenFileTransaction.run(
                at: url, identity: "ana", log: log, effect: .dryRun
            ) { document, recorder in
                try Self.rename(document, through: recorder, suffix: "-previewed")
            }

            #expect(outcome.commit == .previewed)
            #expect(outcome.wouldWrite)
            #expect(outcome.didWrite == false)
        }
    }

    @Test("A dry run whose body changes nothing is unchanged, not previewed")
    func dryRunOfANoOpIsUnchanged() async throws {
        try await withCopiedFixture { url, log in
            let outcome = try await PenFileTransaction.run(
                at: url, identity: "ana", log: log, effect: .dryRun
            ) { document, _ in
                document.nodes.count
            }

            #expect(outcome.commit == .unchanged)
            #expect(outcome.wouldWrite == false)
        }
    }

    @Test("Committing is still the default, and still writes")
    func commitIsTheDefault() async throws {
        try await withCopiedFixture { url, log in
            let before = try Data(contentsOf: url)

            let outcome = try await PenFileTransaction.run(at: url, identity: "ana", log: log) { document, recorder in
                try Self.rename(document, through: recorder, suffix: "-written")
            }

            #expect(outcome.commit == .wrote)
            #expect(outcome.didWrite)
            try #expect(Data(contentsOf: url) != before)
            #expect(FileManager.default.fileExists(atPath: log.fileURL.path))
        }
    }

    // MARK: - The lint preview

    @Test("A preview reports only the findings the edit introduced")
    func previewReportsOnlyIntroducedFindings() async throws {
        try await withCopiedFixture("batch.pen") { url, log in
            let outcome = try await PenFileTransaction.run(
                at: url, identity: "ana", log: log, effect: .dryRun
            ) { document, recorder in
                let preview = try LintPreview(of: document)
                try recorder.apply(.setProperties(EditOperation.SetProperties(
                    nodeID: "Cd101", properties: ["kind.width": .int(900)]
                )))
                return try preview.introduced(in: document)
            }

            let introduced = outcome.value
            // The fixture already trips `text-without-fill` twice and `clipped` once;
            // none of those is this edit's doing, so none of them is reported.
            #expect(introduced.allSatisfy { $0.check == .clipped })
            #expect(introduced.contains { $0.nodeID == "Cd101" })
            #expect(!introduced.contains { $0.nodeID == "Ttl01" })
            #expect(!introduced.contains { $0.nodeID == "Crd01" })
        }
    }

    @Test("A preview of an edit that breaks nothing reports nothing")
    func previewOfACleanEditIsEmpty() async throws {
        try await withCopiedFixture("batch.pen") { url, log in
            let outcome = try await PenFileTransaction.run(
                at: url, identity: "ana", log: log, effect: .dryRun
            ) { document, recorder in
                let preview = try LintPreview(of: document)
                try recorder.apply(.setProperties(EditOperation.SetProperties(
                    nodeID: "Cd101", properties: ["common.name": .string("Renamed")]
                )))
                return try preview.introduced(in: document)
            }

            #expect(outcome.value.isEmpty)
        }
    }
}
