//
//  EditableDocument+ComponentLoops.swift
//  Woodcase
//

import Foundation

/// The component loops a document holds, and the expansion rule every walk that mirrors
/// ``PenRefExpander`` follows around them. See ``ComponentLoop``.
public extension EditableDocument {
    /// The component loops the document holds now — components that contain each other,
    /// directly or through others — each with its cycle in render order.
    ///
    /// Empty for every document an edit made: ``apply(_:)`` refuses an edit that would
    /// close a loop. A file can still arrive with one; it reads, and the nesting among a
    /// loop's members is not expanded.
    var componentLoops: [ComponentLoop] {
        componentLoopIndex.loops { id in componentNode(id)?.common.name ?? id }
    }
}

extension EditableDocument {
    /// The component graph's loops, memoized with the expansion cache — they change
    /// exactly when an expansion can.
    var componentLoopIndex: ComponentLoopIndex {
        if _expansionCache == nil {
            _expansionCache = ExpansionCache()
        }
        if let cached = _expansionCache?.componentLoops { return cached }
        let ids = Set(componentRegistry.keys).union(importedStore.reusables.keys)
        var edges: [String: [String]] = [:]
        for id in ids {
            edges[id] = componentsRendered(inComponent: id)
        }
        let index = ComponentLoopIndex(edges: edges)
        _expansionCache?.componentLoops = index
        return index
    }

    /// Whether an instance of `target` stays unexpanded on this chain, as the expansion
    /// leaves it: the component, or a member of its loop, is on the chain already.
    ///
    /// - Parameters:
    ///   - target: The component a `ref` names.
    ///   - chain: The component ids on the expansion chain.
    /// - Returns: `true` when the `ref` is left as written.
    func closesComponentLoop(entering target: String, onChain chain: Set<String>) -> Bool {
        if chain.contains(target) { return true }
        guard !chain.isEmpty else { return false }
        return componentLoopIndex.closesLoop(entering: target, onChain: chain)
    }

    /// Every component id rendered anywhere in a component's subtree — the document's
    /// own or an imported one — unfiltered and possibly repeated.
    ///
    /// - Parameter id: The component's id.
    /// - Returns: The ids.
    private func componentsRendered(inComponent id: String) -> [String] {
        var rendered: [String] = []
        var pending = [id]
        while let current = pending.popLast() {
            guard let node = componentNode(current) else { continue }
            rendered += node.renderedComponentIDs
            pending += componentChildIDs(of: current)
        }
        return rendered
    }
}

extension EditableDocument {
    /// Whether every instance of a chain is one the expansion expands, given the
    /// component loops it passes.
    ///
    /// A chain is resolved one element at a time, so ``componentRoot(ofInstanceChain:)``
    /// otherwise reads only its innermost element — which is the whole answer until a
    /// loop is in play, because then an instance the chain steps through may be one the
    /// expansion leaves as written. A document with no loop pays one memoized look at its
    /// component graph.
    ///
    /// - Parameter chain: The `ref` node ids, outermost first.
    /// - Returns: `false` when some element stays unexpanded on the chain above it.
    func expandsAcrossComponentLoops(_ chain: [String]) -> Bool {
        guard chain.count > 1, componentLoopIndex.hasLoops else { return true }
        var passed: Set<String> = []
        for index in chain.indices {
            let outer = Array(chain[..<index])
            var payload = effectiveRefData(of: chain[index], insideInstances: outer)
            if payload == nil, case let .ref(injected)? = injectedNodes(insideInstances: outer)[chain[index]]?.node.kind {
                payload = injected
            }
            guard let payload, let placed = componentPlacement(of: payload, onChain: passed) else { return false }
            passed = placed.chain
        }
        return true
    }
}

public extension EditableDocument {
    /// Records the component loops the document holds on its ``readContext``, as a read
    /// of a file does.
    ///
    /// A loop is a design error the reader cannot fix and must not hide: the file opens,
    /// the nesting each loop closes is not expanded, and the read context carries the
    /// loops for whoever opened it to report — an editor's alert, the CLI's `error:` line
    /// on standard error. The library itself prints nothing.
    func recordComponentLoopsOnRead() {
        let loops = componentLoops
        guard !loops.isEmpty else { return }
        var context = readContext
        context.componentLoops = loops
        readContext = context
    }
}
