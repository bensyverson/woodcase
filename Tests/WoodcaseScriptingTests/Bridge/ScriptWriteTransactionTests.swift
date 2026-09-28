//
//  ScriptWriteTransactionTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// A script's writes inside a real ``Woodcase/PenFileTransaction``, and the same writes
/// with no transaction at all.
///
/// Two claims live here. One: a run that ends in an uncaught error leaves the file and
/// the activity log byte for byte what they were — the transaction discards the events
/// the recorder accumulated, so "nothing was written" is a property of the shape rather
/// than of anyone remembering to undo. Two: the recorder is optional, so a library caller
/// with an in-memory document and no log gets exactly the same reports back.
@Suite("a script's writes and the file transaction")
struct ScriptWriteTransactionTests {
    /// A copy of a fixture and a log of its own, deleted with the handle.
    private final class Workspace {
        /// Copies a fixture into a directory of its own.
        ///
        /// - Parameter fixture: The file name inside `Tests/WoodcaseTests/Fixtures`.
        /// - Throws: Whatever `FileManager` throws.
        init(fixture: String) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("woodcase-script-tx-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            file = root.appendingPathComponent(fixture)
            try FileManager.default.copyItem(at: ScriptFixture.url(fixture), to: file)
            log = ActivityLog(home: root.appendingPathComponent("home", isDirectory: true))
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// The directory everything lives in.
        let root: URL

        /// The .pen file under test.
        let file: URL

        /// A log nobody else writes to.
        let log: ActivityLog

        /// The .pen file's bytes right now.
        var bytes: Data {
            (try? Data(contentsOf: file)) ?? Data()
        }

        /// Every event the log holds.
        ///
        /// - Returns: The events, in log order, empty when nothing has been appended.
        /// - Throws: Whatever the reader throws.
        func events() throws -> [ActivityEvent] {
            guard FileManager.default.fileExists(atPath: log.fileURL.path) else { return [] }
            return try ActivityReader(log: log).read().events
        }
    }

    /// A failure raised by a test's transaction body when the script did not finish.
    private struct ScriptDidNotFinish: Error {
        /// The refusal the script ended with.
        let message: String
    }

    /// The script both halves of the no-recorder test run.
    ///
    /// Three verbs and not one of them creates a node: ids are generated, so two runs of
    /// an `add` cannot answer with the same report and the comparison would be about the
    /// id generator rather than about the recorder. What a creating write answers with no
    /// recorder is `ScriptWriteTests`'s question, and it asks it without one.
    private static let mixedWrites = """
    [doc.set('Ttl01', { 'kind.content': 'Hello' }),
     doc.mv('Cd101', 'Brd01'),
     doc.rm('Cd201')];
    """

    // MARK: - Rolling back

    @Test("an uncaught error after several writes leaves the file and the log untouched")
    func anUncaughtErrorWritesNothing() async throws {
        let workspace = try Workspace(fixture: "batch.pen")
        let before = workspace.bytes
        var commit: ScriptRun.Commit?

        await #expect(throws: ScriptDidNotFinish.self) {
            try await PenFileTransaction.run(
                at: workspace.file, identity: "ana", log: workspace.log
            ) { document, recorder in
                let run = ScriptHost.run(
                    [.text(
                        """
                        doc.set('Ttl01', { 'kind.content': 'One' });
                        doc.set('Cd101', { 'kind.width': 120 });
                        doc.set('Nope', { 'kind.width': 1 });
                        """,
                        name: "<argv>"
                    )],
                    over: document,
                    recorder: recorder
                )
                commit = run.commit
                if let error = run.error { throw ScriptDidNotFinish(message: error.message) }
            }
        }

        #expect(commit == .rolledBack)
        #expect(workspace.bytes == before, "the file should be byte for byte what it was")
        #expect(try workspace.events().isEmpty, "a body that throws appends nothing")
    }

    @Test("a run that finishes commits its writes and logs one event each")
    func aFinishedRunCommits() async throws {
        let workspace = try Workspace(fixture: "batch.pen")
        let before = workspace.bytes

        let outcome = try await PenFileTransaction.run(
            at: workspace.file, identity: "ana", log: workspace.log
        ) { document, recorder in
            ScriptHost.run(
                [.text(
                    """
                    doc.set('Ttl01', { 'kind.content': 'One' });
                    doc.set('Cd101', { 'kind.width': 120 });
                    """,
                    name: "<argv>"
                )],
                over: document,
                recorder: recorder
            )
        }
        #expect(outcome.value.error == nil)
        #expect(outcome.value.commit == .wrote)
        #expect(outcome.commit == .wrote)
        #expect(workspace.bytes != before)

        let events = try workspace.events()
        #expect(events.map(\.op.rawValue) == ["set", "set"])
        #expect(events.map(\.identity) == ["ana", "ana"])
        #expect(Set(events.compactMap(\.batch)).count == 1, "one script run is one transaction")
    }

    @Test("the events a script records are the ones the transaction appends")
    func theRecorderSeesTheWrites() async throws {
        let workspace = try Workspace(fixture: "batch.pen")
        let recorded = try await PenFileTransaction.run(
            at: workspace.file, identity: "ana", log: workspace.log
        ) { document, recorder in
            let run = ScriptHost.run(
                [.text("doc.set('Ttl01', { 'kind.content': 'One' });", name: "<argv>")],
                over: document,
                recorder: recorder
            )
            #expect(run.error == nil)
            return recorder.events
        }
        #expect(recorded.value.count == 1)
        #expect(recorded.value.first?.nodes == ["Ttl01"])
        #expect(try workspace.events() == recorded.value)
    }

    // MARK: - No recorder

    @Test("a run with no recorder and no log returns the reports a logged run returns")
    func aLibraryRunNeedsNoLog() async throws {
        let unlogged = try ScriptFixture.document("batch.pen")
        let plain = ScriptHost.run([.text(Self.mixedWrites, name: "<argv>")], over: unlogged)
        #expect(plain.error == nil, "\(plain.error?.message ?? "")")

        let workspace = try Workspace(fixture: "batch.pen")
        let logged = try await PenFileTransaction.run(
            at: workspace.file, identity: "ana", log: workspace.log
        ) { document, recorder in
            (
                run: ScriptHost.run(
                    [.text(Self.mixedWrites, name: "<argv>")], over: document, recorder: recorder
                ),
                materialized: document.materialize()
            )
        }

        #expect(logged.value.run.error == nil, "\(logged.value.run.error?.message ?? "")")
        #expect(plain.result == logged.value.run.result)
        #expect(plain.events == logged.value.run.events)
        #expect(plain.commit == logged.value.run.commit)
        #expect(unlogged.materialize() == logged.value.materialized)
        #expect(try workspace.events().map(\.op.rawValue) == ["set", "mv", "rm"])
    }
}
