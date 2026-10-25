//
//  RemoteReconcileFuzzTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A remote batch settled over what it wrote ends exactly where the whole-document pass
/// would, and says so exactly.
///
/// Two peers edit their own replicas of the fuzz fixture concurrently while a receiver
/// edits its own; their batches reach the receiver in a random interleaving. After each
/// batch the receiver is checked against three oracles that read the whole document:
///
/// - **placement** — the whole-document ``EditableDocument/reconcileChildrenWithParents()``
///   leaves every parent link, children list and the root order as the scoped pass did;
/// - **invalidation** — the batch's ``ChangeInvalidation/RemoteProbe`` reports what a
///   comparison of the document's whole tables before and after reports;
/// - **caches** — every revision and every instance's expansion equals what a document
///   built from scratch computes.
@MainActor
struct RemoteReconcileFuzzTests {
    /// The document's tables, as the whole-document comparison reads them.
    private struct Tables {
        let nodes: [String: PenNode]
        let parents: [String: String]
        let children: [String: [String]]
        let rootOrder: [String]
        let declared: Set<DocumentChangeKey.Table>

        init(_ document: EditableDocument) {
            nodes = document.nodes
            parents = document.parents
            children = document.children
            rootOrder = document.rootOrder
            declared = ChangeInvalidation.Probe.declaredTables(of: document)
        }
    }

    /// The invalidation a comparison of the whole tables gives — the rule the scoped
    /// probe must reproduce.
    private func wholeDocumentInvalidation(
        before: Tables,
        mutations: [DocumentMutation],
        after document: EditableDocument
    ) -> ChangeInvalidation {
        var result = ChangeInvalidation()
        var written = Set<String>()
        for mutation in mutations {
            switch mutation {
            case let .setNode(node): written.insert(node.id)
            case let .removeNode(nodeID): written.insert(nodeID)
            case .setChildren, .setParent, .removeParent: break
            case let .setVariable(name, _), let .removeVariable(name):
                result.formUnion(ChangeInvalidation(category: .structural, documentLevel: [.variable(name)], full: true))
            case let .setImport(alias, _), let .removeImport(alias):
                result.formUnion(ChangeInvalidation(category: .structural, documentLevel: [.importAlias(alias)], full: true))
            case let .setThemeAxis(name, _), let .removeThemeAxis(name):
                result.formUnion(ChangeInvalidation(category: .structural, documentLevel: [.themeAxis(name)], full: true))
            case let .setDocumentProperty(key, _):
                result.formUnion(ChangeInvalidation.Probe.documentProperties([key]))
            }
        }
        for nodeID in written {
            if let old = before.nodes[nodeID], let new = document.nodes[nodeID] {
                let category = ChangeCategory.merge(
                    ChangeCategory.categorize(oldCommon: old.common, newCommon: new.common),
                    ChangeCategory.categorize(oldKind: old.kind, newKind: new.kind)
                )
                result.formUnion(ChangeInvalidation(nodes: [nodeID], category: category))
            } else {
                result.formUnion(ChangeInvalidation(nodes: [nodeID], category: .structural, structural: true))
            }
        }
        var placed = Set<String>()
        for nodeID in Set(before.parents.keys).union(document.parents.keys) where before.parents[nodeID] != document.parents[nodeID] {
            placed.insert(nodeID)
            placed.formUnion([before.parents[nodeID], document.parents[nodeID]].compactMap(\.self))
        }
        for parentID in Set(before.children.keys).union(document.children.keys) where before.children[parentID] != document.children[parentID] {
            placed.insert(parentID)
        }
        let rootChanged = before.rootOrder != document.rootOrder
        if !placed.isEmpty || rootChanged {
            result.formUnion(ChangeInvalidation(
                nodes: placed, category: .structural, documentLevel: rootChanged ? [.rootOrder] : [], structural: true
            ))
        }
        let tables = ChangeInvalidation.Probe.declaredTables(of: document).symmetricDifference(before.declared)
        result.documentLevel.formUnion(tables.map(DocumentChangeKey.declaredTable))
        return result
    }

    /// Every node's revision, filling the cache.
    @discardableResult
    private func revisions(of document: EditableDocument) -> [String: String] {
        document.nodes.keys.reduce(into: [:]) { $0[$1] = document.revision(of: $1) }
    }

