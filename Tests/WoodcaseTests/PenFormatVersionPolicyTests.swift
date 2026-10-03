//
//  PenFormatVersionPolicyTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The version policy past the gate: a newer minor is written back as it was declared,
/// a different major is read-only, and a notice ranks below a warning.
///
/// ``PenVersionGateTests`` covers what the parser decides; this suite covers what every
/// *writer* does with that decision — ``PenFileTransaction`` and ``PenFileMigrator`` —
/// plus the ``PenFormatVersion/Relation`` fact they both ask.
struct PenFormatVersionPolicyTests {
    // MARK: - Helpers

    private static let rectangle = #"{"id":"rect1","type":"rectangle","name":"Box","width":50,"height":50}"#

    private static func document(version: String) -> Data {
        Data(#"{"children":[\#(rectangle)],"version":"\#(version)"}"#.utf8)
    }

    /// Writes a one-rectangle document declaring `version` into a fresh directory.
    private func withDocument<T>(
        version: String,
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFormatVersionPolicyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("design.pen")
        try Self.document(version: version).write(to: url)
        return try await body(url)
    }

    /// Renames the rectangle, so a transaction has something to write.
    private static func rename(_ document: EditableDocument) throws {
        var node = try #require(document.nodes["rect1"])
        node.common.name = "Renamed"
        try document.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: "rect1", common: node.common)))
    }

    private static func declaredVersion(at url: URL) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return object?["version"] as? String
    }

    // MARK: - Relation

    @Test("A version's relation to the model", arguments: [
        ("2.10", PenFormatVersion.Relation.older),
        ("2.16", .older),
        ("2.17", .current),
        ("2.19", .newerMinor),
        ("2.99", .newerMinor),
        ("3.0", .differentMajor),
        ("1.9", .differentMajor),
    ])
    func relationToTheModel(version: String, expected: PenFormatVersion.Relation) throws {
        let parsed = try #require(PenFormatVersion(version))
        #expect(parsed.relation(to: PenFormatVersion(major: 2, minor: 17)) == expected)
    }

    @Test("Only a different major is read-only")
    func onlyADifferentMajorIsReadOnly() {
        #expect(PenFormatVersion.Relation.differentMajor.isReadOnly)
        #expect(!PenFormatVersion.Relation.older.isReadOnly)
        #expect(!PenFormatVersion.Relation.current.isReadOnly)
        #expect(!PenFormatVersion.Relation.newerMinor.isReadOnly)
    }

    @Test("A document reports the relation of the version it declares")
    func documentReportsItsRelation() throws {
        #expect(try PenParser.parse(Self.document(version: "2.21")).formatRelation == .newerMinor)
        #expect(try PenParser.parse(Self.document(version: "3.0")).formatRelation == .differentMajor)
        #expect(PenDocument(children: []).formatRelation == .current)
    }

    // MARK: - Severity

    @Test("A notice ranks below a warning")
    func noticeRanksBelowAWarning() {
        #expect(!PenDiagnostic.Severity.notice.meetsOrExceeds(.warning))
        #expect(PenDiagnostic.Severity.warning.meetsOrExceeds(.notice))
        #expect(PenDiagnostic.Severity.notice.meetsOrExceeds(.notice))
        #expect(PenDiagnostic.Severity.allCases.first == .notice)
    }

    @Test("A notice describes itself as a notice")
    func noticeDescription() {
        let diagnostic = PenDiagnostic(severity: .notice, stage: .migration, message: "newer")
        #expect(diagnostic.description == "notice: [migration] newer")
    }

    @Test("A collector of notices has nothing at or above a warning")
    func noticesAreBelowTheWarningThreshold() {
        let collector = PenDiagnosticCollector()
        collector.notice("newer", stage: .migration)
        #expect(collector.hasIssues)
        #expect(!collector.contains(atLeast: .warning))
        collector.warn("worse", stage: .layout)
        #expect(collector.contains(atLeast: .warning))
    }

    // MARK: - Transactions

    @Test("An edit to a newer-minor file writes its declared version back")
    func transactionKeepsANewerMinor() async throws {
        try await withDocument(version: "2.21") { url in
            let outcome = try await PenFileTransaction.run(at: url) { document in
                try Self.rename(document)
            }
            #expect(outcome.didWrite)
            #expect(try Self.declaredVersion(at: url) == "2.21")
        }
    }

    @Test("An edit to an older 2.x file writes the model's version")
    func transactionUpgradesAnOlderMinor() async throws {
        try await withDocument(version: "2.14") { url in
            try await PenFileTransaction.run(at: url) { document in
                try Self.rename(document)
            }
            #expect(try Self.declaredVersion(at: url) == PenDocument.currentFormatVersion)
        }
    }

    @Test("A write transaction on a different major is refused before the body runs", arguments: [
        WriteEffect.commit, .dryRun,
    ])
    func transactionRefusesADifferentMajor(effect: WriteEffect) async throws {
        try await withDocument(version: "3.0") { url in
            let before = try Data(contentsOf: url)
            var ran = false
            let thrown = await #expect(throws: PenFormatWriteRefusal.self) {
                try await PenFileTransaction.run(at: url, effect: effect) { document in
                    ran = true
                    try Self.rename(document)
                }
            }
            #expect(!ran)
            #expect(thrown?.url == url)
            #expect(thrown?.declared == PenFormatVersion(major: 3, minor: 0))
            #expect(try Data(contentsOf: url) == before)
        }
    }

    @Test("A read transaction on a different major succeeds with the gate's warning")
    func readingADifferentMajorWorks() async throws {
        try await withDocument(version: "3.0") { url in
            let diagnostics = PenDiagnosticCollector()
            let outcome = try await PenFileTransaction.read(at: url, diagnostics: diagnostics) { document in
                document.nodes.count
            }
            #expect(outcome.value == 1)
            #expect(diagnostics.diagnostics.map(\.severity) == [.warning])
        }
    }

    @Test("The refusal names the file, both versions, and that reading still works")
    func refusalDescription() {
        let url = URL(fileURLWithPath: "/tmp/design.pen")
        let refusal = PenFormatWriteRefusal(url: url, declared: PenFormatVersion(major: 3, minor: 0))
        #expect(refusal.description.contains("/tmp/design.pen"))
        #expect(refusal.description.contains("3.0"))
        #expect(refusal.description.contains(PenDocument.currentFormatVersion))
        #expect(refusal.description.contains("read-only"))
    }

    // MARK: - Migration

    @Test("Migrating a newer minor leaves it at its own version, as already current")
    func migratorLeavesANewerMinor() throws {
        let outcome = try PenFileMigrator.migrate(Self.document(version: "2.21"))
        #expect(outcome.wasAlreadyCurrent)
        #expect(outcome.writtenVersion == "2.21")
        #expect(try PenParser.parse(outcome.data).version == "2.21")
    }

    @Test("Migrating an older file reports the version it writes")
    func migratorReportsTheWrittenVersion() throws {
        let outcome = try PenFileMigrator.migrate(Self.document(version: "2.9"))
        #expect(!outcome.wasAlreadyCurrent)
        #expect(outcome.writtenVersion == PenDocument.currentFormatVersion)
    }

    @Test("Migrating a different major is refused, naming the file")
    func migratorRefusesADifferentMajor() throws {
        let url = URL(fileURLWithPath: "/tmp/design.pen")
        let thrown = #expect(throws: PenFormatWriteRefusal.self) {
            try PenFileMigrator.migrate(Self.document(version: "3.0"), from: url)
        }
        #expect(thrown?.url == url)
    }
}
