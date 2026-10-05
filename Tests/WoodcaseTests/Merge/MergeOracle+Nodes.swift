//
//  MergeOracle+Nodes.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// The oracle's node rules: own keys, type, parent and sibling order.
extension MergeOracle {
    /// The nodes ours and theirs both hold and the merge kept — the ones every key of
    /// which has a three-way answer. Base may lack them (both added one id).
    private var sharedNodeIDs: [String] {
        ours.nodes.keys.filter { theirs.nodes[$0] != nil && merged.nodes[$0] != nil }.sorted()
    }

    func nodeKeys() -> [String] {
        var out: [String] = []
        for id in sharedNodeIDs {
            let sides = [base, ours, theirs, merged].map { Self.keys(of: $0.nodes[id]) }
            let types = sides.map { $0?["type"] }
            if types[1] != types[0] {
                if types[3] != types[1] { out.append("\(id): ours retyped it, the merge did not keep ours' type") }
            } else if types[2] != types[0], types[3] != types[2], !reported(.nodeType(nodeID: id)) {
                out.append("\(id): theirs retyped it, the merge did not take it and did not say why")
            }
            // A retype on either side replaces every kind key; the type rule above covers it.
            let heldTypes = sides[0] == nil ? Array(types.dropFirst()) : types
            guard Set(heldTypes).count == 1, let o = sides[1], let t = sides[2], let m = sides[3] else { continue }
            let b = sides[0] ?? [:]
            for key in Set(b.keys).union(o.keys).union(t.keys).union(m.keys).sorted() where key != "type" {
                let (expected, contested) = Self.pick(b[key], o[key], t[key])
                if m[key] != expected {
                    out.append("\(id).\(key): expected \(String(describing: expected)), got \(String(describing: m[key]))")
                }
                if contested, !reportedAny(nodeID: id) { out.append("\(id).\(key): both changed it, unreported") }
            }
        }
        return out
    }

    func placement() -> [String] {
        var out: [String] = []
        for id in sharedNodeIDs {
            let parents = [base, ours, theirs, merged].map { $0.nodes[id] == nil ? nil : $0.parents[id] ?? "" }
            let (expected, contested) = Self.pick(parents[0], parents[1], parents[2])
            let subject = MergeConflict.Subject.parent(nodeID: id)
            if parents[3] != expected, !reported(subject) {
                out.append("\(id): expected parent \(expected ?? "nil"), got \(parents[3] ?? "nil"), unreported")
            }
            if contested, !reported(subject) { out.append("\(id): both moved it, unreported") }
        }
        return out
    }

    /// Where only one side changed a list, the merged list keeps that side's relative
    /// order among the members that landed in it.
    func childOrder() -> [String] {
        var out: [String] = []
        let parents: [String?] = [nil] + base.nodes.keys.filter { ours.nodes[$0] != nil && theirs.nodes[$0] != nil && merged.nodes[$0] != nil }.sorted()
        for parent in parents {
            let lists = [base, ours, theirs, merged].map { Self.children(of: parent, in: $0) }
            if reported(.childOrder(parentID: parent)) { continue }
            for (side, other) in [(2, 1), (1, 2)] where lists[other] == lists[0] {
                let members = lists[side].filter { merged.nodes[$0] != nil && merged.parents[$0] == parent }
                guard members.count == lists[side].count else { continue }
                let kept = lists[3].filter(members.contains)
                if kept != members {
                    out.append("children of \(parent ?? "root"): expected \(members), got \(kept)")
                }
            }
        }
        return out
    }

    // MARK: - Reading nodes

    /// A node's own JSON keys, its id and child list left out; a `ref`'s descendant
    /// overrides flattened to one key per descendant and key, as the merge resolves them.
    static func keys(of node: PenNode?) -> [String: AnyCodable]? {
        guard let node, case let .dictionary(json) = try? NodePropertyCodec.encode(node) else { return nil }
        var keys = json.filter { $0.key != "id" && $0.key != "children" && $0.key != "descendants" }
        if case let .dictionary(descendants) = json["descendants"] {
            for (descendant, entry) in descendants {
                guard case let .dictionary(properties) = entry else {
                    keys["descendants/\(descendant)"] = entry
                    continue
                }
                for (key, value) in properties {
                    keys["descendants/\(descendant)/\(key)"] = value
                }
            }
        }
        return keys
    }

    /// A container's child ids, or the top-level ids for `nil`.
    static func children(of parent: String?, in document: EditableDocument) -> [String] {
        parent.map { document.children[$0] ?? [] } ?? document.rootOrder
    }
}
