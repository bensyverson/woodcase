//
//  EditableDocument+SlotMap.swift
//  Woodcase
//

import Foundation

/// The walk that builds a ``SlotMap``: an instance as the expansion prepares it, one
/// level of nesting at a time.
///
/// ``PenRefExpander/prepareInstance(refNode:refData:registry:visited:cache:)`` clones the
/// component an instance places and applies its overrides — fills included, and the keys
/// on nested instances handed down to them — without expanding the instances inside. So
/// a slot frame in the clone holds exactly what the slot shows, and an instance in the
/// clone is still a `ref` that can be prepared in turn. Walking the clones rather than
/// the stored tree means the map cannot disagree with what the expansion draws.
extension EditableDocument {
    /// The slots and nodes of one instance.
    ///
    /// - Parameters:
    ///   - refID: The instance's stored `ref` node.
    ///   - descendants: The `descendants` map to read in place of the stored one — a
    ///     plan's rewrite in progress; `nil` reads the node as it stands.
    /// - Returns: The map, or `nil` when the node is not an instance of a component the
    ///   document can expand.
    func slotMap(of refID: String, descendants: SlotFillLocation.Entries? = nil) -> SlotMap? {
        guard var refNode = nodes[refID], case var .ref(data) = refNode.kind else { return nil }
        if let descendants {
            data.descendants = descendants.isEmpty ? nil : descendants.mapValues { PenDescendantOverride(properties: $0) }
            refNode.kind = .ref(data)
        }
        return slotMap(ofInstance: refNode)
    }

    /// The slots and nodes of an instance the store need not hold — one in a fill, or
    /// one a swap is about to make.
    ///
    /// - Parameter refNode: The `ref` node; its id prefixes every key's expanded id.
    /// - Returns: The map, or `nil` when the node is not an instance of a component the
    ///   document can expand.
    func slotMap(ofInstance refNode: PenNode) -> SlotMap? {
        guard case let .ref(data) = refNode.kind else { return nil }
        let refID = refNode.id
        var walk = SlotMapWalk(
            map: SlotMap(refID: refID),
            entries: (data.descendants ?? [:]).mapValues(\.properties),
            registry: materializedComponents(),
            cache: PenRefExpander.ResolverCache(loops: componentLoopIndex)
        )
        guard walk.visit(instance: refNode, owner: .outermost, keyPrefix: "", parentKey: nil, visited: [])
        else { return nil }
        return walk.map
    }
}

/// One walk of an instance, gathering its ``SlotMap``.
private struct SlotMapWalk {
    /// Whose map a slot's key lives in.
    enum Owner {
        /// The outermost instance's own `descendants`.
        case outermost

        /// The `descendants` of an instance inside a fill at this location.
        case insideFill(SlotFillLocation, instanceID: String)

        /// Where the fill of a slot with this key is stored.
        func location(refID: String, key: String) -> SlotFillLocation {
            switch self {
            case .outermost: SlotFillLocation(refID: refID, key: key)
            case let .insideFill(location, instanceID): location.entering(instance: instanceID, key: key)
            }
        }
    }

    /// One node waiting to be visited.
    struct Pending {
        /// The node, as prepared.
        var node: PenNode
        /// The key of the node it sits in.
        var parentKey: String?
        /// The slot whose content holds it, if any.
        var siteIndex: Int?
        /// Whether it is at the top of that slot's content.
        var isTop: Bool
    }

    /// The map gathered so far.
    var map: SlotMap
    /// The outermost instance's `descendants`, as read.
    let entries: SlotFillLocation.Entries
    /// Component id → component, for the expansion.
    let registry: [String: PenNode]
    /// The expansion's override-key resolvers.
    let cache: PenRefExpander.ResolverCache

