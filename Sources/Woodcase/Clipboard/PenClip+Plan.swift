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
    /// - **Placement** is the target's (``PasteTarget``).
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
        let copied = Set(contentIDs)
        let carried = self.document.children.filter { !copied.contains($0.id) }

        let variables = PasteVariables(
            clip: self.document.variables ?? [:],
            target: document.importedDefinitions.variables.merging(document.variables ?? [:]) { _, own in own }
        )
        let theirs = document.materializedComponents()
        let reused = reusedComponents(carried, among: theirs, variables: variables)
        let added = carried.filter { reused[$0.id] == nil }

        var ids = Self.positionalIDs(of: carried, reusing: reused, among: theirs)
        var taken = Set(document.nodes.keys).union(document.importedStore.nodes.keys)
        let plans = (added + content).map { root in
            let plan = SubtreeIDPlan.regenerating(root, avoiding: taken)
            taken.formUnion(plan.ids)
            ids.merge(plan.replacements) { _, new in new }
            return plan
        }
        let renames = Self.componentRenames(added + content, among: theirs)
        let rewriter = PasteRewriter(
            ids: ids, variables: variables.changes,
            names: Dictionary(renames.map { ($0.id, $0.rename.to) }, uniquingKeysWith: { first, _ in first })
        )
        let settled = try zip(added + content, plans).map { root, plan in
            try SubtreeIDPlan(ids: plan.ids, replacements: [:]).applied(to: rewriter.rewrite(root))
        }
        let newDefinitions = Array(settled.prefix(added.count))
        let clipRects = Dictionary(
            RootOverlap.roots(in: EditableDocument(from: self.document)).map { ($0.id, $0.rect) },
            uniquingKeysWith: { first, _ in first }
        )
        let copies = PasteSite.Copies(
            rects: contentIDs.map { clipRects[$0] },
            origins: contentIDs.map { origins?[$0] },
            sourceDocumentID: sourceDocumentID
        )
        let placed = Self.sized(
            site.placed(Array(settled.dropFirst(added.count)), copies: copies, in: document),
            origins: copies.origins,
            drawn: { drawnSizes() },
            in: document
        )
        let placedContent = placed.map(\.node)
        try Self.refuseComponentLoops(
            content: placedContent, definitions: newDefinitions, parentIDs: placed.map(\.parentID),
            among: theirs, in: document
        )
        let onCanvas = zip(placed, content).filter { $0.0.parentID == nil }
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
        return PastePlan(
            operations: operations,
            insertedRootIDs: placedContent.map(\.id),
            reusedComponents: reused,
            renamedComponents: renames.map(\.rename),
            reusedVariables: variables.reused,
            renamedVariables: variables.renamed
        )
    }
}
