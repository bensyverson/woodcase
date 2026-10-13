//
//  PenClip.swift
//  Woodcase
//

import Foundation

/// A self-contained copy of some of a document's nodes: what a copy puts on a pasteboard.
///
/// ``extract(nodeIDs:from:)`` takes the nodes an editor has selected and builds a .pen
/// that needs nothing else to draw:
///
/// - **The copied subtrees**, in document order, each placed at the canvas position it
///   was drawn at. A node under another copied node travels inside it rather than
///   twice.
/// - **Every component they draw** — the one an instance names, the components that one
///   uses, the far end of a ref chain, a component an override repoints to — each as
///   its definition is stored, so a paste can compare it with a definition the target
///   already holds. A component defined inside another travels inside it.
/// - **The variables they use**, the variables those reference, and **the theme axes**
///   those variables and any theme pin need, with every option of each axis.
///
/// A node *inside* an instance is copied as drawn: its expansion, overrides applied,
/// detached from the component under ids derived the way a detach derives them
/// (``SubtreeIDPlan/detaching(_:refID:replica:avoiding:)``). A component an imported
/// library defines comes along as a local definition under its prefixed id
/// (`K:Chip1`), with the library variables it uses (`$K:accent`), so the clip has no
/// `imports`.
///
/// The roots of ``document`` are the copied subtrees, named by ``contentIDs``, followed
/// by the carried definitions. A copied node that is itself a component is content, and
/// is not repeated as a definition.
///
/// ```swift
/// let clip = try PenClip.extract(nodeIDs: selection, from: document)
/// let pen = try PenParser.encodeForFile(clip.document)
/// ```
///
/// The same document and ids always give an equal clip: nothing is drawn at random, and
/// every collection comes out in a fixed order.
public struct PenClip: Friendly {
    /// Creates a clip from its parts.
    ///
    /// - Parameters:
    ///   - document: The clip as a .pen document: the copied roots, then the carried
    ///     definitions.
    ///   - contentIDs: The ids of the roots that were copied, in document order.
    public init(document: PenDocument, contentIDs: [String]) {
        self.document = document
        self.contentIDs = contentIDs
    }

    /// The clip as a .pen document: the copied roots, then the carried definitions,
    /// with the variables and theme axes they need and no `imports`.
    public var document: PenDocument

    /// The ids of the roots that were copied, in document order. Every other root of
    /// ``document`` is a component definition carried along for them.
    public var contentIDs: [String]

    /// Extracts a clip of some nodes of a document.
    ///
    /// - Parameters:
    ///   - nodeIDs: The nodes to copy, as an editor selects them: ids of the expanded
    ///     document (``EditableDocument/expandedID(of:)``), so `Chip1/Lbl01` names a node
    ///     inside an instance and `Chip1/Btn01` the instance itself. A stored node's own
    ///     id, a `ref`'s included, is accepted too. Order and repeats do not matter.
    ///   - document: The document they are in, read with the libraries it imports.
    /// - Returns: The clip.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` for an id that names no node.
    public static func extract(nodeIDs: [String], from document: EditableDocument) throws -> PenClip {
        let order = document.nodeIDsInDocumentOrder()
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let selected = try selection(nodeIDs, in: document, position: position)
        let positioned = placed(copies(of: selected, in: document), of: selected, in: document)
        let definitions = definitions(for: positioned, in: document, position: position)
        let content = renumbered(positioned, apartFrom: definitions, in: document)
        let roots = content + definitions
        let needs = needs(of: roots, in: document)
        return PenClip(
            document: PenDocument(
                version: document.version,
                themes: needs.themes.isEmpty ? nil : needs.themes,
                variables: needs.variables.isEmpty ? nil : needs.variables,
                children: roots
            ),
            contentIDs: content.map(\.id)
        )
    }

    // MARK: - Copies

    /// The copied subtrees, in order: a stored node as stored, a drawn one detached.
    ///
    /// Each detach avoids every id the document and its imports hold, and the ids the
    /// detaches before it took, so no two roots of the clip share an id and the answer
    /// depends only on the document.
    ///
    /// - Parameters:
    ///   - selected: The selection, in document order.
    ///   - document: The source document.
    /// - Returns: One subtree per selected node.
    private static func copies(of selected: [Selected], in document: EditableDocument) -> [PenNode] {
        var taken = Set(document.nodes.keys).union(document.importedStore.nodes.keys)
        return selected.map { node in
            guard let instanceID = node.instanceID else { return node.subtree }
            let plan = SubtreeIDPlan.detaching(node.subtree, refID: instanceID, avoiding: taken)
            taken.formUnion(plan.ids)
            return plan.applied(to: node.subtree)
        }
    }

    /// The copied subtrees, each one that shares an id with a carried definition given
    /// ids of its own.
    ///
    /// That happens when a node copied out of a component's definition is copied beside
    /// an instance of that component: the definition comes along whole, so it holds the
    /// copied node too. The copy is renumbered rather than the definition, which stays as
    /// stored. Its ids are derived as a detach derives them, from the copy's own root, so
    /// the answer is still a function of the document.
    ///
    /// - Parameters:
    ///   - content: The copied subtrees.
    ///   - definitions: The carried definitions.
    ///   - document: The source document.
    /// - Returns: The subtrees, none sharing an id with a definition.
    private static func renumbered(
        _ content: [PenNode],
        apartFrom definitions: [PenNode],
        in document: EditableDocument
    ) -> [PenNode] {
        let defined = Set(definitions.flatMap(subtreeIDs(of:)))
        var taken = Set(document.nodes.keys)
            .union(document.importedStore.nodes.keys)
            .union(defined)
            .union(content.flatMap(subtreeIDs(of:)))
        return content.map { root in
            guard !defined.isDisjoint(with: subtreeIDs(of: root)) else { return root }
            let plan = SubtreeIDPlan.detaching(root, refID: root.id, avoiding: taken)
            taken.formUnion(plan.ids)
            return plan.applied(to: root)
        }
    }
}
