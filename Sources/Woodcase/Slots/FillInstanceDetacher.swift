//
//  FillInstanceDetacher.swift
//  Woodcase
//

import Foundation

/// Detaches, in place, the instances of some components that slot fills write.
///
/// A slot fill is inline .pen JSON — the `children` of an entry in a ref's `descendants`
/// map — so an instance written there is no stored node and no ``EditOperation/DetachRef``
/// can reach it. When a delete removes the component it names, it is detached where it
/// stands instead: its JSON is replaced by its expansion one level, exactly as a stored
/// detach writes it (``EditableDocument/detachPlans(deleting:)``). The nested instances of
/// the removed components expand in turn, one that would close a cycle is left out, and
/// the fills the expansion's own instances write are detached by the same rule — so no
/// `ref` survives that names a removed component.
///
/// Every other byte of a fill stays as written, as ``SlotJSON`` keeps it. The ids a
/// detach takes are derived, as a stored detach's are
/// (``SubtreeIDPlan/detaching(_:refID:replica:avoiding:)``), namespaced by the instance's
/// expanded address, so the same document detaches to the same ids.
struct FillInstanceDetacher {
    /// The components whose instances are detached — the ones a delete removes.
    let components: Set<String>

    /// Component id → component, for the expansion.
    let registry: [String: PenNode]

    /// The expansion's override-key resolvers.
    let cache: PenRefExpander.ResolverCache

    /// The collaborative replica doing the detach, or `nil` outside a session.
    let replica: PeerID?

    /// Every id in use, the derived ones added as they are taken.
    var taken: Set<String>

    /// The JSON key naming the component an instance places.
    private static let refKey = "ref"

    /// What becomes of one instance a walk meets.
    private enum Outcome {
        /// It stays as written.
        case keep
        /// Its JSON is replaced.
        case replace(AnyCodable)
        /// It is left out: it would close a cycle, and what it drew goes with the delete.
        case drop
    }

    // MARK: - Fills

    /// A fill's node JSONs with every instance of ``components`` detached, at every depth
    /// of the fill and in the fills its other instances write.
    ///
    /// - Parameters:
    ///   - list: The node JSONs.
    ///   - base: The expanded-id prefix the list's nodes answer to (`Card1/`).
    ///   - found: The address of each instance detached, appended in tree order.
    /// - Returns: The rewritten list.
    mutating func detaching(_ list: [AnyCodable], base: String, found: inout [String]) -> [AnyCodable] {
        detaching(list, base: base, chain: [], found: &found)
    }

    /// The addresses of the instances of some components a fill writes: the instances
    /// ``detaching(_:base:found:)`` would replace.
    ///
    /// - Parameters:
    ///   - components: The components.
    ///   - list: The node JSONs.
    ///   - base: The expanded-id prefix the list's nodes answer to.
    /// - Returns: The addresses, in tree order.
    static func instances(of components: Set<String>, in list: [AnyCodable], base: String) -> [String] {
        var found: [String] = []
        visit(list, base: base, components: components) { _, address in
            found.append(address)
            return .keep
        }
        return found
    }

    /// A tree whose `ref` nodes' fills are detached, as ``detaching(_:base:found:)``.
    ///
    /// - Parameter node: The tree, children inline — an expansion about to be inserted.
    /// - Returns: The tree with its instances' fills rewritten.
    mutating func detachingFills(within node: PenNode) -> PenNode {
        detachingFills(within: node, chain: [])
    }

    // MARK: - Private

    /// ``detaching(_:base:found:)``, carrying the components already expanded on this
    /// chain, so a fill that leads back to one of them ends the walk.
    private mutating func detaching(
        _ list: [AnyCodable], base: String, chain: Set<String>, found: inout [String]
    ) -> [AnyCodable] {
        Self.visit(list, base: base, components: components) { node, address in
            found.append(address)
            return detached(node, address: address, chain: chain)
        }
    }

