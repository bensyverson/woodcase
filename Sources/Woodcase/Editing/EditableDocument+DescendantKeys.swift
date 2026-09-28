//
//  EditableDocument+DescendantKeys.swift
//  Woodcase
//

import Foundation

/// The keys an instance's `descendants` map can hold, as the override guard lists them.
extension EditableDocument {
    /// The keys one walk of an instance finds, and what each of them is.
    struct DescendantKeyList: Friendly {
        /// Every key, in tree order.
        var keys: [String] = []

        /// The keys that name a component root.
        var roots: Set<String> = []

        /// The keys that name content the instance wrote into a slot itself.
        var own: Set<String> = []

        /// Records a key, unless it is already listed.
        ///
        /// - Returns: `false` when the key was listed before.
        mutating func add(_ key: String, isRoot: Bool = false, isOwn: Bool) -> Bool {
            guard !keys.contains(key) else { return false }
            keys.append(key)
            if isRoot { roots.insert(key) }
            if isOwn { own.insert(key) }
            return true
        }
    }

    /// Every key Pen lets this instance write in its `descendants` map.
    ///
    /// A node directly in the component is its own id; a node inside a `ref` nested in
    /// the component is that ref's id, a `/`, then the key within *its* component —
    /// exactly the prefixing ``PenRefExpander`` applies when it expands. The component
    /// root is included: the patcher matches it like any other node.
    ///
    /// Content the instance wrote into a slot itself is left out: Pen drops a key that
    /// names it, bare or by path (`project/2026-09-26-slot-override-keys.md`, rule 5,
    /// and its follow-up), and so does the expansion. That content is still an address
    /// — ``ownSlotContentKeys(ofInstance:)`` lists it — but it is edited where it is
    /// written, in the slot's `children`.
    ///
    /// The walk reads each ref — the instance's own included — through
    /// ``componentRoot(ofInstanceChain:)``, so an instance that has repointed one lists
    /// the keys of the component it repointed *at*, and a component that is itself a
    /// `ref` to another is followed to the far end of that chain. Either way the keys
    /// are the nodes the expansion actually holds.
    ///
    /// - Parameter refNodeID: The instance's `ref` node id.
    /// - Returns: The keys in tree order, each nested ref's keys following the ref.
    ///   Empty for a node that is not a `ref`, or whose component is not in the
    ///   registry.
    func overridableDescendantKeys(ofInstance refNodeID: String) -> [String] {
        let found = descendantKeys(ofInstance: refNodeID)
        return found.keys.filter { !found.own.contains($0) }
    }

    /// The keys an address can reach inside this instance.
    ///
    /// A component *root* is patchable — Pen's patcher matches it like any other node,
    /// so a `descendants` entry keyed by it applies — but no address resolves to it:
    /// stepping into an instance lands on the component's *children*, deliberately, so
    /// that one node never has two addresses storing an edit in two places. The root's
    /// own properties are the instance's root overrides, written by addressing the
    /// instance itself. Content the instance wrote into a slot itself *is* here: it is
    /// an address to read, though not a key to override — a caller offering override
    /// targets leaves out ``ownSlotContentKeys(ofInstance:)`` too.
    ///
    /// - Parameter refNodeID: The instance's `ref` node id.
    /// - Returns: The keys in tree order, component roots removed.
    func addressableDescendantKeys(ofInstance refNodeID: String) -> [String] {
        let found = descendantKeys(ofInstance: refNodeID)
        return found.keys.filter { !found.roots.contains($0) }
    }

    /// The keys naming content the instance wrote into a slot itself.
    ///
    /// Each names a node the instance draws and an address resolves to, and none is a
    /// key Pen lets the instance override: the node is edited in the `children` of the
    /// slot that holds it.
    ///
    /// - Parameter refNodeID: The instance's `ref` node id.
    /// - Returns: The keys, in no particular order.
    func ownSlotContentKeys(ofInstance refNodeID: String) -> Set<String> {
        descendantKeys(ofInstance: refNodeID).own
    }

    /// The slot to rewrite instead, when a key names content the instance wrote into a
    /// slot itself.
    ///
    /// For a node the instance injected, that is the slot it was injected into; for a
    /// node of a component an injected `ref` places, it is the slot holding that `ref`.
    ///
    /// - Parameters:
    ///   - refNodeID: The instance's `ref` node id.
    ///   - descendantKey: The key.
    /// - Returns: The slot's full name path, or `nil` when the key names no content the
    ///   instance wrote itself.
    func ownSlotPath(ofInstance refNodeID: String, descendantKey: String) -> String? {
        guard ownSlotContentKeys(ofInstance: refNodeID).contains(descendantKey) else { return nil }
        var steps = descendantKey.split(separator: NodeAddress.separator).map(String.init)
        while !steps.isEmpty {
            let key = steps.joined(separator: String(NodeAddress.separator))
            if let slot = injectionPoint(ofInstance: refNodeID, descendantKey: key) { return slot }
            steps.removeLast()
        }
        return nil
    }

