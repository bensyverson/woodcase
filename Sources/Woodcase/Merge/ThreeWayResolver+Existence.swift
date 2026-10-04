//
//  ThreeWayResolver+Existence.swift
//  Woodcase
//

import Foundation

/// Which nodes the merged document holds (the design's algorithm step 3).
extension ThreeWayResolver {
    /// Resolves the nodes one side deleted or added.
    ///
    /// - A node theirs deleted goes, unless ours edited it or anything under it, or
    ///   added something under it: then it stays, with every ancestor theirs deleted,
    ///   each reported as ``MergeConflict/Kind/editedLocallyDeletedExternally``.
    /// - A node ours deleted stays deleted. When theirs edited it or anything under it,
    ///   the topmost node ours deleted is reported as
    ///   ``MergeConflict/Kind/deletedLocallyEditedExternally``, carrying both subtrees.
    /// - A node only theirs added is inserted, unless its parent does not survive: then
    ///   the topmost such insert is dropped and reported as
    ///   ``MergeConflict/Kind/orphanedExternalInsert``, carrying its subtree.
    mutating func resolveExistence() {
        removed = Set(theirsChanges.nodes.lazy.filter { $0.value.existence == .removed }.map(\.key))
            .filter { ours.nodes[$0] != nil }

        let seeds = oursChanges.nodes.filter { $0.value.existence == .added || isEdited($0.value) }.keys
        for id in seeds.sorted() {
            keepChain(from: id, kind: .editedLocallyDeletedExternally)
        }

        reportLocalDeletesOfExternalEdits()
        dropOrphanedInserts()
    }

    /// Keeps `id`, if the merge was removing it, and every ancestor of it in the local
    /// tree the merge was removing, reporting each with `kind`.
    mutating func keepChain(from id: String, kind: MergeConflict.Kind) {
        var current: String? = id
        while let node = current {
            if removed.remove(node) != nil {
                report(.existence(nodeID: node), kind)
            }
            current = ours.parents[node]
        }
    }

    /// Reports each topmost node ours deleted under which theirs edited something.
    private mutating func reportLocalDeletesOfExternalEdits() {
        var tops: Set<String> = []
        for (id, change) in theirsChanges.nodes where ours.nodes[id] == nil && isEdited(change) {
            var top = id
            while let parent = base.parents[top], ours.nodes[parent] == nil {
                top = parent
            }
            tops.insert(top)
        }
        for top in tops.sorted() {
            report(
                .existence(nodeID: top), .deletedLocallyEditedExternally,
                base: subtree(top, of: base), theirs: theirs.nodes[top].flatMap { _ in subtree(top, of: theirs) }
            )
        }
    }

    /// Drops every external insert whose parent does not survive, reporting the topmost.
    private mutating func dropOrphanedInserts() {
        let inserts = theirsChanges.nodes.filter { $0.value.existence == .added && ours.nodes[$0.key] == nil }.keys
        var fate: [String: Bool] = [:]
        for id in inserts.sorted() {
            guard !isTakenInsert(id, fate: &fate) else { continue }
            dropped.insert(id)
            if let parent = theirs.parents[id], base.nodes[parent] != nil {
                report(.existence(nodeID: id), .orphanedExternalInsert, theirs: subtree(id, of: theirs))
            }
        }
    }

    /// Whether an external insert survives: its parent is the top level, a node the
    /// local side holds, or another insert that survives.
    private func isTakenInsert(_ id: String, fate: inout [String: Bool]) -> Bool {
        if let known = fate[id] { return known }
        var chain: [String] = []
        var current = id
        var taken = true
        // Climb the chain of inserts iteratively, then settle every one on it at once.
        while true {
            if let known = fate[current] {
                taken = known
                break
            }
            chain.append(current)
            guard let parent = theirs.parents[current] else { break }
            if ours.nodes[parent] != nil { break }
            guard base.nodes[parent] == nil else {
                taken = false
                break
            }
            current = parent
        }
        for link in chain {
            fate[link] = taken
        }
        return taken
    }

    /// A node's subtree as the .pen file writes it, for a conflict to carry.
    func subtree(_ id: String, of document: EditableDocument) -> AnyCodable? {
        try? NodePropertyCodec.encode(document.materializeSubtree(rootID: id))
    }

    // MARK: - Components

    /// Keeps every component the merge would remove while a node it keeps still renders
    /// it — with its whole definition and the ancestors theirs deleted — and reports it
    /// as ``MergeConflict/Kind/componentKeptForLocalInstance``.
    mutating func keepComponentsForInstances() {
        while true {
            let doomed = removed.filter { ours.componentRegistry[$0] != nil }
            guard !doomed.isEmpty else { return }
            let needed = doomed.intersection(survivingReferences(into: doomed))
            guard !needed.isEmpty else { return }
            for component in needed.sorted() {
                removed.subtract(ours.descendantIDs(of: component))
                report(.existence(nodeID: component), .componentKeptForLocalInstance)
                keepChain(from: component, kind: .componentKeptForLocalInstance)
            }
        }
    }

    /// The components in `targets` that a node in the merged document refers to.
    private func survivingReferences(into targets: Set<String>) -> Set<String> {
        var found: Set<String> = []
        let inserted = contents.keys.filter { ours.nodes[$0] == nil && survives($0) }
        for id in Array(ours.nodes.keys) + inserted where survives(id) {
            guard case let .ref(data)? = (contents[id] ?? ours.nodes[id])?.kind, targets.contains(data.ref) else { continue }
            found.insert(data.ref)
        }
        return found
    }
}
