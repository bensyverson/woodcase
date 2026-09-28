//
//  LogLineageTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins the one comparison undo and every write transaction share: does the activity
/// log explain the bytes this file holds?
struct LogLineageTests {
    // MARK: - Helpers

    private static let file = URL(fileURLWithPath: "/tmp/lineage.pen")

    /// A time this suite can name in a sentence: 10:32 local, whatever the zone.
    private static var tenThirtyTwo: Date {
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: .current,
            year: 2026, month: 9, day: 7, hour: 10, minute: 32
        )
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    /// One recorded event, with only the fields the comparison reads.
    private static func event(
        identity: String = "ana",
        revision: String,
        time: Date = LogLineageTests.tenThirtyTwo
    ) -> ActivityEvent {
        ActivityEvent(
            time: time,
            identity: identity,
            file: file,
            op: .set,
            nodes: ["Ttl01"],
            paths: ["Canvas/Title"],
            revision: revision,
            batch: "B1"
        )
    }

    // MARK: - The three answers

    @Test("A file with nothing recorded is unlogged, not diverged")
    func noHistoryIsNotADivergence() {
        let lineage = LogLineage(documentRevision: "9c1b04e6f0011223", newest: nil)
        #expect(lineage == .unlogged)
        #expect(!lineage.isDiverged)
        #expect(lineage.note(naming: Self.file) == nil)
        #expect(lineage.external(naming: Self.file) == nil)
    }

    @Test("The newest event's own revision means woodcase wrote the file last")
    func matchingRevisionIsCurrent() {
        let newest = Self.event(revision: "9c1b04e6f0011223")
        let lineage = LogLineage(documentRevision: "9c1b04e6f0011223", newest: newest)
        #expect(lineage == .current(newest))
        #expect(!lineage.isDiverged)
        #expect(lineage.newest == newest)
        #expect(lineage.note(naming: Self.file) == nil)
    }

    @Test("A revision the log never produced means somebody else wrote the file")
    func differentRevisionIsDiverged() {
        let newest = Self.event(revision: "9c1b04e6f0011223")
        let lineage = LogLineage(documentRevision: "0123456789abcdef", newest: newest)
        #expect(lineage == .diverged(since: newest, found: "0123456789abcdef"))
        #expect(lineage.isDiverged)
        #expect(lineage.newest == newest)
    }

    @Test("explains is the comparison itself, and undo asks it of every candidate")
    func explainsComparesTheRevision() {
        let candidate = Self.event(revision: "9c1b04e6f0011223")
        #expect(LogLineage.explains(candidate, at: "9c1b04e6f0011223"))
        #expect(!LogLineage.explains(candidate, at: "0123456789abcdef"))
    }

    // MARK: - The sentence

    @Test("The note names the file, the last revision the log knows, the writer and the time")
    func noteNamesWhatTheReaderNeeds() throws {
        let lineage = LogLineage(
            documentRevision: "0123456789abcdef", newest: Self.event(revision: "9c1b04e6f0011223")
        )
        let note = try #require(lineage.note(naming: Self.file))
        #expect(note == "/tmp/lineage.pen was rewritten outside woodcase since rev 9c1b04e6 "
            + "(ana, \(ActivityEvent.clockTime(Self.tenThirtyTwo))); the log has no record of that change")
        #expect(note.contains("10:32"))
    }

    @Test("A write nobody claimed is named in the note as unattributed, not as an empty gap")
    func noteNamesTheUnattributedWriter() throws {
        let unattributed = Self.event(identity: ActivityEvent.unattributed, revision: "aaaabbbbccccdddd")
        let lineage = LogLineage(documentRevision: "0123456789abcdef", newest: unattributed)
        let note = try #require(lineage.note(naming: Self.file))
        #expect(note.contains("(unattributed, "))
    }

    // MARK: - The row that closes the hole

    @Test("The external row carries the revision the file was found at, and claims nothing else")
    func externalRowRecordsWhatWasFound() throws {
        let lineage = LogLineage(
            documentRevision: "0123456789abcdef", newest: Self.event(revision: "9c1b04e6f0011223")
        )
        let row = try #require(lineage.external(naming: Self.file, at: Self.tenThirtyTwo))
        #expect(row.op == .external)
        #expect(row.revision == "0123456789abcdef")
        #expect(row.identity == ActivityEvent.unattributed)
        #expect(row.inverse.isEmpty)
        #expect(row.nodes.isEmpty)
        #expect(row.paths.isEmpty)
        #expect(row.batch == nil)
        #expect(row.file == ActivityEvent.canonicalPath(for: Self.file))
    }

    @Test("Recording the row restores the invariant: the next read is current again")
    func theRowClosesTheHole() throws {
        let lineage = LogLineage(
            documentRevision: "0123456789abcdef", newest: Self.event(revision: "9c1b04e6f0011223")
        )
        let row = try #require(lineage.external(naming: Self.file))
        #expect(LogLineage(documentRevision: "0123456789abcdef", newest: row) == .current(row))
    }

    // MARK: - The wire format carries the new kind

    @Test("external round-trips through the log's own JSON line")
    func externalRoundTrips() throws {
        let lineage = LogLineage(
            documentRevision: "0123456789abcdef", newest: Self.event(revision: "9c1b04e6f0011223")
        )
        let row = try #require(lineage.external(naming: Self.file, at: Self.tenThirtyTwo))
        let line = try row.jsonLine()
        #expect(String(decoding: line, as: UTF8.self).contains("\"op\":\"external\""))
        #expect(try ActivityEvent(line: line, using: JSONDecoder()) == row)
    }
}
