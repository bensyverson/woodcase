//
//  SubtreeIDPlan.swift
//  Woodcase
//

import Foundation

/// The ids a subtree will carry once it is inserted, and the rewrite they imply.
///
/// Settling a subtree's ids is three steps, and a plan is the answer to all three:
///
/// 1. **Validate** the ids that were supplied. Each has to satisfy
///    ``PenID/isValid(_:)`` and be unique — in the document *and* within the
///    subtree, because a subtree can carry two nodes that collide only with each
///    other.
/// 2. **Draw** an id for every node that supplied none, avoiding the document's
///    ids and the supplied ones alike.
/// 3. **Rewrite** the references the first two steps moved: a `ref` pointing at a
///    node in the same subtree, and the `descendants` keys naming that node's
///    descendants. A reference pointing *out* of the subtree is left alone — it
///    names something that did not move.
///
/// Two front doors, because only one of them can refuse:
///
/// - ``keeping(_:avoiding:)`` is what `add` uses. An id an agent wrote is the id
///   the node gets; an id it left out is drawn. Agents are not required to invent
///   ids, but one they do invent is honored rather than silently discarded.
/// - ``regenerating(_:avoiding:)`` is what `cp` and ``PenID/remapIDs(in:)`` use.
///   Every id is drawn afresh, whatever the subtree carries, because a copy that
///   kept its source's ids would collide with the source.
///
/// ```swift
/// let plan = try SubtreeIDPlan.keeping(subtree, avoiding: document.allNodeIDs)
/// let settled = plan.applied(to: subtree)
/// ```
public struct SubtreeIDPlan: Friendly {
    /// Creates a plan from its parts.
    ///
    /// - Parameters:
    ///   - ids: The id each node takes, in traversal order.
    ///   - replacements: Old id → new id, for the ids the plan changed.
    public init(ids: [String], replacements: [String: String]) {
        self.ids = ids
        self.replacements = replacements
    }

    /// The id each node takes, in the order the plan walks the subtree: a node,
    /// then its inline children, outermost first.
    public var ids: [String]

    /// Old id → new id, for every node whose id the plan replaced.
    ///
    /// A node that supplied no id contributes nothing: there was no old id for a
    /// reference to have been written against. This is what step 3 rewrites with,
    /// and what a caller that has to relate the copy back to its source — a detach
    /// building the undo for the subtree it expanded — reports.
    public var replacements: [String: String]

    // MARK: - Planning

    /// Plans the ids for a subtree whose supplied ids are to be honored.
    ///
    /// - Parameters:
    ///   - node: The authored subtree. A node whose `id` is empty supplied none.
    ///   - taken: Every id the document already holds.
    /// - Returns: The plan.
    /// - Throws: ``EditingError/invalidNodeID(id:)`` for a supplied id the format
    ///   does not allow, or ``EditingError/duplicateNodeID(id:)`` for one the
    ///   document already holds or the subtree uses twice.
    public static func keeping(_ node: PenNode, avoiding taken: Set<String>) throws -> SubtreeIDPlan {
        var supplied = Set<String>()
        try validate(node, against: taken, seen: &supplied)
        return draw(node, avoiding: taken.union(supplied), policy: .keepSupplied)
    }

    /// Plans a fresh id for every node in a subtree, supplied or not.
    ///
    /// Nothing here can be refused: no supplied id is honored, so none is judged.
    ///
    /// - Parameters:
    ///   - node: The subtree to renumber.
    ///   - taken: Every id the document already holds.
    /// - Returns: The plan.
    public static func regenerating(_ node: PenNode, avoiding taken: Set<String>) -> SubtreeIDPlan {
        draw(node, avoiding: taken, policy: .regenerateAll)
    }

    // MARK: - Applying

    /// Returns the subtree with its ids settled and its internal references rewritten.
    ///
    /// - Parameter node: The subtree the plan was made for.
    /// - Returns: The same subtree, renumbered.
    /// - Precondition: `node` is the subtree this plan was made for — the walk is
    ///   positional, so a plan does not fit a tree of a different shape.
    public func applied(to node: PenNode) -> PenNode {
        precondition(
            ids.count == Self.nodeCount(of: node),
            "a SubtreeIDPlan can only be applied to the subtree it was planned for"
        )
        var index = 0
        return rewritten(node, index: &index)
    }

    // MARK: - What a plan does with a supplied id

    /// Whether a supplied id is honored or thrown away.
    private enum Policy {
        /// Keep an id the subtree supplied; draw one for a node that supplied none.
        case keepSupplied

        /// Draw an id for every node, whatever the subtree supplied.
        case regenerateAll
    }

    // MARK: - Step 1: validate

    /// Checks every supplied id in a subtree, gathering them as it goes.
    ///
    /// - Parameters:
    ///   - node: The node to check, then its inline children.
    ///   - taken: Every id the document already holds.
    ///   - seen: The supplied ids found so far, which later nodes must not repeat.
    /// - Throws: ``EditingError/invalidNodeID(id:)`` or ``EditingError/duplicateNodeID(id:)``.
    private static func validate(_ node: PenNode, against taken: Set<String>, seen: inout Set<String>) throws {
        if !node.id.isEmpty {
            guard PenID.isValid(node.id) else {
                throw EditingError.invalidNodeID(id: node.id)
            }
            guard !taken.contains(node.id), seen.insert(node.id).inserted else {
                throw EditingError.duplicateNodeID(id: node.id)
            }
        }
        for child in node.kind.inlineChildren {
            try validate(child, against: taken, seen: &seen)
        }
    }

