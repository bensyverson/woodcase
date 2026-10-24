//
//  SlotJSON+Renumber.swift
//  Woodcase
//

import Foundation

/// Fresh ids for nodes headed into a fill, so ids stay unique across the document.
///
/// Pen renames every repeated id on load, document-wide, a node in a fill included
/// (`project/2026-09-26-slot-override-keys.md`, rule 6), and a path naming the renamed
/// repeat stops resolving. So a copy written into a fill — a duplicate, a paste, the
/// default content copied on a slot's first change — takes a fresh id for every node in
/// it: its inline children, and the nodes in every fill an instance among them writes.
extension SlotJSON {
    /// A node JSON with a fresh id on every node it holds, at every depth.
    ///
    /// - Parameters:
    ///   - value: The node JSON.
    ///   - oldBase: The expanded-id prefix the node answers to now (`Filled/`).
    ///   - newBase: The expanded-id prefix it will answer to.
    ///   - taken: Every id in use, the drawn ones added as they are drawn.
    ///   - renames: Old expanded id → new, for every node renumbered, gathered.
    /// - Returns: The renumbered JSON.
    static func renumbered(
        _ value: AnyCodable,
        oldBase: String,
        newBase: String,
        taken: inout Set<String>,
        renames: inout [String: String]
    ) -> AnyCodable {
        guard case var .dictionary(node) = value else { return value }
        let separator = String(NodeAddress.separator)
        let old = id(of: value)
        let fresh = PenID.generate(avoiding: taken)
        taken.insert(fresh)
        node[idKey] = .string(fresh)
        if let old { renames[oldBase + old] = newBase + fresh }

        if case let .array(children)? = node[childrenKey] {
            node[childrenKey] = .array(children.map {
                renumbered($0, oldBase: oldBase, newBase: newBase, taken: &taken, renames: &renames)
            })
        }
        guard isRef(node), case var .dictionary(map)? = node[descendantsKey] else { return .dictionary(node) }
        let innerOld = oldBase + (old ?? fresh) + separator
        let innerNew = newBase + fresh + separator
        for key in map.keys.sorted() {
            guard case var .dictionary(entry)? = map[key], case let .array(fill)? = entry[childrenKey] else { continue }
            entry[childrenKey] = .array(fill.map {
                renumbered($0, oldBase: innerOld, newBase: innerNew, taken: &taken, renames: &renames)
            })
            map[key] = .dictionary(entry)
        }
        node[descendantsKey] = .dictionary(map)
        return .dictionary(node)
    }

    /// A node JSON whose ids are kept where none is taken, and renumbered whole where one
    /// is — a node moved into a fill keeps its ids, so a selection of it holds.
    ///
    /// - Parameters:
    ///   - value: The node JSON.
    ///   - base: The expanded-id prefix it will answer to.
    ///   - taken: Every id in use apart from the node's own, its ids added.
    ///   - renames: Old expanded id → new, for every node renumbered, gathered.
    /// - Returns: The JSON, renumbered only if it had to be.
    static func keepingIDs(
        _ value: AnyCodable,
        base: String,
        taken: inout Set<String>,
        renames: inout [String: String]
    ) -> AnyCodable {
        let ids = allIDs(in: [value])
        guard Set(ids).count == ids.count, !ids.contains(where: taken.contains), !ids.contains(where: { !PenID.isValid($0) })
        else { return renumbered(value, oldBase: base, newBase: base, taken: &taken, renames: &renames) }
        taken.formUnion(ids)
        return value
    }
}

// MARK: - Stored nodes

extension SlotJSON {
    /// A node headed into the document with its ids settled: kept when none is taken,
    /// none repeats and each is valid — the nodes in the fills an instance among them
    /// writes counted too — else drawn afresh, the whole subtree and its fills.
    ///
    /// - Parameters:
    ///   - node: The node, with its children inline.
    ///   - taken: Every id in use, the node's ids added.
    /// - Returns: The node as it will be inserted.
    static func settlingIDs(of node: PenNode, taken: inout Set<String>) -> PenNode {
        var settled = node
        let inline = collectIDs(inlineOf: node)
        if Set(inline).count == inline.count, !inline.contains(where: taken.contains), inline.allSatisfy(PenID.isValid) {
            taken.formUnion(inline)
        } else {
            let plan = SubtreeIDPlan.regenerating(node, avoiding: taken)
            taken.formUnion(plan.ids)
            settled = plan.applied(to: node)
        }
        let filled = fillIDs(in: settled)
        if Set(filled).count == filled.count, !filled.contains(where: taken.contains), filled.allSatisfy(PenID.isValid) {
            taken.formUnion(filled)
            return settled
        }
        return renumberingFills(of: settled, taken: &taken)
    }

