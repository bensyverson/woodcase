//
//  EditOperationNormalizedTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `normalized(in:)` rewrites whole-struct property writes as per-path patches.
struct EditOperationNormalizedTests {
    @Test("updateCommon becomes setProperties of only the changed paths")
    func updateCommonNormalizes() {
        let document = SessionTestDocuments.make()
        var common = PenNodeCommon(name: "Renamed")
        common.opacity = .literal(0.5)
        let normalized = EditOperation.updateCommon(EditOperation.UpdateCommon(nodeID: "c1", common: common))
            .normalized(in: document)
        #expect(normalized == .setProperties(EditOperation.SetProperties(
            nodeID: "c1", properties: ["common.name": "Renamed", "common.opacity": 0.5]
        )))
    }

    @Test("a same-case updateKind becomes setProperties of only the changed paths")
    func sameCaseUpdateKindNormalizes() {
        let document = SessionTestDocuments.make()
        let normalized = EditOperation.updateKind(EditOperation.UpdateKind(
            nodeID: "c1",
            kind: .rectangle(PenNode.RectangleData(width: .fixed(50), height: .fixed(40), cornerRadius: .uniform(.literal(4))))
        )).normalized(in: document)
        #expect(normalized == .setProperties(EditOperation.SetProperties(
            nodeID: "c1", properties: ["kind.width": 50, "kind.cornerRadius": 4]
        )))
    }

    @Test("an unchanged updateCommon becomes an empty patch")
    func unchangedIsEmpty() throws {
        let document = SessionTestDocuments.make()
        let common = try #require(document.nodes["c1"]).common
        let normalized = EditOperation.updateCommon(EditOperation.UpdateCommon(nodeID: "c1", common: common))
            .normalized(in: document)
        #expect(normalized == .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: [:])))
    }

    @Test("a change of node type stays a whole updateKind")
    func kindCaseChangeStays() {
        let document = SessionTestDocuments.make()
        let operation = EditOperation.updateKind(EditOperation.UpdateKind(
            nodeID: "c1", kind: .text(PenNode.TextData(content: .literal("hi")))
        ))
        #expect(operation.normalized(in: document) == operation)
    }

    @Test("every other operation, and one on a missing node, is returned unchanged")
    func othersUnchanged() {
        let document = SessionTestDocuments.make()
        let operations: [EditOperation] = [
            .moveNode(EditOperation.MoveNode(nodeID: "c1", newParentID: "f2")),
            .setProperties(EditOperation.SetProperties(nodeID: "c1", properties: ["kind.width": 3])),
            .updateCommon(EditOperation.UpdateCommon(nodeID: "missing", common: PenNodeCommon(name: "x"))),
        ]
        for operation in operations {
            #expect(operation.normalized(in: document) == operation)
        }
    }

    @Test("the normalized op applies to the same document as the original")
    func appliesEqual() throws {
        var common = PenNodeCommon(name: "Renamed")
        common.x = .literal(12)
        let operations: [EditOperation] = [
            .updateCommon(EditOperation.UpdateCommon(nodeID: "c1", common: common)),
            .updateKind(EditOperation.UpdateKind(
                nodeID: "f1", kind: .frame(PenNode.FrameData(width: .fillContainer(fallback: nil), gap: .literal(8)))
            )),
            .updateKind(EditOperation.UpdateKind(
                nodeID: "ref1", kind: .ref(PenNode.RefData(ref: "comp1", rootOverrides: ["height": 30]))
            )),
        ]
        for operation in operations {
            let original = SessionTestDocuments.make()
            let normalizedDocument = SessionTestDocuments.make()
            let normalized = operation.normalized(in: normalizedDocument)
            guard case .setProperties = normalized else {
                Issue.record("\(operation) did not normalize")
                continue
            }
            try original.apply(operation)
            try normalizedDocument.apply(normalized)
            #expect(normalizedDocument.materialize() == original.materialize())
        }
    }

    @Test("across the fixtures, swapping one node's properties for another's normalizes and lands equal")
    func fixtureCorpus() throws {
        var pairs = 0
        for url in try Self.fixtureURLs() {
            guard let parsed = try? PenParser.parse(Data(contentsOf: url)) else { continue }
            let document = EditableDocument(from: parsed)
            let ids = document.nodes.keys.sorted()
            for (id, other) in zip(ids, ids.dropFirst() + ids.prefix(1)) {
                guard let node = document.nodes[id], let donor = document.nodes[other] else { continue }
                var operations: [EditOperation] = [
                    .updateCommon(EditOperation.UpdateCommon(nodeID: id, common: donor.common)),
                ]
                if node.kind.typeName == donor.kind.typeName {
                    operations.append(.updateKind(EditOperation.UpdateKind(nodeID: id, kind: donor.kind)))
                }
                for operation in operations {
                    pairs += 1
                    let normalized = operation.normalized(in: document)
                    guard case let .setProperties(patch) = normalized else {
                        Issue.record("\(url.lastPathComponent): \(id) ← \(other) did not normalize")
                        continue
                    }
                    var expected = node
                    switch operation {
                    case let .updateCommon(op): expected.common = op.common
                    case let .updateKind(op): expected.kind = op.kind.withEmptyChildren()
                    default: break
                    }
                    var patched = node
                    for (path, value) in patch.properties {
                        patched = try NodePropertyCodec.setting(value, at: path, on: patched)
                    }
                    patched.kind = patched.kind.withEmptyChildren()
                    #expect(patched == expected, "\(url.lastPathComponent): \(id) ← \(other)")
                }
            }
        }
        #expect(pairs > 1000, "only \(pairs) pairs exercised")
    }

    /// Every `.pen` file under the test bundle's `Fixtures`, sorted.
    private static func fixtureURLs() throws -> [URL] {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        let urls = (walk?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "pen" }
        return urls.sorted { $0.path < $1.path }
    }
}
