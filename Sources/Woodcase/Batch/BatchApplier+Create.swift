//
//  BatchApplier+Create.swift
//  Woodcase
//

import Foundation

extension BatchApplier {
    /// Plans an `add`: validate names, settle its ids, place it, insert it.
    ///
    /// An id the subtree supplied is kept; one it left out is drawn. See
    /// ``SubtreeIDPlan``.
    static func planAdd(
        _ op: BatchOperation.AddOp,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> BatchPlan {
        // Refused before anything else: an unnamed node is invisible to every
        // later line, and to the next agent to open the file.
        if let unnamed = firstUnnamedNode(in: op.node, ancestorNames: [], index: nil) {
            throw unnamed
        }
        if let swallowed = firstLiteralRootOverridesKey(in: op.node, ancestorNames: []) {
            throw swallowed
        }
        let parentID = try op.parent.map { try containerID($0, in: document, tags: tags) }
        let plan = try SubtreeIDPlan.keeping(op.node, avoiding: document.allNodeIDs)
        let authored = plan.applied(to: op.node)
        var node = authored
        if parentID == nil {
            node = placedAtRoot(node, in: document, coordinates: .authored)
        }
        return BatchPlan(
            operations: [.insertNode(EditOperation.InsertNode(
                node: node, parentID: parentID, index: op.at
            ))],
            expecting: parentID.map { expecting(op.rev, on: $0) } ?? [:],
            expectedDocumentRevision: parentID == nil ? op.rev : nil,
            createdRootID: node.id,
            actedOnID: node.id,
            divergences: [placement(of: node, from: authored, coordinates: .authored)]
                .compactMap(\.self)
        )
    }

    /// Plans a `replace`: validate names and the root id, settle the ids, swap it in.
    ///
    /// The target's id is what the new root gets, so the ids the *replaced* subtree
    /// holds are struck off the taken set before ``SubtreeIDPlan`` judges the supplied
    /// ones — they are being freed by this very operation, and a caller rebuilding a
    /// node should be able to keep the ids it already published.
    static func planReplace(
        _ op: BatchOperation.ReplaceOp,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> BatchPlan {
        if let unnamed = firstUnnamedNode(in: op.node, ancestorNames: [], index: nil) {
            throw unnamed
        }
        if let swallowed = firstLiteralRootOverridesKey(in: op.node, ancestorNames: []) {
            throw swallowed
        }
        let targetID = try nodeID(op.target, in: document, tags: tags)
        guard op.node.id.isEmpty || op.node.id == targetID else {
            throw BatchError.replacementIDMismatch(
                address: op.target.description, supplied: op.node.id, kept: targetID
            )
        }

        let authored = PenNode(id: targetID, common: op.node.common, kind: op.node.kind, extras: op.node.extras)
        let freed = Set(document.descendantIDs(of: targetID))
        let plan = try SubtreeIDPlan.keeping(authored, avoiding: document.allNodeIDs.subtracting(freed))
        return BatchPlan(
            operations: [.replaceSubtree(EditOperation.ReplaceSubtree(node: plan.applied(to: authored)))],
            expecting: expecting(op.rev, on: targetID),
            createdRootID: targetID,
            actedOnID: targetID
        )
    }

    /// Plans a `cp`: a ref for a reusable source, a deep copy for anything else.
    ///
    /// Unlike an `add`, a copy draws *every* id afresh — keeping the source's would
    /// collide with the source itself.
    ///
    /// This plans the **insert only**. A path-keyed property names a node inside the
    /// copy, which does not exist yet, so those are applied afterwards by
    /// ``performCopy(_:on:tags:recorder:undo:into:)`` — and an `each` list is one insert
    /// per row, planned there for the same reason. Splitting the keys here as well means
    /// a caller that plans a `cp` directly gets the root's properties and no surprises.
    static func planCopy(
        _ op: BatchOperation.CopyOp,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> BatchPlan {
        try planCopyInsert(op, in: document, tags: tags).plan
    }

    /// Plans a `cp`'s insert, and says which id the copy will have.
    ///
    /// The id is what the assignments inside the copy anchor on, and it exists the
    /// moment the plan is made — so it is returned rather than fished back out of an
    /// optional the caller would have to handle.
    ///
    /// - Parameters:
    ///   - op: The copy to plan. Only ``BatchOperation/CopyOp/props`` keyed for the
    ///     copy's root are used; path-keyed ones are the caller's to apply after.
    ///   - document: The document to copy into.
    ///   - tags: Tag name → node id, for a source or parent addressed as `@tag`.
    /// - Returns: The insert's plan, and the id the copy's root will hold.
    /// - Throws: ``EditingError`` from resolving the source or the parent.
    static func planCopyInsert(
        _ op: BatchOperation.CopyOp,
        in document: EditableDocument,
        tags: [String: String]
    ) throws -> (plan: BatchPlan, rootID: String) {
        let rootProperties = CopyAssignment.split(op.props ?? [:]).root
        let sourceID = try nodeID(op.source, in: document, tags: tags)
        let parentID = try op.parent.map { try containerID($0, in: document, tags: tags) }
        guard let source = document.node(id: sourceID) else {
            throw EditingError.nodeNotFound(id: sourceID)
        }

        // Placing a reusable node makes an instance of it, which is what Pen
        // does — duplicating the definition would make a second component.
        var node: PenNode = if source.common.reusable == true {
            PenNode(
                id: PenID.generate(avoiding: document.allNodeIDs),
                common: PenNodeCommon(name: source.common.name),
                kind: .ref(PenNode.RefData(ref: sourceID))
            )
        } else {
            try copied(document.materializeSubtree(rootID: sourceID), into: document)
        }
        let carried = node
        if parentID == nil {
            node = placedAtRoot(node, in: document, coordinates: .copied)
        }

        var operations: [EditOperation] = [.insertNode(EditOperation.InsertNode(
            node: node, parentID: parentID, index: op.at
        ))]
        var divergences: [WriteDivergence] = []
        // A copy's own properties are applied after the insert and win outright, so
        // coordinates passed alongside it settle the placement rather than diverge.
        if !rootProperties.isEmpty {
            try NodePropertyCodec.checkAuthored(rootProperties, on: node)
            operations.append(.setProperties(EditOperation.SetProperties(
                nodeID: node.id, properties: rootProperties
            )))
            divergences += propertyDivergences(rootProperties, on: node, in: document)
        }
        let placedCoordinates = rootProperties["common.x"] == nil && rootProperties["common.y"] == nil
        if placedCoordinates, let moved = placement(of: renamed(node, by: rootProperties), from: carried, coordinates: .copied) {
            divergences.insert(moved, at: 0)
        }

        return (
            BatchPlan(
                operations: operations,
                expecting: parentID.map { expecting(op.rev, on: $0) } ?? [:],
                expectedDocumentRevision: parentID == nil ? op.rev : nil,
                createdRootID: node.id,
                actedOnID: node.id,
                divergences: divergences
            ),
            node.id
        )
    }

    // MARK: - Names

    /// The node as its own line will have named it, for a sentence written before the
    /// line's properties are applied.
    ///
    /// The placement divergence is composed from the copy at plan time, and a
    /// `common.name` given on the same line lands one operation later — so without this
    /// the note named the *source*, the one name the caller is least likely to recognize
    /// as this write's subject (round two of the host trial, agents B and C).
    ///
    /// - Parameters:
    ///   - node: The copy as planned.
    ///   - properties: The root properties the same line applies after the insert.
    /// - Returns: The node with the line's `common.name` on it, or the node unchanged.
    private static func renamed(_ node: PenNode, by properties: [String: AnyCodable]) -> PenNode {
        guard case let .string(name)? = properties["common.name"] else { return node }
        var announced = node
        announced.common.name = name
        return announced
    }

    /// The first node in an authored subtree with no usable name, or `nil`.
    ///
    /// - Parameters:
    ///   - node: The node to check, then its inline children.
    ///   - ancestorNames: The names of the nodes above it, outermost first.
    ///   - index: Its position among its parent's children, or `nil` for the root.
    /// - Returns: The refusal to throw, or `nil` when every node is named.
    static func firstUnnamedNode(
        in node: PenNode,
        ancestorNames: [String],
        index: Int?
    ) -> BatchError? {
        guard let name = node.common.name, !name.isEmpty else {
            var parts = ancestorNames
            if let index { parts.append("[\(index)]") }
            return BatchError.unnamedNode(
                type: node.kind.typeName,
                locator: parts.isEmpty
                    ? "the root of the subtree"
                    : parts.joined(separator: String(NodeAddress.separator))
            )
        }
        for (childIndex, child) in inlineChildren(of: node).enumerated() {
            if let unnamed = firstUnnamedNode(
                in: child, ancestorNames: ancestorNames + [name], index: childIndex
            ) {
                return unnamed
            }
        }
        return nil
    }

    /// A node's inline children, as written in the subtree.
    static func inlineChildren(of node: PenNode) -> [PenNode] {
        switch node.kind {
        case let .frame(data): data.children ?? []
        case let .group(data): data.children ?? []
        default: []
        }
    }

    // MARK: - Root overrides

    /// The key the format has no key for: a `ref`'s root overrides are its own
    /// top-level keys, so `rootOverrides` names something only the codec has.
    static let rootOverridesKey = "rootOverrides"

    /// The first `ref` in an authored subtree that writes a literal `rootOverrides`
    /// key, or `nil`.
    ///
    /// ``PenNode/RefData`` decodes every non-reserved top-level key into
    /// ``PenNode/RefData/rootOverrides``, so by the time a subtree gets here a literal
    /// key is an *entry* in that map named `rootOverrides` — indistinguishable, after
    /// the fact, from an override of a property called `rootOverrides`. No node has
    /// one, so it applies cleanly and changes nothing; refusing it is the only way the
    /// mistake ever gets told.
    ///
    /// - Parameters:
    ///   - node: The node to check, then its inline children.
    ///   - ancestorNames: The names of the nodes above it, outermost first.
    /// - Returns: The refusal to throw, or `nil` when no ref carries the key.
    static func firstLiteralRootOverridesKey(
        in node: PenNode,
        ancestorNames: [String]
    ) -> BatchError? {
        let names = ancestorNames + [node.common.name ?? node.id]
        if case let .ref(data) = node.kind, data.rootOverrides?[rootOverridesKey] != nil {
            return BatchError.literalRootOverridesKey(
                locator: names.joined(separator: String(NodeAddress.separator))
            )
        }
        for child in inlineChildren(of: node) {
            if let found = firstLiteralRootOverridesKey(in: child, ancestorNames: names) {
                return found
            }
        }
        return nil
    }

    // MARK: - Ids

    /// A copy of a subtree with fresh ids that no node in the document holds.
    ///
    /// A `ref` inside the subtree that pointed at another node *in* the subtree
    /// follows the copy; one pointing at a component outside it is left alone.
    ///
    /// - Parameters:
    ///   - node: The subtree to renumber.
    ///   - document: The document it is going into.
    /// - Returns: The subtree with fresh ids.
    static func copied(_ node: PenNode, into document: EditableDocument) -> PenNode {
        SubtreeIDPlan.regenerating(node, avoiding: document.allNodeIDs).applied(to: node)
    }

    // MARK: - Reporting

    /// The tree of names and ids the document now holds under a created root.
    ///
    /// A creating line answers with this, and so does any caller that has changed
    /// something *after* the line ran — a CLI applying properties to a fresh copy —
    /// because the names in the answer must be the names on disk, not the ones the
    /// copy was made with.
    ///
    /// - Parameters:
    ///   - rootID: The id of the created subtree's root.
    ///   - document: The document as it stands now.
    /// - Returns: The name → id tree beneath that root, outermost first.
    public static func createdTree(rootID: String, in document: EditableDocument) -> CreatedNode {
        CreatedNode(
            id: rootID,
            name: document.node(id: rootID)?.common.name,
            children: document.childIDs(of: rootID).map { createdTree(rootID: $0, in: document) }
        )
    }
}
