//
//  ThreeWayResolver+Content.swift
//  Woodcase
//

import Foundation

/// A node's own content, merged key by key (the design's algorithm step 2).
extension ThreeWayResolver {
    /// Merges the content of every node theirs changed or added that the merge keeps.
    ///
    /// A node both sides added with one id merges against an absent base, so a key
    /// only one side sets is taken and a key both set differently is reported as
    /// ``MergeConflict/Kind/addedTwice``.
    mutating func resolveContent() {
        for id in theirsChanges.nodes.keys.sorted() {
            guard let theirsNode = theirs.nodes[id] else { continue }
            guard let oursNode = ours.nodes[id] else {
                if !dropped.contains(id) { contents[id] = theirsNode }
                continue
            }
            let baseNode = base.nodes[id]
            let keys = baseNode == nil
                ? NodeChangeKey.contentDifferences(oursNode, theirsNode)
                : theirsChanges.nodes[id]?.keys.filter { $0.propertyPath != nil } ?? []
            guard !keys.isEmpty else { continue }
            let merged = mergeContent(id: id, base: baseNode, ours: oursNode, theirs: theirsNode, keys: keys)
            if merged != oursNode { contents[id] = merged }
        }
    }

    /// One node's merged content, starting from ours and taking each key of `keys` that
    /// only theirs changed.
    private mutating func mergeContent(id: String, base: PenNode?, ours: PenNode, theirs: PenNode, keys: Set<NodeChangeKey>) -> PenNode {
        if let base, ours == base { return theirs }
        let kind: MergeConflict.Kind = base == nil ? .addedTwice : .bothChanged
        let oursRetyped = base.map { $0.kind.typeName != ours.kind.typeName } ?? false
        let oursTouchedKind = base.map { $0.kind != ours.kind } ?? true
        var merged = ours
        var typeReported = false

        // The type goes first: which keys are extras depends on it, so an extra of theirs
        // is written onto the type the node ends up with.
        let ordered = keys.sorted { lhs, rhs in
            (lhs == .type ? 0 : 1, lhs.propertyPath ?? "") < (rhs == .type ? 0 : 1, rhs.propertyPath ?? "")
        }
        for key in ordered {
            guard let path = key.propertyPath else { continue }
            let isKindKey = key == .type || path.hasPrefix("kind.")
            if isKindKey, key == .type || oursRetyped {
                guard oursTouchedKind else {
                    merged.kind = theirs.kind
                    continue
                }
                if !typeReported, ours.kind != theirs.kind {
                    typeReported = true
                    report(
                        .nodeType(nodeID: id), kind, base: base.map { .string($0.kind.typeName) },
                        ours: .string(ours.kind.typeName), theirs: .string(theirs.kind.typeName)
                    )
                }
                continue
            }
            if case .ref = merged.kind, path == "kind.descendants" || path == "kind.rootOverrides" {
                mergeOverrides(path, id: id, base: base, ours: ours, theirs: theirs, into: &merged, kind: kind)
                continue
            }
            mergeValue(at: path, id: id, base: base, ours: ours, theirs: theirs, into: &merged, kind: kind)
        }
        return merged
    }

    /// Merges one property path: theirs' value when ours left it as the base has it,
    /// otherwise ours', reported when the two differ.
    private mutating func mergeValue(
        at path: String, id: String, base: PenNode?, ours: PenNode, theirs: PenNode,
        into merged: inout PenNode, kind: MergeConflict.Kind
    ) {
        let baseValue = base.map { Self.value(at: path, of: $0) } ?? .null
        let oursValue = Self.value(at: path, of: ours)
        let theirsValue = Self.value(at: path, of: theirs)
        guard theirsValue != baseValue, oursValue != theirsValue else { return }
        guard oursValue == baseValue else {
            report(.property(nodeID: id, path: path), kind, base: base.map { _ in baseValue }, ours: oursValue, theirs: theirsValue)
            return
        }
        do {
            merged = try NodePropertyCodec.setting(theirsValue, at: path, on: merged)
        } catch where path.hasPrefix(NodePropertyCodec.extrasPrefix) && merged.kind.typeName != theirs.kind.typeName {
            // An extra is a key theirs' type does not model; ours' type, kept over it,
            // may model that key, so the value cannot go in as an extra.
            report(.property(nodeID: id, path: path), kind, base: base.map { _ in baseValue }, ours: oursValue, theirs: theirsValue)
        } catch {
            assertionFailure("Node \(id): theirs' \(path) does not write back through the codec: \(error)")
        }
    }

    /// Keeps ours' type for every node theirs retyped to a leaf that still holds
    /// children in the merge — children ours gave it, which a leaf cannot hold — and
    /// reports it as a ``MergeConflict/Subject/nodeType(nodeID:)`` both sides changed.
    mutating func keepContainersHoldingChildren() {
        for id in contents.keys.sorted() {
            guard let merged = contents[id], !merged.kind.canHaveChildren,
                  let local = ours.nodes[id], local.kind.canHaveChildren else { continue }
            let children: [String]? = if let entry = childLists[id] { entry } else { ours.children[id] }
            guard !(children ?? []).isEmpty else { continue }
            contents[id]?.kind = local.kind
            report(
                .nodeType(nodeID: id), .bothChanged, base: base.nodes[id].map { .string($0.kind.typeName) },
                ours: .string(local.kind.typeName), theirs: .string(merged.kind.typeName)
            )
        }
    }

    /// A property's value, or ``AnyCodable/null`` when the node's kind has no such path.
    static func value(at path: String, of node: PenNode) -> AnyCodable {
        (try? NodePropertyCodec.value(at: path, of: node)) ?? .null
    }
}