    /// Every key this instance's expansion holds, and what each one is.
    private func descendantKeys(ofInstance refNodeID: String) -> DescendantKeyList {
        var found = DescendantKeyList()
        guard let componentID = componentRoot(ofInstanceChain: [refNodeID]) else { return found }
        appendDescendantKeys(
            ofComponent: componentID, prefix: "", chain: [refNodeID], visited: [], isOwn: false, into: &found
        )
        return found
    }

    /// Walks one component's overridable nodes, stepping through nested refs.
    ///
    /// `componentID` is always the *resolved* root — the far end of any alias chain —
    /// because that is the subtree the expander clones and prefixes. `visited` carries
    /// the components already on this chain, so a component that refers to itself
    /// terminates instead of recurring forever. `chain` carries the `ref` nodes the walk
    /// has stepped through, which is what tells a nested ref whether an instance above
    /// it has repointed it — and what tells a slot frame which children the instance
    /// wrote into it. `isOwn` says the walk is already inside content the instance
    /// wrote itself.
    ///
    /// A node an override fills contributes the injected children *instead of* its own
    /// subtree, which is the substitution ``PenRefExpander`` makes: an override keyed by
    /// a node the fill replaced would never apply, so it is not a key this instance has.
    ///
    /// Runs from a work list rather than by recursion: a component chained to another
    /// through nested `ref`s, dozens of thousands deep, used to recurse one Swift call
    /// per level and overflow a task's 512 KiB stack in a debug build
    /// (`project/2026-09-26-debug-stack-depth.md`). `DescendantKeyStep` carries one
    /// pending call frame's own state — everything the recursive version captured on
    /// the stack — and `drain(_:into:)` pushes each one's own recursive call *before*
    /// the rest of its list, so the stack still visits nodes in the same pre-order the
    /// recursion did.
    private func appendDescendantKeys(
        ofComponent componentID: String,
        prefix: String,
        chain: [String],
        visited: Set<String>,
        isOwn: Bool,
        into found: inout DescendantKeyList
    ) {
        var stack: [DescendantKeyStep] = []
        if let first = componentStep(
            componentID: componentID, prefix: prefix, chain: chain, visited: visited, isOwn: isOwn
        ) {
            stack.append(first)
        }
        drain(&stack, into: &found)
    }

    /// Walks the children an instance injected into one node.
    ///
    /// An injected node is keyed by its own id under the *same* prefix as the node it
    /// was written into — expansion prefixes every id in the clone with the instance's,
    /// however deep, so the key gains no step. A `ref` among them does add one: the
    /// nodes of the component it places answer to the cross-ref key the expander
    /// applies after expansion.
    ///
    /// Runs from the same work list `appendDescendantKeys(ofComponent:prefix:chain:visited:isOwn:into:)`
    /// does — a single override's inline `children` can nest as deep as the format
    /// allows, and each level used to recurse one Swift call.
    private func appendInjectedKeys(
        _ injected: [PenNode],
        prefix: String,
        chain: [String],
        visited: Set<String>,
        isOwn: Bool,
        into found: inout DescendantKeyList
    ) {
        guard !injected.isEmpty else { return }
        var stack: [DescendantKeyStep] = [
            .injected(items: injected, index: 0, prefix: prefix, chain: chain, visited: visited, isOwn: isOwn),
        ]
        drain(&stack, into: &found)
    }

    // MARK: - The work list

    /// One pending call frame of the descendant-key walk: everything either recursive
    /// function once captured on the native call stack, kept on a plain array instead.
    ///
    /// A step names the list it is partway through (a component's overridable nodes, or
    /// one instance's injected children) and the index to resume at — the rest of that
    /// list is pushed back onto the stack, under whatever recursive work the current
    /// element produces, so the deeper work drains first and the list resumes only once
    /// it has.
    private enum DescendantKeyStep {
        /// Resuming `appendDescendantKeys(ofComponent:prefix:chain:visited:isOwn:into:)`'s
        /// loop over one component's overridable nodes.
        ///
        /// `replaced` is that call's own `replaced` set: ids an override already
        /// consumed, which the loop's `where` clause skipped over rather than visiting.
        case component(
            items: [OverridableNode], index: Int, componentID: String,
            prefix: String, chain: [String], visited: Set<String>, replaced: Set<String>, isOwn: Bool
        )

