//
//  SettledTree.swift
//  Woodcase
//

import Foundation

/// The document as it actually renders: refs expanded, variables resolved for a
/// theme, and every node laid out.
///
/// A tree read reports settled values or nothing, never an authored size standing in
/// for a computed one. This runs the pipeline once per read and hands ``TreeView``
/// both halves of the answer: the rect for each node, and the node itself after
/// overrides and variable resolution.
///
/// ## Why not `computeLayout()`
///
/// ``EditableDocument/computeLayout(textMeasurer:)`` takes no theme, and the
/// expansion under it strips reusable component definitions — so a component would
/// have no rect at all, and a themed read would report the default theme's rects.
/// This pipeline is the same one, expanded for ``PenRefExpander/Purpose/canvas``
/// with the theme passed through, and it leaves the document's layout cache
/// untouched: a read has no side effects. Keeping the definitions is also what a design canvas renders. The
/// one place the two pipelines can disagree is a definition sitting *inside* a
/// laid-out container: it stays in the flow here, so its siblings sit where the
/// canvas puts them rather than where an export would.
///
/// ## Node ids after expansion
///
/// ``PenRefExpander`` prefixes every id inside an instance with the ref's id, so a
/// node inside instance `Nav01` is keyed `"Nav01/Lbl01"` — exactly the id-path
/// ``ResolvedNodeAddress/address`` writes for that target. The one exception is the
/// instance's own root, which is keyed `"Nav01/<component root id>"` because the
/// component's root node keeps its own id under the prefix.
/// ## Imports
///
/// An instance of an imported component (`V:Button`) expands from the libraries the
/// document was read with — ``EditableDocument/expanded(for:)`` — so it settles to the
/// component's size here exactly as it draws in `shot`. See <doc:PenImportNamespaces>.
///
/// ## Fonts
///
/// The pipeline registers the document's fonts before it measures anything, through
/// the resolver on its read context and
/// ``GoogleFontResolver/prepareCachedFonts(for:diagnostics:)``. Registration happens
/// inside the resolver, so a face sitting in the on-disk cache is invisible to Core
/// Text until somebody asks for it — and only `shot` and `render` ever did, which is
/// why they and `tree` disagreed about every text width in a Google font. Preparation
/// here is the offline half of that chain: system faces and the cache, never a
/// download, because a read that goes to the network is a read that can hang. A family
/// it cannot place gets one line on standard error naming it and the face the
/// measurement actually used.
/// ## Who may hold one
///
/// `package`, not `public`: settling is an implementation of the read verbs, and the
/// value is only useful to a caller that also holds the ``EditableDocument`` it was
/// built from. `WoodcaseScripting` holds one per theme for the length of a script run
/// — the "a read after a write sees settled layout" rule made cheap — and after a
/// write brings each one up to date with ``init(document:theme:textSizes:reusing:)``,
/// which lays out again only the roots the write could have moved. Nothing outside this
/// package sees the type.
package struct SettledTree {
    /// Every node's layout rect, in its parent's coordinate space, keyed by the
    /// node's post-expansion id.
    package let rects: [String: PenRect]

    /// Every node's layout rect in **document space**, keyed by the node's
    /// post-expansion id.
    ///
    /// ``rects`` is what the layout engine writes: a rect measured from the node's own
    /// parent, so a leaf six levels down reads `0,0` when it sits in its parent's
    /// corner. This is the same map with the origins composed, by the one walk
    /// ``PenLayoutEngine/absoluteRects(under:in:layoutRects:)`` that `shot --outline`
    /// and the viewer's overlay use — never a second hand-rolled sum. Every root node
    /// is a walk of its own, and a root's own rect is already in canvas coordinates,
    /// so the union is the whole document in one frame.
    package let absoluteRects: [String: PenRect]

    /// Every node after expansion and variable resolution, with children stripped,
    /// keyed by its post-expansion id.
    package let nodes: [String: PenNode]

    /// The per-root pieces this tree was assembled from, which a later settle reuses;
    /// `nil` for a tree settled whole.
    package let ledger: Ledger?

    /// Runs the pipeline for one read.
    ///
    /// The document's ``EditableDocument/readContext`` supplies the rest: the libraries
    /// its imported instances expand from, and the resolver its fonts are registered
    /// through before it is measured — ``GoogleFontResolver/shared`` when the command
    /// line read the file, a resolver over a temporary cache in a test, and none at all
    /// for a document built in memory. There is deliberately no default here: a default
    /// is invisible at every call site above it, which is how a test came to measure in
    /// the reader's cached fonts.
    ///
    /// - Parameters:
    ///   - document: The document to settle.
    ///   - theme: Theme axes to pin, merged over the document's default theme.
    ///   - textMeasurer: A function that measures text bounding boxes.
    package init(
        document: EditableDocument,
        theme: [String: String],
        textMeasurer: TextMeasurer = PenLayoutEngine.defaultTextMeasurer
    ) {
        let expanded = document.expanded(for: .canvas)
        let resolved = PenVariableResolver.resolve(expanded, theme: theme)
        document.registerFonts(forSettling: resolved)
        let layoutRects = PenLayoutEngine.layout(resolved, textMeasurer: textMeasurer)
        rects = layoutRects
        absoluteRects = Self.composed(layoutRects, of: resolved)

        nodes = Self.indexed(resolved.children)
        ledger = nil
    }

    /// A tree from maps already assembled — the reusing settle's.
    ///
    /// - Parameters:
    ///   - rects: Every node's parent-relative rect.
    ///   - absoluteRects: Every node's document-space rect.
    ///   - nodes: Every resolved node, children stripped.
    ///   - ledger: The per-root pieces the maps were assembled from.
    init(
        rects: [String: PenRect],
        absoluteRects: [String: PenRect],
        nodes: [String: PenNode],
        ledger: Ledger?
    ) {
        self.rects = rects
        self.absoluteRects = absoluteRects
        self.nodes = nodes
        self.ledger = ledger
    }

    /// Composes every root's subtree into one document-space rect map.
    ///
    /// - Parameters:
    ///   - layoutRects: The engine's parent-relative rects.
    ///   - document: The expanded, resolved document they were computed for.
    /// - Returns: The same nodes, keyed the same way, measured from the canvas origin.
    private static func composed(
        _ layoutRects: [String: PenRect],
        of document: PenDocument
    ) -> [String: PenRect] {
        var absolute: [String: PenRect] = [:]
        for root in document.children {
            absolute.merge(
                PenLayoutEngine.absoluteRects(
                    under: root.id, in: document, layoutRects: layoutRects
                )
            ) { existing, _ in existing }
        }
        return absolute
    }

    /// Indexes a node array and everything under it by id, stripping children so the
    /// index does not hold a copy of every subtree.
    ///
    /// Shared with ``DocumentLinter``, which indexes a second, *unexpanded* resolve of
    /// the same document to read a `ref` — the one node expansion removes before the
    /// resolver can reach it.
    ///
    /// - Parameter nodes: The nodes to index, with their subtrees.
    /// - Returns: Every node in the forest, keyed by id.
    static func indexed(_ nodes: [PenNode]) -> [String: PenNode] {
        // Pre-order from a work list, not recursion, so a deep tree cannot overflow a
        // Swift task's stack in a debug build (`project/2026-09-26-debug-stack-depth.md`).
        // A duplicated id keeps the later node in pre-order, as it always has.
        var index: [String: PenNode] = [:]
        var pending = Array(nodes.reversed())
        while let node = pending.popLast() {
            var stripped = node
            stripped.kind = node.kind.withEmptyChildren()
            index[node.id] = stripped
            if let children = nodeChildren(node) {
                pending.append(contentsOf: children.reversed())
            }
        }
        return index
    }

    /// A node's inline children, or `nil` for a node that cannot have any.
    private static func nodeChildren(_ node: PenNode) -> [PenNode]? {
        switch node.kind {
        case let .frame(data): data.children
        case let .group(data): data.children
        default: nil
        }
    }
}