    /// Visits one instance: prepares it and walks its clone.
    ///
    /// - Parameters:
    ///   - instance: The `ref` node, its id the expanded path to it.
    ///   - owner: Whose map its slots' keys live in.
    ///   - keyPrefix: The key prefix of its nodes in that map.
    ///   - parentKey: The key of the ref node itself in the outermost map, `nil` for the
    ///     outermost instance.
    ///   - visited: The components already on this expansion chain.
    /// - Returns: `false` when the instance does not expand.
    @discardableResult
    mutating func visit(
        instance: PenNode,
        owner: Owner,
        keyPrefix: String,
        parentKey: String?,
        visited: Set<String>
    ) -> Bool {
        guard case let .ref(data) = instance.kind,
              let prepared = PenRefExpander.prepareInstance(
                  refNode: instance, refData: data, registry: registry, visited: visited, cache: cache
              )
        else { return false }
        let base = instance.id + String(NodeAddress.separator)
        let componentID = String(prepared.node.id.dropFirst(base.count))
        if let parentKey {
            map.nodes[parentKey]?.componentRootID = componentID
        }
        let context = Context(
            owner: owner, keyPrefix: keyPrefix, base: base, componentID: componentID,
            instanceRootID: prepared.node.id, visited: prepared.chainVisited
        )
        var stack = prepared.node.kind.inlineChildren.reversed().map {
            Pending(node: $0, parentKey: parentKey, siteIndex: nil, isTop: false)
        }
        while let next = stack.popLast() {
            stack.append(contentsOf: visit(next, in: context).reversed())
        }
        return true
    }

    /// What one instance's nodes share.
    struct Context {
        /// Whose map its slots' keys live in.
        var owner: Owner
        /// The key prefix of its nodes in that map.
        var keyPrefix: String
        /// The expanded-id prefix the expansion gave its clone.
        var base: String
        /// The component it places.
        var componentID: String
        /// The expanded id of its root.
        var instanceRootID: String
        /// The components on its expansion chain.
        var visited: Set<String>
    }

    /// Records one node and returns what to visit below it.
    private mutating func visit(_ pending: Pending, in context: Context) -> [Pending] {
        let node = pending.node
        let separator = String(NodeAddress.separator)
        let refPrefix = map.refID + separator
        let key = String(node.id.dropFirst(refPrefix.count))
        let localID = String(node.id.dropFirst(context.base.count))
        map.nodes[key] = SlotMap.Node(
            node: node, parentKey: pending.parentKey, siteIndex: pending.siteIndex, localID: localID
        )
        if pending.isTop, let index = pending.siteIndex {
            map.sites[index].contentKeys.append(key)
        }

        if case .ref = node.kind {
            nest(into: node, key: key, localID: localID, siteIndex: pending.siteIndex, context: context)
            return []
        }
        if pending.siteIndex == nil, case let .frame(frame) = node.kind, frame.slot != nil {
            let location = context.owner.location(refID: map.refID, key: context.keyPrefix + localID)
            map.sites.append(SlotMap.Site(
                slotKey: key,
                location: location,
                frame: node,
                componentID: context.componentID,
                componentSlotID: localID,
                instanceRootID: context.instanceRootID,
                contentPrefix: String(key.dropLast(localID.count)),
                isFilled: location.fill(in: entries) != nil
            ))
            let index = map.sites.count - 1
            return node.kind.inlineChildren.map { Pending(node: $0, parentKey: key, siteIndex: index, isTop: true) }
        }
        return node.kind.inlineChildren.map {
            Pending(node: $0, parentKey: key, siteIndex: pending.siteIndex, isTop: false)
        }
    }

    /// Visits an instance met inside another.
    ///
    /// One of the component's own, or one in default content, answers to a longer key
    /// of the same map; one in a fill the instance wrote answers to its own map, inside
    /// that fill.
    private mutating func nest(into node: PenNode, key: String, localID: String, siteIndex: Int?, context: Context) {
        let separator = String(NodeAddress.separator)
        if let siteIndex, map.sites[siteIndex].isFilled {
            visit(
                instance: node, owner: .insideFill(map.sites[siteIndex].location, instanceID: localID),
                keyPrefix: "", parentKey: key, visited: context.visited
            )
        } else {
            visit(
                instance: node, owner: context.owner, keyPrefix: context.keyPrefix + localID + separator,
                parentKey: key, visited: context.visited
            )
        }
    }
}