    /// Every instance's expansion, filling the cache.
    @discardableResult
    private func expansions(of document: EditableDocument) -> [String: ExpandedRef] {
        document.nodes.reduce(into: [:]) { result, entry in
            if case .ref = entry.value.kind { result[entry.key] = try? document.expandRef(nodeID: entry.key) }
        }
    }

    /// Applies a batch the way a session does, returning the scoped invalidation and the
    /// mutations, or `nil` when nothing landed.
    private func apply(_ batch: [CRDTOperation], to document: EditableDocument) -> (ChangeInvalidation, [DocumentMutation])? {
        var probe = ChangeInvalidation.RemoteProbe(document)
        var mutations: [DocumentMutation] = []
        for operation in batch {
            mutations += (try? document.applyRemoteMutations(operation, journal: &probe.journal)) ?? []
        }
        guard !mutations.isEmpty else { return nil }
        document.reconcileChildrenWithParents(after: &probe.journal)
        return (probe.invalidation(of: mutations, after: document), mutations)
    }

    /// One scenario: two remote peers and a receiver that may edit too.
    ///
    /// A receiver that edits can leave its store disagreeing with the CRDT, and then its
    /// next batch reconciles whole; one that only receives settles every batch scoped.
    private func run(seed: UInt64, operations: Int, receiverEdits: Bool) {
        var generator = RandomEditGenerator(seed: seed)
        let base = FuzzFixture.document()
        let receiver = EditableDocument(from: base, peerID: PeerID(rawValue: "fuzz_receiver"))
        let peers = ["A", "B"].map { EditableDocument(from: base, peerID: PeerID(rawValue: "fuzz_peer_\($0)")) }
        var queues: [[[CRDTOperation]]] = [[], []]
        for (index, peer) in peers.enumerated() {
            for step in 0 ..< operations {
                guard let operation = generator.operation(for: peer, label: index == 0 ? "A" : "B", index: step),
                      let batch = try? peer.applyLocal(operation), !batch.isEmpty
                else { continue }
                queues[index].append(batch)
            }
        }

        var cursors = [0, 0]
        var step = 0
        while let peer = (0 ..< 2).filter({ cursors[$0] < queues[$0].count }).randomElement(using: &generator.rng) {
            step += 1
            if receiverEdits, Int.random(in: 0 ..< 4, using: &generator.rng) == 0,
               let local = generator.operation(for: receiver, label: "R", index: step)
            {
                _ = try? receiver.applyLocal(local)
            }
            revisions(of: receiver)
            expansions(of: receiver)
            let before = Tables(receiver)
            let batch = queues[peer][cursors[peer]]
            cursors[peer] += 1
            guard let (invalidation, mutations) = apply(batch, to: receiver) else { continue }

            #expect(
                invalidation == wholeDocumentInvalidation(before: before, mutations: mutations, after: receiver),
                "seed \(seed) step \(step): the scoped invalidation differs"
            )
            let scratch = EditableDocument(from: receiver.materialize())
            #expect(revisions(of: receiver) == revisions(of: scratch), "seed \(seed) step \(step): a revision is stale")
            #expect(expansions(of: receiver) == expansions(of: scratch), "seed \(seed) step \(step): an expansion is stale")

            let settled = (receiver.parents, receiver.children, receiver.rootOrder)
            receiver.reconcileChildrenWithParents()
            #expect(receiver.parents == settled.0, "seed \(seed) step \(step): parents differ from the whole pass")
            #expect(receiver.children == settled.1, "seed \(seed) step \(step): children differ from the whole pass")
            #expect(receiver.rootOrder == settled.2, "seed \(seed) step \(step): root order differs from the whole pass")
        }
    }

    @Test("a scoped remote batch agrees with the whole-document oracles", arguments: [1, 42, 777, 1337, 2026, 9999, 55555, 271_828] as [UInt64])
    func agreesWithWholeDocument(seed: UInt64) {
        run(seed: seed, operations: 80, receiverEdits: true)
    }

    @Test("a receiver that only receives settles every batch scoped and agrees", arguments: [5, 99, 4242, 80808] as [UInt64])
    func receiverOnlyAgrees(seed: UInt64) {
        run(seed: seed, operations: 80, receiverEdits: false)
    }
}