        /// Resuming `appendInjectedKeys(_:prefix:chain:visited:isOwn:into:)`'s loop
        /// over one list of injected nodes.
        case injected(
            items: [PenNode], index: Int,
            prefix: String, chain: [String], visited: Set<String>, isOwn: Bool
        )
    }

    /// The first step of walking one component, or `nil` under exactly the guard
    /// `appendDescendantKeys(ofComponent:prefix:chain:visited:isOwn:into:)` used to
    /// open with: already on the chain, not in the registry, or with nothing to walk.
    private func componentStep(
        componentID: String, prefix: String, chain: [String], visited: Set<String>, isOwn: Bool
    ) -> DescendantKeyStep? {
        guard !visited.contains(componentID), let surface = inspectComponent(componentID),
              !surface.overridableNodes.isEmpty
        else { return nil }
        var seen = visited
        seen.insert(componentID)
        return .component(
            items: surface.overridableNodes, index: 0, componentID: componentID,
            prefix: prefix, chain: chain, visited: seen, replaced: [], isOwn: isOwn
        )
    }

    /// Drains a work list of pending steps, in the order the recursive walk once
    /// visited them.
    ///
    /// Each step processes exactly one element of its list, pushes its own list's
    /// resumption (if any elements remain), and *then* pushes whatever recursive call
    /// that element produced — so the stack, a LIFO, pops the deeper work first and only
    /// resumes a list once everything under its current element is done. That is the
    /// same order a native call stack enforces for free.
    private func drain(_ stack: inout [DescendantKeyStep], into found: inout DescendantKeyList) {
        while let step = stack.popLast() {
            switch step {
            case let .component(items, index, componentID, prefix, chain, visited, replaced, isOwn):
                guard index < items.count else { continue }
                let overridable = items[index]
                guard !replaced.contains(overridable.nodeID) else {
                    if index + 1 < items.count {
                        stack.append(.component(
                            items: items, index: index + 1, componentID: componentID,
                            prefix: prefix, chain: chain, visited: visited, replaced: replaced, isOwn: isOwn
                        ))
                    }
                    continue
                }

                let key = prefix + overridable.nodeID
                _ = found.add(key, isRoot: overridable.nodeID == componentID, isOwn: isOwn)

                let injected = injectedChildren(of: overridable.nodeID, insideInstances: chain)
                var nextReplaced = replaced
                if injected != nil {
                    nextReplaced.formUnion(descendantIDs(of: overridable.nodeID).dropFirst())
                }
                if index + 1 < items.count {
                    stack.append(.component(
                        items: items, index: index + 1, componentID: componentID,
                        prefix: prefix, chain: chain, visited: visited, replaced: nextReplaced, isOwn: isOwn
                    ))
                }

                if let injected {
                    let ownFill = isOwn || injectedChildrenAreOwn(of: overridable.nodeID, insideInstances: chain)
                    if !injected.isEmpty {
                        stack.append(.injected(
                            items: injected, index: 0, prefix: prefix, chain: chain, visited: visited, isOwn: ownFill
                        ))
                    }
                    continue
                }
                guard let nested = componentRootID(placedBy: overridable.nodeID, insideInstances: chain)
                else { continue }
                if let nestedStep = componentStep(
                    componentID: nested, prefix: key + String(NodeAddress.separator),
                    chain: chain + [overridable.nodeID], visited: visited, isOwn: isOwn
                ) {
                    stack.append(nestedStep)
                }

            case let .injected(items, index, prefix, chain, visited, isOwn):
                guard index < items.count else { continue }
                let node = items[index]
                if index + 1 < items.count {
                    stack.append(.injected(
                        items: items, index: index + 1, prefix: prefix, chain: chain, visited: visited, isOwn: isOwn
                    ))
                }

                let key = prefix + node.id
                guard found.add(key, isOwn: isOwn) else { continue }

                if case let .ref(data) = node.kind {
                    if let nested = componentRootID(of: data),
                       let nestedStep = componentStep(
                           componentID: nested, prefix: key + String(NodeAddress.separator),
                           chain: chain + [node.id], visited: visited, isOwn: isOwn
                       )
                    {
                        stack.append(nestedStep)
                    }
                    continue
                }
                let refill = injectedChildren(of: node.id, insideInstances: chain)
                let ownFill = isOwn || (refill != nil && injectedChildrenAreOwn(of: node.id, insideInstances: chain))
                let nextItems = refill ?? node.kind.inlineChildren
                if !nextItems.isEmpty {
                    stack.append(.injected(
                        items: nextItems, index: 0, prefix: prefix, chain: chain, visited: visited, isOwn: ownFill
                    ))
                }
            }
        }
    }
}
