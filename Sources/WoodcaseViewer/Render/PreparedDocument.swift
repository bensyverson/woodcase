//
//  PreparedDocument.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// A document carried through the pipeline as far as it goes without deciding what to
/// draw: parsed, expanded, resolved for one theme, fonts registered, laid out.
///
/// ```text
/// Parse → Expand → Resolve → Fonts → Layout → **prepared** → Render
/// ```
///
/// This is the expensive half, and the half that does not change when the viewer is
/// asked for a different artboard or a different size — so it is what the
/// ``RenderCache`` keeps warm between requests, keyed by file and theme.
public struct PreparedDocument: Sendable {
    /// Creates a prepared document.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document.
    ///   - generationSource: The document as code generation reads it.
    ///   - expanded: The expanded document, variables still written as `$name`.
    ///   - rects: Settled layout rects by node id.
    ///   - artboards: The top-level frames, in document order.
    ///   - revision: The source document's revision, before expansion.
    ///   - directory: The .pen file's directory, which relative image URLs resolve against.
    public init(
        document: PenDocument,
        generationSource: PenDocument,
        expanded: PenDocument,
        rects: [String: PenRect],
        artboards: [Artboard],
        revision: String,
        directory: URL
    ) {
        self.document = document
        self.generationSource = generationSource
        self.expanded = expanded
        self.rects = rects
        self.artboards = artboards
        self.revision = revision
        self.directory = directory
    }

    /// The expanded, resolved document.
    public let document: PenDocument

    /// The document as code generation reads it — refs unexpanded, variables
    /// unresolved, and every imported component merged in as a root.
    ///
    /// Code generation reads *this*: a ref becomes a component instantiation and a
    /// `$name` becomes a CSS custom property, so running the emitters over the resolved
    /// document would inline every component and hard-code every token. It is
    /// ``Woodcase/EditableDocument/materializeForGeneration()``, the same document
    /// `woodcase generate` emits from, so the code panel shows imported components too.
    public let generationSource: PenDocument

    /// The expanded document with variables still written as `$name`.
    ///
    /// The step between the two above, and the one that says what a node was *authored*
    /// as — which the Details pane needs to tell a literal from a variable. It is kept
    /// rather than recomputed because ``RenderCache`` already makes it on the way to
    /// ``document`` and used to throw it away.
    public let expanded: PenDocument

    /// Settled layout rects by node id.
    public let rects: [String: PenRect]

    /// The top-level frames, in document order.
    public let artboards: [Artboard]

    /// The source document's revision — ``EditableDocument/documentRevision``, taken
    /// before expansion, so it is the same string the activity log and the tree report
    /// carry for this state of the file.
    public let revision: String

    /// The .pen file's directory, which relative image URLs resolve against.
    public let directory: URL

    /// The artboard with an id.
    ///
    /// - Parameter id: The artboard's node id.
    /// - Returns: The artboard, or `nil` if this document has no such top-level frame.
    public func artboard(id: String) -> Artboard? {
        artboards.first { $0.id == id }
    }

    /// The artboard an id names, or the error that says why it names none.
    ///
    /// The two failures are different answers and get different cases: a file that has
    /// artboards says "not that one, here are the ones there are"; a file that has none
    /// says there are none. Splitting them is what stops a message quoting an id nobody
    /// gave it — `'' cannot be rendered`, which is how a brand-new file used to 404.
    ///
    /// - Parameters:
    ///   - id: The artboard's node id.
    ///   - file: The file, for the error.
    /// - Returns: The artboard.
    /// - Throws: ``ViewerError/noArtboards(file:)`` when this document has no top-level
    ///   frames, or ``ViewerError/unknownArtboard(id:file:available:)`` listing the ones
    ///   it does have.
    public func artboard(id: String, of file: ViewerFile) throws -> Artboard {
        if let artboard = artboard(id: id) { return artboard }
        guard !artboards.isEmpty else {
            throw ViewerError.noArtboards(file: file.id)
        }
        throw ViewerError.unknownArtboard(
            id: id, file: file.id, available: artboards.map(\.id)
        )
    }

    /// Which artboards a set of edited nodes sits in.
    ///
    /// The activity log records the ids a write touched, and a page that follows an
    /// identity needs an artboard to move to — so the mapping is made here, from the
    /// settled tree, rather than guessed on the client from a name path.
    ///
    /// A node reached through a component instance carries the id-path expansion gave
    /// it (`Chi01/Lbl01`), while the log records the id as it is written in the file
    /// (`Lbl01`). Both are matched, which is why editing one node inside a definition
    /// names the definition *and* every artboard that places it: all of those renders
    /// really did change.
    ///
    /// Every *step* of that path is an authored id — ``Woodcase/PenRefExpander`` writes
    /// `<ref id>/<node id>` at each level of nesting — so the whole path is matched, not
    /// only its last component. The ref node's own id is the step that used to be
    /// missed: `Chi01` is replaced by `Chi01/Cmp01`, and a write to the bare ref named
    /// no artboard at all, so it moved no follower and lit no unread dot.
    ///
    /// - Parameter nodes: The node ids a write touched.
    /// - Returns: The ids of the artboards containing them, in document order, once
    ///   each. Empty for an unattributed write, which names no nodes at all.
    public func artboardIDs(containing nodes: [String]) -> [String] {
        guard !nodes.isEmpty else { return [] }
        let wanted = Set(nodes)
        return artboards.filter { artboard in
            guard let root = document.children.first(where: { $0.id == artboard.id }) else {
                return false
            }
            return Self.subtree(root, contains: wanted)
        }.map(\.id)
    }

    /// Whether a subtree holds any of the wanted ids.
    private static func subtree(_ node: PenNode, contains wanted: Set<String>) -> Bool {
        if matches(node.id, wanted) { return true }
        return node.kind.inlineChildren.contains { subtree($0, contains: wanted) }
    }

    /// Whether one node's id is one of the wanted ones, as written or as expanded.
    ///
    /// An expanded id is a path of authored ids — the refs it was reached through, then
    /// the node itself — so any step matching is the node, or an instance of it, being
    /// on this artboard.
    private static func matches(_ id: String, _ wanted: Set<String>) -> Bool {
        if wanted.contains(id) { return true }
        guard id.contains("/") else { return false }
        return id.split(separator: "/").contains { wanted.contains(String($0)) }
    }
}
