//
//  CRDTDocumentPropertiesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The root's own properties — fonts, version, file token, table declarations and root
/// extras — replicate one last-writer-wins register per key.
@MainActor
struct CRDTDocumentPropertiesTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")

    private func makeDoc() -> PenDocument {
        let rect = PenNode(id: "r1", common: PenNodeCommon(name: "Rect"), kind: .rectangle(PenNode.RectangleData()))
        return PenDocument(children: [rect])
    }

    private func set(_ properties: [String: AnyCodable]) -> EditOperation {
        .setDocumentProperties(EditOperation.SetDocumentProperties(properties: properties))
    }

    private let brandFonts: AnyCodable = [["name": "Brand Sans", "url": "fonts/BrandSans.ttf"]]

    @Test("fonts, version, file token and root extras reach the other peer")
    func propertiesRoundTrip() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let b = EditableDocument(from: makeDoc(), peerID: peerB)

        let ops = try a.applyLocal(set([
            "fonts": brandFonts,
            "version": "2.99",
            "fileToken": "tok-1",
            "extras.brand": ["accent": "teal"],
        ]))
        #expect(ops.count == 4)
        b.applyRemote(ops)

        #expect(b.fonts == a.fonts)
        #expect(b.fonts?.first?.name == "Brand Sans")
        #expect(b.version == "2.99")
        #expect(b.fileToken == "tok-1")
        #expect(b.extras == a.extras)
        #expect(b.materialize() == a.materialize())
    }

    @Test("removing a property replicates as its removal")
    func removalReplicates() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let b = EditableDocument(from: makeDoc(), peerID: peerB)
        try b.applyRemote(a.applyLocal(set(["fileToken": "tok-1", "extras.brand": 1])))
        #expect(b.fileToken == "tok-1")
        #expect(b.extras["brand"] == 1)
        try b.applyRemote(a.applyLocal(set(["fileToken": .null, "extras.brand": .null])))

        #expect(b.fileToken == nil)
        #expect(b.extras["brand"] == nil)
    }

    @Test("a table declaration replicates")
    func tableDeclarationReplicates() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let b = EditableDocument(from: makeDoc(), peerID: peerB)
        try b.applyRemote(a.applyLocal(set(["themes": [:]])))
        #expect(b.themes == [:])
    }

    @Test("concurrent writes of one key converge on the later write, of different keys keep both")
    func concurrentWritesConverge() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let b = EditableDocument(from: makeDoc(), peerID: peerB)
        let fromA = try a.applyLocal(set(["version": "2.19", "extras.a": 1]))
        let fromB = try b.applyLocal(set(["version": "2.99", "extras.b": 2]))

        a.applyRemote(fromB)
        b.applyRemote(fromA)

        #expect(a.version == b.version)
        #expect(a.extras == b.extras)
        #expect(a.extras["a"] == 1)
        #expect(a.extras["b"] == 2)
    }

    @Test("a stale write of a key loses to the newer one it raced")
    func staleWriteLoses() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let b = EditableDocument(from: makeDoc(), peerID: peerB)
        let older = try a.applyLocal(set(["fileToken": "old"]))
        b.applyRemote(older)
        let newer = try b.applyLocal(set(["fileToken": "new"]))
        a.applyRemote(newer)

        let c = EditableDocument(from: makeDoc(), peerID: PeerID(rawValue: "ccc"))
        c.applyRemote(older + newer)
        #expect(a.fileToken == "new")
        #expect(c.fileToken == "new")
    }

    @Test("a snapshot carries the document properties' timestamps")
    func snapshotCarriesTimestamps() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        _ = try a.applyLocal(set(["version": "2.99"]))
        let snapshot = try #require(a.crdtDocument?.snapshot())
        #expect(snapshot.documentPropertyTimestamps["version"] != nil)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CRDTSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }
}
