//
//  SubtreeIDPlan+Detach.swift
//  Woodcase
//

import Foundation

/// The third front door: ids a detach derives rather than draws.
///
/// A detach replaces a `ref` with its expansion, and every node of that expansion
/// needs an id of its own. Drawing them at random made a detach unpredictable: an undo
/// prepared *before* the detach could not name the subtree it would have to remove,
/// and two copies of one document detached to different nodes. Deriving each
/// id from the ref and the expanded node it renames makes the answer a function of the
/// document, known before anything is written.
public extension SubtreeIDPlan {
    /// Plans the ids a detach gives an expanded instance.
    ///
    /// Each node's id is the 64-bit FNV-1a hash of `refID + "/" + expandedID` — prefixed
    /// with `replica + "/"` when a replica is named — written
    /// as base-62 digits in ``PenID``'s alphabet and truncated to five characters — the
    /// shape every generated id has. An id that `taken` already holds, or that an earlier
    /// node of this plan took, is re-salted: the hash input gains `"#1"`, then `"#2"`, and
    /// so on until the id is free. The same expansion, ref and `taken` always yield the
    /// same plan.
    ///
    /// **Collaborative editing names the replica.** A CRDT identifies a node by its id, so
    /// two peers that detach the same instance concurrently must not mint the same ids for
    /// what are two separate creations — a delete of one would be undone by the other's
    /// late-arriving create. ``EditableDocument`` passes its ``CRDTDocument/peerID`` here
    /// in collaborative mode; a plain document passes none. Either way the ids stay a
    /// function of the document, which is what an inverse prepared before the detach needs.
    ///
    /// Every node is renamed, so ``replacements`` maps each expanded id to its new id, and
    /// ``applied(to:)`` rewrites a reference pointing inside the expansion exactly as a
    /// ``regenerating(_:avoiding:)`` plan does.
    ///
    /// - Parameters:
    ///   - expanded: The expansion, as ``PenRefExpander`` produced it — its ids are the
    ///     ref's own and prefixed component ids.
    ///   - refID: The id of the ref being detached.
    ///   - replica: The collaborative replica doing the detach, or `nil` outside a
    ///     collaborative session.
    ///   - taken: Ids no planned id may take: the document's, and any a replica cannot
    ///     reuse.
    /// - Returns: The plan.
    static func detaching(
        _ expanded: PenNode,
        refID: String,
        replica: PeerID? = nil,
        avoiding taken: Set<String>
    ) -> SubtreeIDPlan {
        let namespace = replica.map { "\($0.rawValue)/\(refID)" } ?? refID
        var plan = SubtreeIDPlan(ids: [], replacements: [:])
        var used = taken
        // Pre-order from a work list: the expansion can be as deep as the component.
        var pending: [PenNode] = [expanded]
        while let node = pending.popLast() {
            let id = derivedID(for: node.id, namespace: namespace, avoiding: used)
            used.insert(id)
            plan.ids.append(id)
            plan.replacements[node.id] = id
            pending.append(contentsOf: node.kind.inlineChildren.reversed())
        }
        return plan
    }

    // MARK: - Private

    /// The first free id in one expanded node's salt sequence.
    ///
    /// - Parameters:
    ///   - expandedID: The node's id in the expansion.
    ///   - namespace: The ref being detached, behind the replica when there is one.
    ///   - used: Ids already taken.
    /// - Returns: The derived id.
    private static func derivedID(for expandedID: String, namespace: String, avoiding used: Set<String>) -> String {
        let seed = "\(namespace)/\(expandedID)"
        var salt = 0
        while true {
            var hasher = FNV1aHasher()
            hasher.combine(salt == 0 ? seed : "\(seed)#\(salt)")
            let id = base62(hasher.finalize())
            if !used.contains(id) { return id }
            salt += 1
        }
    }

    /// The low digits of a hash in base 62, as many as an id has.
    ///
    /// - Parameter value: The hash.
    /// - Returns: A ``PenID``-shaped id.
    private static func base62(_ value: UInt64) -> String {
        let radix = UInt64(PenID.charset.count)
        var remaining = value
        var digits: [Character] = []
        digits.reserveCapacity(PenID.length)
        for _ in 0 ..< PenID.length {
            digits.append(PenID.charset[Int(remaining % radix)])
            remaining /= radix
        }
        return String(digits)
    }
}
