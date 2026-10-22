//
//  RootOverrideNaturalKeyUndoTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A raw ``EditOperation/OverrideRoot`` naming a Woodcase-owned key writes the ref's own
/// `metadata.woodcase` (rule 6), so unsetting the key removes that entry and undoing the
/// write restores the entry as it stood (leaf QqB9Zj).
@MainActor
struct RootOverrideNaturalKeyUndoTests {
    private typealias Fixture = NaturalPathFixture

    /// How an undo is captured: the whole-struct inverse or the guarded per-key steps.
    enum Undo: CaseIterable {
        case whole, granular
    }

    private static let dash: AnyCodable = [6, 3]
    private static let earlier: AnyCodable = [2, 2]

    private func overrideRoot(_ properties: [String: AnyCodable], unset: [String] = []) -> EditOperation {
        .overrideRoot(EditOperation.OverrideRoot(refNodeID: "Ins01", properties: properties, unset: unset))
    }

    /// Applies an operation and returns what undoes it.
    private func applying(_ operation: EditOperation, to document: EditableDocument, undo: Undo) throws -> [EditOperation] {
        let inverse: [EditOperation] = switch undo {
        case .whole: try document.prepareInverse(of: operation)
        case .granular: try document.granularInverse(of: operation).map { $0.resolved(in: document) }
        }
        try document.apply(operation)
        return inverse
    }

    private func dash(in document: EditableDocument) -> AnyCodable? {
        document.node(id: "Ins01")?.common.metadata?[woodcase: .strokeDash]
    }

    @Test("A raw root unset of a natural key removes the ref's metadata entry")
    func unsetRemovesEntry() throws {
        let document = try Fixture.document()
        let original = document.node(id: "Ins01")
        try document.apply(overrideRoot(["kind.strokeDash": Self.dash]))
        try document.apply(overrideRoot([:], unset: ["kind.strokeDash"]))
        #expect(dash(in: document) == nil)
        #expect(document.node(id: "Ins01") == original)
        #expect(Fixture.expanded("Ins01/Bdg01", in: document)?.strokeDash?.lengths == [2, 2])
    }

    @Test("Undoing a raw root override of kind.strokeDash leaves no dash", arguments: Undo.allCases)
    func undoNewKey(undo: Undo) throws {
        let document = try Fixture.document()
        let original = document.node(id: "Ins01")
        let inverse = try applying(overrideRoot(["kind.strokeDash": Self.dash]), to: document, undo: undo)
        #expect(dash(in: document) == Self.dash)
        for operation in inverse {
            try document.apply(operation)
        }
        #expect(dash(in: document) == nil)
        #expect(document.node(id: "Ins01") == original)
    }

    @Test("Undoing a raw root override over an earlier value restores that value", arguments: Undo.allCases)
    func undoRestoresEarlier(undo: Undo) throws {
        let document = try Fixture.document()
        try document.apply(overrideRoot(["kind.strokeDash": Self.earlier]))
        let before = document.node(id: "Ins01")
        let inverse = try applying(overrideRoot(["strokeDash": Self.dash]), to: document, undo: undo)
        for operation in inverse {
            try document.apply(operation)
        }
        #expect(dash(in: document) == Self.earlier)
        #expect(document.node(id: "Ins01") == before)
    }

    @Test("Undoing a raw root unset of a natural key restores the value", arguments: Undo.allCases)
    func undoUnset(undo: Undo) throws {
        let document = try Fixture.document()
        try document.apply(overrideRoot(["common.locked": true]))
        let before = document.node(id: "Ins01")
        let inverse = try applying(overrideRoot([:], unset: ["common.locked"]), to: document, undo: undo)
        #expect(document.node(id: "Ins01")?.common.metadata?[woodcase: .locked] == nil)
        for operation in inverse {
            try document.apply(operation)
        }
        #expect(document.node(id: "Ins01") == before)
    }

    @Test("A raw root unset of a natural key replicates to the other replica")
    func unsetReplicates() throws {
        let document = try Fixture.document().materialize()
        let peerA = EditableDocument(from: document, peerID: PeerID(rawValue: "peerA"))
        let peerB = EditableDocument(from: document, peerID: PeerID(rawValue: "peerB"))
        try peerB.applyRemote(peerA.applyLocal(overrideRoot(["kind.strokeDash": Self.dash])))
        #expect(dash(in: peerB) == Self.dash)
        try peerB.applyRemote(peerA.applyLocal(overrideRoot([:], unset: ["kind.strokeDash"])))
        #expect(dash(in: peerB) == nil)
        #expect(peerB.node(id: "Ins01") == peerA.node(id: "Ins01"))
    }
}
