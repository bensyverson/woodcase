//
//  RandomEditGenerator.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Draws random ``EditOperation``s for a document, reproducibly from a seed.
///
/// Every draw comes from one ``SeededRandomNumberGenerator``, so a seed fixes the
/// whole sequence of operations — and of anything else the caller draws from ``rng``
/// between them. An operation is drawn against the document's current state but not
/// checked: it may be refused when applied (a cycle, a missing node), and fuzz loops
/// skip those.
///
/// Two vocabularies share the generator:
///
/// - ``operation(for:label:index:)`` — the CRDT fuzz set: inserts, deletes, moves,
///   common-property edits, variables, theme axes, imports, descendant overrides and
///   detaches, weighted toward contended structure. Its draws are pinned by
///   `RandomEditGeneratorTests`; change it and the CRDT seeds explore different runs.
/// - ``mergeOperation(for:label:index:scope:)`` — that set plus the operations a
///   three-way merge has to reproduce: retypes, declared-empty child lists and tables,
///   node and root extras, path-level property patches, refs and component deletes.
struct RandomEditGenerator {
    /// The source of every draw. Callers that interleave their own random choices with
    /// the generator's draw from here too, so one seed reproduces the whole run.
    var rng: SeededRandomNumberGenerator

    /// Creates a generator whose draws are fixed by `seed`.
    init(seed: UInt64) {
        rng = SeededRandomNumberGenerator(seed: seed)
    }

    /// Draws one operation from the CRDT fuzz set, or `nil` when the draw finds nothing
    /// to act on.
    ///
    /// - Parameters:
    ///   - doc: The document the operation is meant for.
    ///   - label: A short peer label, folded into the ids and names the operation mints.
    ///   - index: The operation's position in the peer's run, folded in the same way.
    mutating func operation(for doc: EditableDocument, label: String, index: Int) -> EditOperation? {
        let nodeIDs = Array(doc.allNodeIDs).sorted()
        guard !nodeIDs.isEmpty else { return nil }

        // Weight structural ops (insert/delete/move) more heavily since they
        // exercise the most complex convergence paths.
        // 0-11: existing ops, 12-13: overrideDescendant, 14: detachRef
        switch Int.random(in: 0 ..< 15, using: &rng) {
        case 0: return insertLeaf(in: doc, nodeIDs: nodeIDs, label: label, index: index)
        case 1: return insertContainer(in: doc, nodeIDs: nodeIDs, label: label, index: index)
        case 2, 3: return .deleteNode(EditOperation.DeleteNode(nodeID: nodeIDs.randomElement(using: &rng)!))
        case 4, 5: return move(in: doc, nodeIDs: nodeIDs)
        case 6: return updateCommon(in: doc, nodeIDs: nodeIDs, label: label, index: index)
        case 7: return variableEdit(in: doc)
        case 8: return themeAxisEdit(in: doc)
        case 9: return importEdit(in: doc)
        case 10, 11: return hotNodeEdit(in: doc, nodeIDs: nodeIDs, label: label, index: index)
        case 12, 13: return overrideDescendant(in: doc, nodeIDs: nodeIDs, label: label, index: index)
        case 14: return detachRef(in: doc, nodeIDs: nodeIDs)
        default: return nil
        }
    }

    // MARK: - Shared draws

    /// The ids among `nodeIDs` whose node can hold children.
    func containers(in doc: EditableDocument, among nodeIDs: [String]) -> [String] {
        nodeIDs.filter { doc.nodes[$0]?.kind.canHaveChildren == true }
    }

    /// The ids among `nodeIDs` whose node is a `ref`.
    func refs(in doc: EditableDocument, among nodeIDs: [String]) -> [String] {
        nodeIDs.filter { id in
            if case .ref = doc.nodes[id]?.kind { return true }
            return false
        }
    }

    /// Sometimes an insertion index into `parentID`'s list (or the top level), else `nil`.
    mutating func maybeIndex(in doc: EditableDocument, parentID: String?) -> Int? {
        guard Bool.random(using: &rng) else { return nil }
        let count = parentID.flatMap { doc.children[$0]?.count } ?? doc.rootOrder.count
        return count > 0 ? Int.random(in: 0 ... count, using: &rng) : 0
    }

    /// A random 6-digit hex color.
    mutating func hexColor() -> String {
        "#\(String(format: "%06X", Int.random(in: 0 ..< 0xFFFFFF, using: &rng)))"
    }
}
