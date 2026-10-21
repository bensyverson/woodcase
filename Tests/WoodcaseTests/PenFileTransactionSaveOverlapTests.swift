//
//  PenFileTransactionSaveOverlapTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Two saves of one snapshot that overlap — an app's debounced save begun while its
/// explicit save is still writing — carry the same, older synced revision. The second
/// finds the file holding exactly what it would write, which is no change by another
/// writer: it reports ``PenFileTransaction/SaveOutcome/unchanged`` rather than asking
/// the app to merge its own save back in.
struct PenFileTransactionSaveOverlapTests {
    private let ben = Author(name: "ben", peerID: PeerID(rawValue: "peer-ben"))

    private func openSession(_ url: URL) throws -> DocumentSession {
        try DocumentSession(document: PenParser.parse(contentsOf: url), author: ben, file: url, merger: .threeWay)
    }

    @Test("two overlapping saves of one snapshot write once and report no file change")
    func overlappingSavesWriteOnce() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let change = try session.submit(.local(LocalEdit(operations: [SaveFixture.rename("Mark")])))
        let snapshot = session.snapshot()

        async let first = PenFileTransaction.save(snapshot, changes: [change], to: url, log: fixture.log)
        async let second = PenFileTransaction.save(snapshot, changes: [change], to: url, log: fixture.log)
        let outcomes = try await [first, second]

        #expect(outcomes.count(where: { $0 == .wrote }) == 1)
        #expect(outcomes.count(where: { $0 == .unchanged }) == 1)
        #expect(try fixture.events(for: url).map(\.op) == [.set])
    }

    @Test("a stale snapshot's save finds the earlier save of it and is unchanged, logging nothing")
    func staleSnapshotOfSavedDocumentIsUnchanged() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let change = try session.submit(.local(LocalEdit(operations: [SaveFixture.rename("Mark")])))
        let snapshot = session.snapshot()
        try await PenFileTransaction.save(snapshot, changes: [change], to: url, log: fixture.log)
        let saved = try Data(contentsOf: url)

        let outcome = try await PenFileTransaction.save(snapshot, changes: [change], to: url, log: fixture.log)

        #expect(outcome == .unchanged)
        #expect(try Data(contentsOf: url) == saved)
        #expect(try fixture.events(for: url).count == 1)
    }

    @Test("a stale snapshot is unchanged when the file holds its document in other bytes")
    func staleSnapshotMatchesByContentNotBytes() async throws {
        let fixture = try SaveFixture()
        defer { fixture.remove() }
        let url = try fixture.copy()
        let session = try openSession(url)
        let change = try session.submit(.local(LocalEdit(operations: [SaveFixture.rename("Mark")])))
        let snapshot = session.snapshot()
        // Another writer leaves exactly the snapshot's document, compact rather than pretty.
        let compact = try JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(with: PenParser.encodeForFile(snapshot.document))
        )
        try compact.write(to: url)

        let outcome = try await PenFileTransaction.save(snapshot, changes: [change], to: url, log: fixture.log)

        #expect(outcome == .unchanged)
        #expect(try Data(contentsOf: url) == compact)
    }
}