    /// The ids of a node's inline tree, root first.
    private static func collectIDs(inlineOf node: PenNode) -> [String] {
        var result: [String] = []
        var pending = [node]
        while let next = pending.popLast() {
            result.append(next.id)
            pending.append(contentsOf: next.kind.inlineChildren.reversed())
        }
        return result
    }

    /// A node with a fresh id on every node in the fills its instances write, at every
    /// depth — what a copy needs on top of ``SubtreeIDPlan``, which renumbers the inline
    /// tree only.
    ///
    /// - Parameters:
    ///   - node: The node, with its children inline.
    ///   - taken: Every id in use, the drawn ones added.
    /// - Returns: The node with its fills renumbered.
    static func renumberingFills(of node: PenNode, taken: inout Set<String>) -> PenNode {
        applyingFillRenames(fillRenames(in: node, taken: &taken), to: node)
    }

    /// A fresh id for every node in the fills a node's instances write, at every depth,
    /// drawn but not yet written — so a caller that maps paths through ids (a paste's
    /// connector ends and override keys) can map these too, then apply them with
    /// ``applyingFillRenames(_:to:)``.
    ///
    /// - Parameters:
    ///   - node: The node, with its children inline.
    ///   - taken: Every id in use, the drawn ones added.
    /// - Returns: Old id → new id, for each node in a fill.
    static func fillRenames(in node: PenNode, taken: inout Set<String>) -> [String: String] {
        var renames: [String: String] = [:]
        for id in fillIDs(in: node) where renames[id] == nil {
            let fresh = PenID.generate(avoiding: taken)
            taken.insert(fresh)
            renames[id] = fresh
        }
        return renames
    }

    /// A node with the ids of the nodes in its instances' fills rewritten through a map,
    /// at every depth; ids the map does not name stay.
    ///
    /// - Parameters:
    ///   - renames: Old id → new id.
    ///   - node: The node, with its children inline.
    /// - Returns: The node with its fills' ids rewritten.
    static func applyingFillRenames(_ renames: [String: String], to node: PenNode) -> PenNode {
        guard !renames.isEmpty else { return node }
        return PenTreeRewrite.rewrite(node, context: ()) { current, _ in
            guard case var .ref(data) = current.kind, var descendants = data.descendants else {
                return .descend(current, ())
            }
            for key in descendants.keys.sorted() {
                guard case let .array(fill)? = descendants[key]?.properties[childrenKey] else { continue }
                descendants[key]?.properties[childrenKey] = .array(fill.map { renaming($0, through: renames) })
            }
            data.descendants = descendants
            return .keep(PenNode(id: current.id, common: current.common, kind: .ref(data), extras: current.extras))
        } ?? node
    }

    /// A node JSON with every id it holds — inline and in its fills — rewritten through a map.
    private static func renaming(_ value: AnyCodable, through renames: [String: String]) -> AnyCodable {
        guard case var .dictionary(node) = value else { return value }
        if case let .string(id)? = node[idKey], let new = renames[id] { node[idKey] = .string(new) }
        if case let .array(children)? = node[childrenKey] {
            node[childrenKey] = .array(children.map { renaming($0, through: renames) })
        }
        if case var .dictionary(map)? = node[descendantsKey] {
            for key in map.keys.sorted() {
                guard case var .dictionary(entry)? = map[key], case let .array(fill)? = entry[childrenKey] else { continue }
                entry[childrenKey] = .array(fill.map { renaming($0, through: renames) })
                map[key] = .dictionary(entry)
            }
            node[descendantsKey] = .dictionary(map)
        }
        return .dictionary(node)
    }

    /// The ids of the nodes in the fills a node's instances write, at every depth.
    static func fillIDs(in node: PenNode) -> [String] {
        var result: [String] = []
        var pending = [node]
        while let next = pending.popLast() {
            if case let .ref(data) = next.kind {
                for key in (data.descendants ?? [:]).keys.sorted() {
                    guard case let .array(fill)? = data.descendants?[key]?.properties[childrenKey] else { continue }
                    result.append(contentsOf: allIDs(in: fill))
                }
            }
            pending.append(contentsOf: next.kind.inlineChildren.reversed())
        }
        return result
    }
}

extension EditableDocument {
    /// Every id the document holds or a peer still holds, the nodes in every fill
    /// included — the ids a new node anywhere, in a fill or not, must not take.
    var idsInUse: Set<String> {
        var taken = detachTakenIDs
        for node in nodes.values {
            guard case let .ref(data) = node.kind, let descendants = data.descendants else { continue }
            for entry in descendants.values {
                guard case let .array(fill)? = entry.properties[SlotJSON.childrenKey] else { continue }
                taken.formUnion(SlotJSON.allIDs(in: fill))
            }
        }
        return taken
    }
}
