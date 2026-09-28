//
//  EditableDocument+Injected.swift
//  Woodcase
//

import Foundation

/// The children an instance writes into a component's slot frame.
///
/// A slot fill is a `children` entry in the instance's `descendants` map: inline .pen
/// JSON for nodes that live in no store, and that the expansion is the first thing to
/// give an id. Every reader that has to agree about what an instance actually contains
/// — the tree walk, the address resolver, the override guard, the name path — asks
/// here, so there is one answer to "what did this instance put in that slot" rather
/// than one answer per caller. A second list is exactly what once told writers a slot
/// fill would never be read while ``PenNodePatcher`` was busy applying it.
public extension EditableDocument {
    /// A node an instance injected, and where it sits by name inside that instance.
    struct InjectedNode: Friendly {
        /// The node exactly as the override writes it.
        public var node: PenNode

        /// The name-path segments from just below the component root down to the node,
        /// the slot frame it was injected into included.
        public var segments: [String]

        /// Creates an injected node.
        ///
        /// - Parameters:
        ///   - node: The node as the override writes it.
        ///   - segments: Its name-path segments within the instance.
        public init(node: PenNode, segments: [String]) {
            self.node = node
            self.segments = segments
        }
    }

    /// The children an instance writes into one node, or `nil` when none does.
    ///
    /// A `children` entry in a `descendants` map *replaces* the node's own subtree when
    /// the instance expands — which is how a component's slot frame is filled.
    ///
    /// Two overrides can carry them, and they are read in the order ``PenRefExpander``
    /// applies them: the instance the node sits *directly* inside, keyed by the node's
    /// own id, and then the outermost instance keyed by the whole id path — the
    /// cross-ref form, applied after expansion, which therefore wins. The inner one is
    /// read from the node's payload when the enclosing ref is itself injected, because
    /// then there is no node in the flat store to ask.
    ///
    /// - Parameters:
    ///   - nodeID: The node being filled, by the id its instance's map keys it under.
    ///   - chain: The `ref` node ids it sits inside, outermost first. Empty in the
    ///     document's own tree, where no override reaches.
    /// - Returns: The children as written, or `nil` when no override names any.
    func injectedChildren(of nodeID: String, insideInstances chain: [String]) -> [PenNode]? {
        guard let outermost = chain.first, let innermost = chain.last else { return nil }
        let outer = Array(chain.dropLast())
        var found: [PenNode]?
        if let override = refData(of: innermost, insideInstances: outer)?.descendants?[nodeID] {
            found = Self.children(of: override) ?? found
        }
        guard chain.count > 1 else { return found }

        let crossKey = (chain.dropFirst() + [nodeID])
            .joined(separator: String(NodeAddress.separator))
        if let override = effectiveRefData(of: outermost, insideInstances: [])?
            .descendants?[crossKey]
        {
            found = Self.children(of: override) ?? found
        }
        return found
    }

    /// Whether the children ``injectedChildren(of:insideInstances:)`` answers were
    /// written by the chain's outermost instance itself.
    ///
    /// They are when that instance's own `descendants` map carries them — keyed by the
    /// node's id when the chain is the instance alone, by the cross-ref path otherwise.
    /// Pen lets no key of that instance reach them.
    ///
    /// - Parameters:
    ///   - nodeID: The filled node, by the id its instance's map keys it under.
    ///   - chain: The `ref` node ids it sits inside, outermost first.
    /// - Returns: `true` when the outermost instance wrote the fill.
    func injectedChildrenAreOwn(of nodeID: String, insideInstances chain: [String]) -> Bool {
        guard let outermost = chain.first else { return false }
        let key = (chain.dropFirst() + [nodeID]).joined(separator: String(NodeAddress.separator))
        guard let override = effectiveRefData(of: outermost, insideInstances: [])?.descendants?[key] else {
            return false
        }
        return Self.children(of: override) != nil
    }