    // MARK: - Step 2: draw

    /// Walks the subtree assigning each node its id.
    ///
    /// - Parameters:
    ///   - node: The subtree.
    ///   - taken: Ids no draw may hit — the document's, plus the supplied ones
    ///     under ``Policy/keepSupplied``.
    ///   - policy: What to do with an id the subtree supplied.
    /// - Returns: The plan.
    private static func draw(_ node: PenNode, avoiding taken: Set<String>, policy: Policy) -> SubtreeIDPlan {
        var plan = SubtreeIDPlan(ids: [], replacements: [:])
        var used = taken
        assign(node, policy: policy, into: &plan, used: &used)
        return plan
    }

    /// Assigns one node's id, then its children's.
    ///
    /// - Parameters:
    ///   - node: The node to assign.
    ///   - policy: What to do with an id it supplied.
    ///   - plan: The plan being built.
    ///   - used: Every id spoken for so far.
    private static func assign(
        _ node: PenNode,
        policy: Policy,
        into plan: inout SubtreeIDPlan,
        used: inout Set<String>
    ) {
        let id: String
        if policy == .keepSupplied, !node.id.isEmpty {
            id = node.id
        } else {
            id = PenID.generate(avoiding: used)
            if !node.id.isEmpty {
                plan.replacements[node.id] = id
            }
        }
        used.insert(id)
        plan.ids.append(id)
        for child in node.kind.inlineChildren {
            assign(child, policy: policy, into: &plan, used: &used)
        }
    }

    // MARK: - Step 3: rewrite

    /// Rebuilds one node with its planned id and rewritten references.
    ///
    /// - Parameters:
    ///   - node: The node to rebuild.
    ///   - index: How far into ``ids`` the walk has got.
    /// - Returns: The rebuilt node.
    private func rewritten(_ node: PenNode, index: inout Int) -> PenNode {
        let id = ids[index]
        index += 1
        return PenNode(id: id, common: node.common, kind: rewritten(node.kind, index: &index), extras: node.extras)
    }

    /// Rebuilds a node's kind: its inline children, and any reference it holds.
    ///
    /// - Parameters:
    ///   - kind: The kind to rebuild.
    ///   - index: How far into ``ids`` the walk has got.
    /// - Returns: The rebuilt kind.
    private func rewritten(_ kind: PenNode.Kind, index: inout Int) -> PenNode.Kind {
        switch kind {
        case var .frame(data):
            data.children = rewritten(data.children, index: &index)
            return .frame(data)

        case var .group(data):
            data.children = rewritten(data.children, index: &index)
            return .group(data)

        case var .ref(data):
            // A ref whose target did not move points out of the subtree, at a
            // component that is staying where it is — and so do its descendant
            // keys, which name nodes inside *that* component.
            guard let target = replacements[data.ref] else { return .ref(data) }
            data.ref = target
            data.descendants = data.descendants.map(rewrittenKeys)
            return .ref(data)

        default:
            return kind
        }
    }

    /// Rebuilds a list of inline children in order.
    ///
    /// - Parameters:
    ///   - children: The children, or `nil` for a container that declares none.
    ///   - index: How far into ``ids`` the walk has got.
    /// - Returns: The rebuilt children, `nil` staying `nil`.
    private func rewritten(_ children: [PenNode]?, index: inout Int) -> [PenNode]? {
        guard let children else { return nil }
        var result: [PenNode] = []
        result.reserveCapacity(children.count)
        for child in children {
            result.append(rewritten(child, index: &index))
        }
        return result
    }

    /// Rewrites the keys of a `descendants` map through ``replacements``.
    ///
    /// A key is one id, or a `/`-separated path of them naming a node inside a
    /// nested instance, so each segment is mapped on its own.
    ///
    /// - Parameter overrides: The map as written.
    /// - Returns: The map with each key's segments remapped where the plan moved them.
    private func rewrittenKeys(
        _ overrides: [String: PenDescendantOverride]
    ) -> [String: PenDescendantOverride] {
        var result: [String: PenDescendantOverride] = [:]
        for (key, override) in overrides {
            let segments = key
                .split(separator: NodeAddress.separator, omittingEmptySubsequences: false)
                .map { replacements[String($0)] ?? String($0) }
            result[segments.joined(separator: String(NodeAddress.separator))] = override
        }
        return result
    }

    // MARK: - Shape

    /// How many nodes an inline subtree holds.
    ///
    /// - Parameter node: The subtree's root.
    /// - Returns: The node and everything inline beneath it.
    private static func nodeCount(of node: PenNode) -> Int {
        1 + node.kind.inlineChildren.reduce(0) { $0 + nodeCount(of: $1) }
    }
}
