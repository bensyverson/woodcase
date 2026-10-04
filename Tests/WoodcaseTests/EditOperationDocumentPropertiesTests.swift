//
//  EditOperationDocumentPropertiesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditOperation/setDocumentProperties(_:)``: the root's `fonts`, `version`,
/// `fileToken` and unmodeled `extras.<key>` are each settable, each with an inverse
/// that restores the document exactly, and the operation survives its own wire format.
@MainActor
struct EditOperationDocumentPropertiesTests {
    private let peerA = PeerID(rawValue: "aaa")

    // MARK: - Helpers

    private func document() throws -> PenDocument {
        try PenParser.parse(#"""
        {"version": "2.17", "fileToken": "tok-1", "rootFuture": {"a": 1},
         "fonts": [{"name": "Inter", "url": "./Inter.ttf"}],
         "children": [{"id": "Board", "type": "frame"}]}
        """#)
    }

    private func set(_ properties: [String: AnyCodable]) -> EditOperation {
        .setDocumentProperties(EditOperation.SetDocumentProperties(properties: properties))
    }

    /// Applies `op`, then its inverse, and checks the document is back where it was.
    ///
    /// - Returns: The document as `op` left it, for the caller's own checks.
    @discardableResult
    private func roundTrip(_ op: EditOperation, on editable: EditableDocument) throws -> PenDocument {
        let before = editable.materialize()
        let inverse = try editable.prepareInverse(of: op)
        try editable.apply(op)
        let after = editable.materialize()
        for step in inverse {
            try editable.apply(step)
        }
        #expect(editable.materialize() == before)
        return after
    }

    // MARK: - Each key, with its inverse

    @Test("fonts is replaced, and cleared, and each inverse restores the declarations")
    func setsFonts() throws {
        let editable = try EditableDocument(from: document())
        let replaced = try roundTrip(set(["fonts": [["name": "Plex", "url": "./Plex.ttf"]]]), on: editable)
        #expect(replaced.fonts?.map(\.name) == ["Plex"])

        let cleared = try roundTrip(set(["fonts": .null]), on: editable)
        #expect(cleared.fonts == nil)
    }

    @Test("version is set, and its inverse restores the old one")
    func setsVersion() throws {
        let editable = try EditableDocument(from: document())
        let after = try roundTrip(set(["version": "2.20"]), on: editable)
        #expect(after.version == "2.20")
    }

    @Test("fileToken is set and cleared, each with an inverse")
    func setsFileToken() throws {
        let editable = try EditableDocument(from: document())
        #expect(try roundTrip(set(["fileToken": "tok-2"]), on: editable).fileToken == "tok-2")
        #expect(try roundTrip(set(["fileToken": .null]), on: editable).fileToken == nil)
    }

    @Test("A root extra is added, changed and removed, each with an inverse")
    func setsRootExtras() throws {
        let editable = try EditableDocument(from: document())
        #expect(try roundTrip(set(["extras.added": true]), on: editable).extras["added"] == true)
        #expect(try roundTrip(set(["extras.rootFuture": 2]), on: editable).extras["rootFuture"] == 2)
        #expect(try roundTrip(set(["extras.rootFuture": .null]), on: editable).extras.isEmpty)
    }

    @Test("Several keys in one operation apply together and undo together")
    func setsSeveralKeys() throws {
        let editable = try EditableDocument(from: document())
        let after = try roundTrip(
            set(["version": "2.20", "fileToken": .null, "extras.added": 1, "fonts": .null]),
            on: editable
        )
        #expect(after.version == "2.20")
        #expect(after.fileToken == nil)
        #expect(after.fonts == nil)
        #expect(after.extras.values == ["rootFuture": ["a": 1], "added": 1])
    }

    @Test("The inverse names exactly the keys the operation wrote, with their prior values")
    func inverseIsPerKey() throws {
        let editable = try EditableDocument(from: document())
        let inverse = try editable.prepareInverse(of: set(["fileToken": "x", "extras.added": 1]))
        #expect(inverse == [set(["fileToken": "tok-1", "extras.added": .null])])
    }

    // MARK: - Refusals

    @Test("An unknown key, a claimed root key and a mistyped value are refused, changing nothing")
    func refusesBadKeysAndValues() throws {
        let editable = try EditableDocument(from: document())
        let before = editable.materialize()

        #expect(throws: EditingError.unknownDocumentProperty(key: "colour")) {
            try editable.apply(self.set(["colour": 1]))
        }
        #expect(throws: EditingError.unknownDocumentProperty(key: "extras.children")) {
            try editable.apply(self.set(["extras.children": []]))
        }
        #expect(throws: EditingError.unknownDocumentProperty(key: "extras.")) {
            try editable.apply(self.set(["extras.": 1]))
        }
        #expect(throws: EditingError.self) {
            try editable.apply(self.set(["version": 3, "fileToken": "ok"]))
        }
        #expect(throws: EditingError.self) {
            try editable.apply(self.set(["version": .null]))
        }
        #expect(throws: EditingError.self) {
            try editable.apply(self.set(["fonts": "Inter"]))
        }
        #expect(editable.materialize() == before)
    }

    // MARK: - Codable

    @Test("setDocumentProperties round-trips through its JSON encoding")
    func codableRoundTrip() throws {
        let op = set(["fonts": [["name": "Plex", "url": "./Plex.ttf"]], "version": "2.20", "extras.k": .null])
        let decoded = try JSONDecoder().decode(EditOperation.self, from: JSONEncoder().encode(op))
        #expect(decoded == op)
    }

    // MARK: - Bookkeeping

    @Test("An activity row reads it as a set that names no node")
    func activityKind() {
        let op = set(["version": "2.20"])
        #expect(ActivityEvent.Kind(op) == .set)
        #expect(ActivityEvent.nodeIDs(touchedBy: op).isEmpty)
    }

    // MARK: - CRDT

    @Test("In collaborative mode it is local-only: the flat store takes it and nothing replicates")
    func crdtIsLocalOnly() throws {
        let source = try document()
        let a = EditableDocument(from: source, peerID: peerA)

        let ops = try a.applyLocal(set(["version": "2.20", "extras.added": 1]))

        #expect(ops.isEmpty)
        #expect(a.version == "2.20")
        #expect(a.extras["added"] == 1)
    }

    @Test("In collaborative mode a refused document write still throws, and replicates nothing")
    func crdtRefusesBadWrite() throws {
        let a = try EditableDocument(from: document(), peerID: peerA)
        #expect(throws: EditingError.unknownDocumentProperty(key: "colour")) {
            _ = try a.applyLocal(self.set(["colour": 1]))
        }
        #expect(a.crdtDocument?.operationLog.operations.isEmpty == true)
    }
}
