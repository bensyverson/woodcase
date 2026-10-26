//
//  CRDTSeedFingerprintTests.swift
//  WoodcaseTests
//

import CryptoKit
import Foundation
import Testing
@testable import Woodcase

/// A replica's seed fingerprint: the same for every replica seeded from an equal
/// document, whatever its peer id; different for another document; and carried through a
/// snapshot or state transfer to replicas that were never seeded themselves.
@MainActor
struct CRDTSeedFingerprintTests {
    private let peerA = PeerID(rawValue: "aaa")
    private let peerB = PeerID(rawValue: "bbb")
    private let peerC = PeerID(rawValue: "ccc")

    private func makeDoc(name: String = "Frame") -> PenDocument {
        let rect = PenNode(
            id: "r1",
            common: PenNodeCommon(name: "Rect"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100.5)))
        )
        let frame = PenNode(id: "f1", common: PenNodeCommon(name: name), kind: .frame(PenNode.FrameData(children: [rect])))
        return PenDocument(imports: ["kit": "kit.pen"], children: [frame])
    }

    private func rename(_ id: String, _ name: String) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: id, properties: ["common.name": .string(name)]))
    }

    // MARK: - Seeding

    @Test("replicas seeded from equal documents report the same fingerprint, whatever their peer ids")
    func equalSeedsMatch() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let b = EditableDocument(from: makeDoc(), peerID: peerB)
        let fingerprintA = try #require(a.seedFingerprint)
        #expect(fingerprintA == b.seedFingerprint)
    }

    @Test("a replica seeded from a different document reports a different fingerprint")
    func differentSeedsDiffer() throws {
        let a = EditableDocument(from: makeDoc(), peerID: peerA)
        let b = EditableDocument(from: makeDoc(name: "Other"), peerID: peerA)
        let fingerprintA = try #require(a.seedFingerprint)
        let fingerprintB = try #require(b.seedFingerprint)
        #expect(fingerprintA != fingerprintB)
    }

    @Test("the fingerprint is 32 bytes: a SHA-256 digest")
    func fingerprintIsThirtyTwoBytes() throws {
        let fingerprint = try #require(EditableDocument(from: makeDoc(), peerID: peerA).seedFingerprint)
        #expect(fingerprint.bytes.count == 32)
        #expect(SeedFingerprint.byteCount == 32)
    }

    @Test("a document that is not collaborative has no seed fingerprint")
    func soloDocumentHasNone() {
        #expect(EditableDocument(from: makeDoc()).seedFingerprint == nil)
    }

    @Test("the CRDT document reports the fingerprint the editable document exposes")
    func crdtDocumentCarriesIt() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)
        let crdt = try #require(editable.crdtDocument)
        #expect(crdt.seedFingerprint == editable.seedFingerprint)
    }

    @Test("local edits do not change the fingerprint: it is the seed's, not the current document's")
    func editsKeepTheSeedFingerprint() throws {
        let editable = EditableDocument(from: makeDoc(), peerID: peerA)
        let before = try #require(editable.seedFingerprint)
        _ = try editable.applyLocal(rename("f1", "Renamed"))
        #expect(editable.seedFingerprint == before)
    }

    @Test("a document's fingerprint does not depend on how its dictionaries were built")
    func dictionaryOrderDoesNotMatter() {
        var forward: [String: String] = [:]
        var backward = [String: String](minimumCapacity: 256)
        let aliases = (0 ..< 64).map { "alias\($0)" }
        for alias in aliases {
            forward[alias] = "\(alias).pen"
        }
        for alias in aliases.reversed() {
            backward[alias] = "\(alias).pen"
        }
        let a = SeedFingerprint(of: PenDocument(imports: forward, children: []))
        let b = SeedFingerprint(of: PenDocument(imports: backward, children: []))
        #expect(a.bytes.count == 32)
        #expect(a == b)
    }

    @Test("the canonical encoding sorts keys and writes numbers in their shortest form")
    func canonicalEncodingIsPinned() {
        let rect = PenNode(id: "r1", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(width: .fixed(0.1))))
        let document = PenDocument(version: "2.21", imports: ["b": "b/b.pen", "a": "a.pen"], children: [rect])
        let encoded = String(decoding: SeedFingerprint.canonicalEncoding(of: document), as: UTF8.self)
        #expect(encoded == #"{"children":[{"id":"r1","type":"rectangle","width":0.1}],"imports":{"a":"a.pen","b":"b/b.pen"},"version":"2.21"}"#)
    }

    @Test("the fingerprint is SHA-256 over a versioned prefix and the canonical encoding")
    func fingerprintIsPinned() {
        let document = PenDocument(version: "2.21", children: [])
        let expected = Data(SHA256.hash(data: Data("woodcase.crdt-seed.v1\n".utf8) + SeedFingerprint.canonicalEncoding(of: document)))
        #expect(SeedFingerprint(of: document).bytes == expected)
        // `printf 'woodcase.crdt-seed.v1\n{"children":[],"version":"2.21"}' | shasum -a 256`
        #expect(SeedFingerprint(of: document).bytes.map { String(format: "%02x", $0) }.joined()
            == "c3b6fbd385a60d0c5d16f1feeb83a0eee96d49b79efae13e80126ed73d8eed9c")
    }

    // MARK: - Snapshots and state transfer

    @Test("a replica restored from a snapshot reports the donor's fingerprint")
    func snapshotCarriesIt() throws {
        let donor = EditableDocument(from: makeDoc(), peerID: peerA)
        _ = try donor.applyLocal(rename("f1", "Edited"))
        let snapshot = try #require(donor.crdtDocument?.snapshot())
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CRDTSnapshot.self, from: data)
        let restored = try CRDTDocument(from: decoded, peerID: peerB)
        #expect(restored.seedFingerprint == donor.seedFingerprint)
    }

    @Test("a peer that joined by state transfer matches peers seeded from the session's document, and passes it on")
    func stateTransferCarriesIt() throws {
        let donor = EditableDocument(from: makeDoc(), peerID: peerA)
        _ = try donor.applyLocal(rename("f1", "Edited"))
        let transfer = try #require(donor.stateTransfer())
        let data = try JSONEncoder().encode(transfer)
        let joiner = try EditableDocument(joining: JSONDecoder().decode(CRDTStateTransfer.self, from: data), peerID: peerB)
        let seededLater = EditableDocument(from: makeDoc(), peerID: peerC)

        let donorFingerprint = try #require(donor.seedFingerprint)
        #expect(donorFingerprint.bytes.count == 32)
        #expect(joiner.seedFingerprint == donorFingerprint)
        #expect(joiner.seedFingerprint == seededLater.seedFingerprint)
        // The joiner's document is the donor's edited one, so seeding from it would
        // differ: the fingerprint is the session's seed, carried, not recomputed.
        #expect(SeedFingerprint(of: joiner.materialize()) != joiner.seedFingerprint)

        let second = try EditableDocument(joining: #require(joiner.stateTransfer()), peerID: peerC)
        #expect(second.seedFingerprint == donor.seedFingerprint)
    }

    @Test("a snapshot whose fingerprint is not 32 bytes does not decode")
    func malformedFingerprintIsRefused() throws {
        let snapshot = try #require(EditableDocument(from: makeDoc(), peerID: peerA).crdtDocument?.snapshot())
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        object["seedFingerprint"] = Data([1, 2, 3]).base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CRDTSnapshot.self, from: tampered)
        }
    }

    @Test("a fingerprint is made from 32 bytes and no other count")
    func bytesInitializerChecksLength() {
        #expect(SeedFingerprint(bytes: Data(repeating: 7, count: 32))?.bytes == Data(repeating: 7, count: 32))
        #expect(SeedFingerprint(bytes: Data(repeating: 7, count: 31)) == nil)
    }
}