    /// One instance's replacement: its expansion one level, fills detached, ids derived —
    /// or nothing, for one that names a component already expanded on this chain.
    private mutating func detached(_ json: [String: AnyCodable], address: String, chain: Set<String>) -> Outcome {
        guard let refNode = SlotJSON.node(from: .dictionary(json)), case let .ref(data) = refNode.kind else { return .keep }
        if chain.contains(data.ref) { return .drop }
        var expanded = EditableDocument.removingInstances(
            of: components,
            from: PenRefExpander.expandInstanceLevel(
                refNode: refNode, registry: registry, cache: cache, expandingNestedInstancesOf: components
            )
        )
        expanded = detachingFills(within: expanded, chain: chain.union([data.ref]))
        let plan = SubtreeIDPlan.detaching(expanded, refID: address, replica: replica, avoiding: taken)
        taken.formUnion(plan.ids)
        // Encoding a node the model holds never fails.
        guard let replacement = try? SlotJSON.json(of: plan.applied(to: expanded)) else { return .keep }
        return .replace(replacement)
    }

    /// ``detachingFills(within:)``, carrying the chain.
    private mutating func detachingFills(within node: PenNode, chain: Set<String>) -> PenNode {
        PenTreeRewrite.rewrite(node, context: ()) { current, _ in
            guard case var .ref(data) = current.kind, var descendants = data.descendants else {
                return .descend(current, ())
            }
            var changed = false
            for key in descendants.keys.sorted() {
                guard case let .array(fill)? = descendants[key]?.properties[SlotJSON.childrenKey] else { continue }
                var found: [String] = []
                let rewritten = detaching(fill, base: "\(current.id)\(NodeAddress.separator)", chain: chain, found: &found)
                guard !found.isEmpty else { continue }
                descendants[key]?.properties[SlotJSON.childrenKey] = .array(rewritten)
                changed = true
            }
            guard changed else { return .descend(current, ()) }
            data.descendants = descendants
            return .keep(PenNode(id: current.id, common: current.common, kind: .ref(data), extras: current.extras))
        } ?? node
    }

    /// Walks a fill's node JSONs, handing each instance of `components` to `outcome`,
    /// which answers what becomes of it.
    ///
    /// The walk descends the inline children of every node that is no instance, and the
    /// fills every other instance writes; it never descends an instance of `components`,
    /// whose own fills its detach expands.
    ///
    /// - Parameters:
    ///   - list: The node JSONs.
    ///   - base: The expanded-id prefix the list's nodes answer to.
    ///   - components: The components whose instances `outcome` sees.
    ///   - outcome: Answers what becomes of an instance, given its JSON and address.
    /// - Returns: The list with the replacements made.
    @discardableResult
    private static func visit(
        _ list: [AnyCodable],
        base: String,
        components: Set<String>,
        _ outcome: ([String: AnyCodable], String) -> Outcome
    ) -> [AnyCodable] {
        var result: [AnyCodable] = []
        result.reserveCapacity(list.count)
        let separator = String(NodeAddress.separator)
        for value in list {
            guard case var .dictionary(node) = value, let id = SlotJSON.id(of: value) else {
                result.append(value)
                continue
            }
            if SlotJSON.isRef(node) {
                if case let .string(ref)? = node[refKey], components.contains(ref) {
                    switch outcome(node, base + id) {
                    case .keep: result.append(value)
                    case let .replace(replacement): result.append(replacement)
                    case .drop: break
                    }
                    continue
                }
                guard case var .dictionary(map)? = node[SlotJSON.descendantsKey] else {
                    result.append(value)
                    continue
                }
                for key in map.keys.sorted() {
                    guard case var .dictionary(entry)? = map[key], case let .array(fill)? = entry[SlotJSON.childrenKey]
                    else { continue }
                    entry[SlotJSON.childrenKey] = .array(
                        visit(fill, base: base + id + separator, components: components, outcome)
                    )
                    map[key] = .dictionary(entry)
                }
                node[SlotJSON.descendantsKey] = .dictionary(map)
            } else if let children = SlotJSON.children(of: node) {
                node[SlotJSON.childrenKey] = .array(visit(children, base: base, components: components, outcome))
            }
            result.append(.dictionary(node))
        }
        return result
    }
}
