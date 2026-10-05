//
//  RandomEditGeneratorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``RandomEditGenerator``: a seed fixes every operation it draws.
@MainActor
struct RandomEditGeneratorTests {
    /// Hashes every operation three peers draw from the CRDT set, 75 each, applying the
    /// ones that apply, then one more draw from the shared generator.
    private static func crdtFingerprint(seed: UInt64) throws -> String {
        var generator = RandomEditGenerator(seed: seed)
        var hasher = FNV1aHasher()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let base = FuzzFixture.document()
        for peerIndex in 0 ..< 3 {
            let peer = EditableDocument(from: base, peerID: PeerID(rawValue: "p\(peerIndex)"))
            let label = String(Character(UnicodeScalar(65 + peerIndex)!))
            for index in 0 ..< 75 {
                guard let operation = generator.operation(for: peer, label: label, index: index) else {
                    hasher.combine("nil")
                    continue
                }
                try hasher.combine(encoder.encode(operation))
                _ = try? peer.applyLocal(operation)
            }
        }
        hasher.combine(String(generator.rng.next()))
        return hasher.hexString
    }

    /// The fingerprints were recorded from the generator while it was still private to
    /// `CRDTFuzzTests`, so the extraction kept every CRDT seed's run.
    @Test("The CRDT set draws the same operations it drew before it was extracted", arguments: [
        (UInt64(1), "e5bfa9dff426ec3f"),
        (UInt64(42), "45b3ba04e61ca948"),
        (UInt64(9999), "cab4f5d3a3a2a178"),
        (UInt64(2026), "608400122022be15"),
    ])
    func crdtSetIsPinned(seed: UInt64, fingerprint: String) throws {
        #expect(try Self.crdtFingerprint(seed: seed) == fingerprint)
    }

    /// What an applied operation exercises, as a short label.
    private static func feature(of operation: EditOperation, in document: EditableDocument) -> String {
        switch operation {
        case let .insertNode(insert):
            if case .ref = insert.node.kind { return "insert instance" }
            if case let .frame(frame) = insert.node.kind, frame.children == [] { return "insert declared-empty frame" }
            return insert.index == nil ? "insert" : "insert at index"
        case let .deleteNode(delete):
            let subtree = Set(document.descendantIDs(of: delete.nodeID))
            let stranded = document.instanceIDs(ofComponent: delete.nodeID).contains { !subtree.contains($0) }
            return stranded ? "delete component, instances \(delete.instances.rawValue)" : "delete"
        case let .moveNode(move): return move.index == nil ? "move" : "move to index"
        case let .updateKind(update):
            if !update.kind.canHaveChildren { return "retype to leaf" }
            return update.emptyChildren.map { "retype to container, children \($0.rawValue)" } ?? "retype to container"
        case let .setProperties(set):
            return set.properties.keys.contains { $0.hasPrefix("extras.") } ? "node extra" : "set properties"
        case let .setDocumentProperties(set):
            return set.properties.keys.contains { ["variables", "imports", "themes"].contains($0) } ? "declare table" : "root property"
        case .overrideDescendant: return "override descendant"
        case .overrideRoot: return "override root"
        case .detachRef: return "detach"
        case .addVariable, .updateVariable, .removeVariable: return "variable"
        case .addImport, .updateImport, .removeImport: return "import"
        case .addThemeAxis, .updateThemeAxis, .removeThemeAxis: return "theme axis"
        default: return "other"
        }
    }

    @Test("The merge set applies every kind of edit a merge must reproduce, across the everyday seeds")
    func mergeSetCoversItsVocabulary() throws {
        var seen: Set<String> = []
        for seed in DocumentMergeFuzzTests.seeds {
            var generator = RandomEditGenerator(seed: seed)
            let document = try FuzzFixture.mergeDocument()
            for index in 0 ..< DocumentMergeFuzzTests.operationsPerSide * 2 {
                guard let operation = generator.mergeOperation(for: document, label: "S", index: index) else { continue }
                let label = Self.feature(of: operation, in: document)
                if (try? document.apply(operation)) != nil { seen.insert(label) }
            }
        }
        let expected: Set = [
            "insert", "insert at index", "insert instance", "insert declared-empty frame", "delete", "delete component, instances detach",
            "move", "move to index", "retype to leaf", "retype to container", "retype to container, children declared",
            "retype to container, children absent", "set properties", "node extra", "declare table", "root property",
            "override descendant", "override root", "detach", "variable", "import", "theme axis",
        ]
        #expect(expected.subtracting(seen).isEmpty, "never applied: \(expected.subtracting(seen).sorted())")
    }
}
