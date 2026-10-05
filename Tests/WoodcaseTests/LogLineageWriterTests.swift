//
//  LogLineageWriterTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``LogLineage/writer`` names who wrote the file, as the ``Author`` a file merge is
/// credited to, so an app never builds one by hand.
struct LogLineageWriterTests {
    private func row(_ identity: String, op: ActivityEvent.Kind = .set) -> ActivityEvent {
        ActivityEvent(
            time: Date(), identity: identity, file: URL(fileURLWithPath: "/tmp/x.pen"), op: op,
            nodes: [], paths: [], inverse: [], revision: "r", batch: "b"
        )
    }

    @Test("a current lineage's writer is the newest row's identity, on a replica of its own")
    func currentNamesWriter() throws {
        let writer = try #require(LogLineage.current(row("claude")).writer)
        #expect(writer.name == "claude")
        #expect(writer == LogLineage.current(row("claude")).writer)
        #expect(writer != LogLineage.current(row("ana")).writer)
    }

    @Test("a writer named like the app's author is still another replica")
    func sameNameOtherReplica() throws {
        let ben = Author(name: "ben", peerID: PeerID(rawValue: "peer-ben"))
        let writer = try #require(LogLineage.current(row("ben")).writer)
        #expect(writer.name == "ben")
        #expect(writer != ben)
    }

    @Test("a diverged, unlogged or external-row lineage names no writer")
    func unknownWriters() {
        #expect(LogLineage.unlogged.writer == nil)
        #expect(LogLineage.diverged(since: row("claude"), found: "f").writer == nil)
        #expect(LogLineage.current(row(ActivityEvent.unattributed, op: .external)).writer == nil)
    }
}