    /// Every node injected anywhere inside one instance chain, by id.
    ///
    /// The walk descends the component the chain's innermost `ref` places, and wherever
    /// an override fills a node it takes the injected children *instead of* the node's
    /// own subtree — the substitution the expansion makes. It does not step through a
    /// nested `ref`: the nodes inside one belong to a longer chain, and answer to a
    /// longer key.
    ///
    /// - Parameter chain: The `ref` node ids, outermost first.
    /// - Returns: Injected node id → the node and its name-path segments. Empty for a
    ///   chain that names no component, and for one that injects nothing.
    func injectedNodes(insideInstances chain: [String]) -> [String: InjectedNode] {
        guard let componentID = componentRoot(ofInstanceChain: chain) else { return [:] }
        var result: [String: InjectedNode] = [:]
        collectInjected(below: componentID, of: componentID, chain: chain, into: &result)
        return result
    }

    /// The component root the innermost `ref` of a chain places.
    ///
    /// The flat store answers for a `ref` it holds; a `ref` an instance injected exists
    /// only inside that instance's override, so its payload is read from the node the
    /// enclosing chain injected.
    ///
    /// - Parameter chain: The `ref` node ids, outermost first.
    /// - Returns: The component root's id, or `nil` when the chain is empty or its
    ///   innermost element places no component.
    func componentRoot(ofInstanceChain chain: [String]) -> String? {
        guard let innermost = chain.last else { return nil }
        let outer = Array(chain.dropLast())
        if let stored = componentRootID(placedBy: innermost, insideInstances: outer) {
            return stored
        }
        guard case let .ref(data)? = injectedNodes(insideInstances: outer)[innermost]?.node.kind
        else { return nil }
        return componentRootID(of: data)
    }

    /// The node one `descendants` key names inside an instance.
    ///
    /// A key's last step is a node id, and it is either a node of the component — one
    /// the flat store holds — or one the instance injected, which only the override
    /// carries. An injected node wins over a stored id that happens to match, because
    /// the injected one is what the expansion puts there.
    ///
    /// - Parameters:
    ///   - refNodeID: The instance's `ref` node id.
    ///   - descendantKey: The key inside its `descendants` map.
    /// - Returns: The node the key names, or `nil` when it names nothing.
    func node(ofInstance refNodeID: String, descendantKey: String) -> PenNode? {
        let steps = descendantKey.split(separator: NodeAddress.separator).map(String.init)
        guard let last = steps.last else { return nil }
        let chain = [refNodeID] + steps.dropLast()
        return injectedNodes(insideInstances: chain)[last]?.node ?? componentNode(last)
    }

    /// The full name path of the node an instance injected a child *into*.
    ///
    /// This is the address a caller rewrites to add, remove or reorder a slot's
    /// contents: the children are one `children` value on that node, not nodes with
    /// storage of their own.
    ///
    /// - Parameters:
    ///   - refNodeID: The instance's `ref` node id.
    ///   - descendantKey: The key inside its `descendants` map.
    /// - Returns: The filled node's full name path, or `nil` when the key names a node
    ///   that was not injected.
    func injectionPoint(ofInstance refNodeID: String, descendantKey: String) -> String? {
        let steps = descendantKey.split(separator: NodeAddress.separator).map(String.init)
        guard let last = steps.last else { return nil }
        let chain = [refNodeID] + steps.dropLast()
        guard let injected = injectedNodes(insideInstances: chain)[last] else { return nil }
        return ([namePath(ofInstanceChain: chain)] + injected.segments.dropLast())
            .joined(separator: String(NodeAddress.separator))
    }
}

// MARK: - Walking

extension EditableDocument {
    /// The `ref` payload of a chain element, injected or stored.
    ///
    /// ``effectiveRefData(of:insideInstances:)`` reads the flat store, which has no
    /// entry for a `ref` an instance wrote into a slot — and a component *that* ref
    /// places can have a slot of its own, filled by the injected node's own
    /// `descendants` map.
    private func refData(of nodeID: String, insideInstances chain: [String]) -> PenNode.RefData? {
        if let stored = effectiveRefData(of: nodeID, insideInstances: chain) { return stored }
        guard case let .ref(data)? = injectedNodes(insideInstances: chain)[nodeID]?.node.kind
        else { return nil }
        return data
    }

    /// The full name path of an instance chain: the outermost `ref`, then each nested
    /// step as its own key names it.
    private func namePath(ofInstanceChain chain: [String]) -> String {
        guard let refID = chain.first else { return "" }
        let key = chain.dropFirst().joined(separator: String(NodeAddress.separator))
        return key.isEmpty ? namePath(of: refID) : namePath(ofDescendant: key, in: refID)
    }

