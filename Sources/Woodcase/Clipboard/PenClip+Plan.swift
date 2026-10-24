//
//  PenClip+Plan.swift
//  Woodcase
//

import Foundation

public extension PenClip {
    /// The gap a paste ``PasteTarget/after(siblingID:)`` leaves between the node and the
    /// copies, inside a free container. On the canvas it is ``RootOverlap/margin``.
    static let besideGap: Double = 20

    /// Plans taking this clip into a document: the operations a paste applies, without
    /// applying them.
    ///
    /// - **Ids** are always regenerated, avoiding every id the document and its imported
    ///   libraries hold; every reference inside the paste follows.
    /// - **Components** the clip carries are reused when the document has one with the
    ///   same name and the same definition (``ComponentFingerprints`` says what "same"
    ///   means: node ids, canvas position and the ids of the components it draws do not
    ///   count). A carried component without a name matches by id. Every other carried
    ///   component is inserted as a root, past everything on the canvas; any component
    ///   the paste inserts — carried, or one of the copies — whose name the document
    ///   already holds is renamed (`Button 2`). Instances, `descendants` keys and
    ///   repointed overrides follow the reused or renamed component.
    /// - **Variables** follow the same rule (``PasteVariables``): reused when equal,
    ///   renamed (`primary-2`) when the name is taken by a different one, and every
    ///   `$name` in the paste follows.
    /// - **Theme axes** the document lacks are added; one it has is widened by the
    ///   options it lacks, appended so its first option stays its default.
    /// - **Placement** is the target's (``PasteTarget``) — except for a connection, which
    ///   Pen keeps only at the top level: a copied connector and each one the clip carried
    ///   (``PenClip/connectorIDs``) go in as roots, after the nodes, its ends following
    ///   the copies. One with an end that would name a node neither the paste nor the
    ///   target holds is left out (``PastePlan/droppedConnectorIDs``).
    /// - **Component loops** are refused before anything is planned to be written.
    ///
    /// Apply ``PastePlan/operations`` together, in order — as one ``LocalEdit`` through a
    /// ``DocumentSession``, which makes the paste one undo step.
    ///
    /// - Parameters:
    ///   - document: The document to paste into. It is read, not changed.
    ///   - target: Where the copies go.
    /// - Returns: The plan.
    /// - Throws: ``PasteError``.
    func plan(into document: EditableDocument, at target: PasteTarget) throws -> PastePlan {
        let roots = Dictionary(self.document.children.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let content = try contentIDs.map { id in
            guard let root = roots[id] else { throw PasteError.contentNotInClip(id: id) }
            return root
        }
        let site = try PasteSite(target, in: document)
        let connectors = try connectorIDs.map { id in
            guard let root = roots[id] else { throw PasteError.contentNotInClip(id: id) }
            return root
        }
        let copied = Set(contentIDs).union(connectorIDs)
        let carried = self.document.children.filter { !copied.contains($0.id) }

        let variables = PasteVariables(
            clip: self.document.variables ?? [:],
            target: document.importedDefinitions.variables.merging(document.variables ?? [:]) { _, own in own }
        )
        let theirs = document.materializedComponents()
        let reused = reusedComponents(carried, among: theirs, variables: variables)
        let added = carried.filter { reused[$0.id] == nil }

        var ids = Self.positionalIDs(of: carried, reusing: reused, among: theirs)
        // The nodes in every fill are in use too: Pen renames a repeated id on load, a node
        // in a fill included, so the copies avoid them, and the copies' own fills are
        // renumbered — mapped like any id, so an override key or a connector end naming a
        // node in a fill follows it.
        var taken = document.idsInUse.union(document.importedStore.nodes.keys)
        let plans = (added + content + connectors).map { root in
            let plan = SubtreeIDPlan.regenerating(root, avoiding: taken)
            taken.formUnion(plan.ids)
            ids.merge(plan.replacements) { _, new in new }
            return plan
        }
        let fillRenames = (added + content + connectors).map { root in
            let renames = SlotJSON.fillRenames(in: root, taken: &taken)
            ids.merge(renames) { _, new in new }
            return renames
        }
        let renames = Self.componentRenames(added + content, among: theirs)
        let rewriter = PasteRewriter(
            ids: ids, variables: variables.changes,
            names: Dictionary(renames.map { ($0.id, $0.rename.to) }, uniquingKeysWith: { first, _ in first })
        )
        let settled = try zip(zip(added + content + connectors, plans), fillRenames).map { pair, renames in
            let (root, plan) = pair
            return try SlotJSON.applyingFillRenames(
                renames, to: SubtreeIDPlan(ids: plan.ids, replacements: [:]).applied(to: rewriter.rewrite(root))
            )
        }
        let newDefinitions = Array(settled.prefix(added.count))
        let clipDocument = EditableDocument(from: self.document)
        let ends = ConnectorEnds(
            regenerated: Set(plans.flatMap(\.replacements.keys)), clip: clipDocument, target: document
        )
        let clipRects = Dictionary(
            RootOverlap.roots(in: clipDocument).map { ($0.id, $0.rect) },
            uniquingKeysWith: { first, _ in first }
        )
        // A connection is not placed: Pen keeps it at the top level, wherever the copies go.
        let contentSettled = Array(settled[added.count ..< added.count + content.count])
        let placeable = content.indices.filter { !content[$0].isConnection }
        let copiedConnections = content.indices.filter { content[$0].isConnection }
        let copies = PasteSite.Copies(
            rects: placeable.map { clipRects[contentIDs[$0]] },
            origins: placeable.map { origins?[contentIDs[$0]] },
            sourceDocumentID: sourceDocumentID
        )
        let placed = Self.sized(
            site.placed(placeable.map { contentSettled[$0] }, copies: copies, in: document),
            origins: copies.origins,
            drawn: {
                let sizes = drawnSizes()
                return placeable.map { sizes[$0] }
            },
            in: document
        )
        let connections = ends.keeping(
            copiedConnections.map { contentSettled[$0] }, from: copiedConnections.map { content[$0] }
        )
        let carriedConnectors = ends.keeping(Array(settled.suffix(connectors.count)), from: connectors)
        try Self.refuseComponentLoops(
            content: placed.map(\.node), definitions: newDefinitions, parentIDs: placed.map(\.parentID),
            among: theirs, in: document
        )
        let onCanvas = zip(placed, placeable.map { content[$0] }).filter { $0.0.parentID == nil }
        let placedDefinitions = Self.pastTheCanvas(
            newDefinitions,
            widths: added.map { clipRects[$0.id]?.width ?? 0 },
            occupied: RootOverlap.roots(in: document).map(\.rect)
                + Self.rects(of: onCanvas.map(\.0.node), sized: onCanvas.map(\.1), from: clipRects)
        )

        /// Each copied root's size as the clip draws it.
        func drawnSizes() -> [PenSize?] {
            let laidOut = PenLayoutEngine.layout(PenVariableResolver.resolve(self.document))
            return contentIDs.map { laidOut[$0]?.drawnSize }
        }

        var operations = themeOperations(in: document) + variables.operations
        operations += placedDefinitions.map { .insertNode(EditOperation.InsertNode(node: $0)) }
        operations += placed.map { root in
            .insertNode(EditOperation.InsertNode(node: root.node, parentID: root.parentID, index: root.index))
        }
        // Connections last, as roots: after the nodes their ends name, so the undo takes
        // them out first.
        operations += (connections.nodes + carriedConnectors.nodes).map { node in
            .insertNode(EditOperation.InsertNode(node: node))
        }
        var pastedIDs = Dictionary(uniqueKeysWithValues: zip(placeable, placed.map(\.node.id)))
        for (index, node) in zip(connections.kept, connections.nodes) {
            pastedIDs[copiedConnections[index]] = node.id
        }
        return PastePlan(
            operations: operations,
            insertedRootIDs: content.indices.compactMap { pastedIDs[$0] },
            reusedComponents: reused,
            renamedComponents: renames.map(\.rename),
            reusedVariables: variables.reused,
            renamedVariables: variables.renamed,
            insertedConnectorIDs: carriedConnectors.nodes.map(\.id),
            droppedConnectorIDs: connections.dropped + carriedConnectors.dropped
        )
    }
}