    /// Records the nodes injected at or below one node of a component.
    ///
    /// A node an override fills contributes its injected children and nothing else: the
    /// subtree it authored is not in the expansion, so nothing below it can be named.
    ///
    /// Runs from a work list rather than by recursion: this walk reaches as deep as the
    /// component's own tree from its root to whichever slot an instance fills, and a
    /// debug build's per-level stack cost overflows a task's 512 KiB long before a
    /// realistic component would (`project/2026-09-26-debug-stack-depth.md`).
    /// `InjectedStep` carries one pending call's own state, and `drainInjected(_:into:)`
    /// pushes it in the same pre-order the recursive version visited nodes in.
    private func collectInjected(
        below nodeID: String,
        of componentID: String,
        chain: [String],
        into result: inout [String: InjectedNode]
    ) {
        var stack: [InjectedStep] = [.belowVisit(nodeID: nodeID, componentID: componentID, chain: chain)]
        drainInjected(&stack, into: &result)
    }

    // MARK: - The work list

    /// One pending call frame of the injected-node walk, kept on a plain array instead
    /// of the native call stack.
    private enum InjectedStep {
        /// Visiting one node of a component's own tree, on the way down to a slot: the
        /// unit of work `collectInjected(below:of:chain:into:)` once recursed on, once
        /// per real child.
        case belowVisit(nodeID: String, componentID: String, chain: [String])

        /// Resuming `collectInjected(_:base:chain:into:)`'s loop over one list of
        /// injected nodes, from `index`.
        case injected(items: [PenNode], index: Int, base: [String], chain: [String])
    }

    /// Drains a work list of pending steps, in the order the recursive walk once
    /// visited them.
    ///
    /// A node's real children carry no state between them, so `InjectedStep.belowVisit`
    /// simply pushes every child at once, reversed so the first one pops first. A list of
    /// injected nodes resumes by index instead, the same shape
    /// `EditableDocument.drain(_:into:)` uses for the descendant-key walk, because the
    /// dedup against `result` has to see one node at a time in order.
    private func drainInjected(_ stack: inout [InjectedStep], into result: inout [String: InjectedNode]) {
        while let step = stack.popLast() {
            switch step {
            case let .belowVisit(nodeID, componentID, chain):
                if let injected = injectedChildren(of: nodeID, insideInstances: chain) {
                    guard !injected.isEmpty else { continue }
                    let base = nodeID == componentID ? [] : componentSegments(to: nodeID)
                    stack.append(.injected(items: injected, index: 0, base: base, chain: chain))
                    continue
                }
                for childID in componentChildIDs(of: nodeID).reversed() {
                    stack.append(.belowVisit(nodeID: childID, componentID: componentID, chain: chain))
                }

            case let .injected(items, index, base, chain):
                guard index < items.count else { continue }
                let node = items[index]
                if index + 1 < items.count {
                    stack.append(.injected(items: items, index: index + 1, base: base, chain: chain))
                }
                guard result[node.id] == nil else { continue }
                let segments = base + [pathSegment(of: node)]
                result[node.id] = InjectedNode(node: node, segments: segments)
                // A `ref` holds nothing here — the nodes of the component it places sit
                // one chain step deeper, under a longer key.
                if case .ref = node.kind { continue }
                let children = injectedChildren(of: node.id, insideInstances: chain) ?? node.kind.inlineChildren
                if !children.isEmpty {
                    stack.append(.injected(items: children, index: 0, base: segments, chain: chain))
                }
            }
        }
    }

    /// The `children` one override carries, decoded, or `nil` when it names none.
    ///
    /// A whole-node replacement is read the same way: it names `children` or it does
    /// not, and either way the key means what it means to ``PenNodePatcher``.
    ///
    /// - Parameter override: The override to read.
    /// - Returns: The children it writes, or `nil` when it writes none — or writes
    ///   something that is not a list of nodes, which the expansion drops in turn.
    private static func children(of override: PenDescendantOverride) -> [PenNode]? {
        guard let value = override.properties[PenNodePatcher.childrenKey],
              let data = try? JSONEncoder().encode(value),
              let nodes = try? JSONDecoder().decode([PenNode].self, from: data)
        else { return nil }
        return nodes
    }
}
