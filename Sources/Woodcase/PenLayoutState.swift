//
//  PenLayoutState.swift
//  Woodcase
//

import Foundation

/// A laid-out document and everything needed to lay it out again node by node.
///
/// ``PenLayoutEngine/layout(_:textMeasurer:options:)`` answers once and forgets. A state keeps the
/// expanded document, its ``PenLayoutIndex``, every rect, and what the walk remembers of
/// each node's size (the engine's memo: the offer and size of each node's last final
/// call, and a few sizes from measuring calls). With those, a later pass skips every
/// subtree whose content and offered space did not change, so it costs what the edit
/// reaches — the containers on the edited node's spine, each walking its children, most
/// of which answer from memory — rather than the board it sits in.
///
/// Two calls use it:
///
/// - ``update(to:invalidation:)`` commits: it takes the document as edited and the
///   ``PenLayoutInvalidation`` the edits recorded, and lays out what that names.
/// - ``hypothetical(_:)`` previews: it lays out the document as a few
///   ``PenLayoutEdit``s would leave it — a row lifted out of a stack, dropped at another
///   index, a node at another size — on a copy, and returns what would change. The state
///   and the document are untouched; it is a value.
///
/// Both return a ``PenLayoutChange`` that names exactly the rects that differ, and both
/// equal a full layout of the same document bit for bit: `IncrementalLayoutEquivalenceTests`
/// holds ``update(to:invalidation:)`` to that over every fixture and a spread of writes,
/// and `PenLayoutStateTests` holds a hypothetical to the layout after committing it — so
/// a preview hands off to its commit without a flash.
///
/// The state is `Sendable` and not ``Friendly``: it holds the text measurer, a closure.
public struct PenLayoutState: Sendable {
    /// The expanded, resolved document the rects belong to.
    public private(set) var document: PenDocument

    /// Where each node of ``document`` sits.
    public private(set) var index: PenLayoutIndex

    /// Every node's rect, in its parent's coordinates, keyed by expanded id.
    public private(set) var rects: [String: PenRect] = [:]

    /// What the walk remembers of each node's size.
    var memo = PenLayoutEngine.Memo()

    /// The cards the rects were laid out with drawn raw.
    public private(set) var options: PenLayoutOptions

    /// The sizes of the texts the passes have typeset, bounded; every pass measures
    /// through it (design decision 4).
    public let textSizes: TextSizeCache

    /// The measurer every pass uses: ``textSizes``' measurer.
    let textMeasurer: TextMeasurer

    /// The font set's generation when the rects were laid out (``TextSizeCache/fontGeneration``).
    /// When it has moved, every remembered size may be wrong, so the next update lays
    /// out everything.
    private(set) var fontGeneration: Int

    /// Lays a document out in full, measuring text through a new ``TextSizeCache`` of the
    /// default capacity.
    ///
    /// - Parameters:
    ///   - document: An expanded, resolved document, as ``PenLayoutEngine/layout(_:textMeasurer:options:)``
    ///     takes it.
    ///   - textMeasurer: The text measurer behind the state's text cache.
    ///   - options: The cards drawn raw. Defaults to none.
    public init(
        document: PenDocument,
        textMeasurer: @escaping TextMeasurer = PenLayoutEngine.defaultTextMeasurer,
        options: PenLayoutOptions = PenLayoutOptions()
    ) {
        self.init(document: document, textSizes: TextSizeCache(measuring: textMeasurer), options: options)
    }

    /// Lays a document out in full, measuring text through a text cache the caller made.
    ///
    /// - Parameters:
    ///   - document: An expanded, resolved document.
    ///   - textSizes: The text cache every pass of this state measures through, with the
    ///     measurer behind it.
    ///   - options: The cards drawn raw. Defaults to none.
    public init(document: PenDocument, textSizes: TextSizeCache, options: PenLayoutOptions = PenLayoutOptions()) {
        self.document = document
        index = PenLayoutIndex(document)
        self.textSizes = textSizes
        self.options = options
        textMeasurer = textSizes.measurer
        fontGeneration = textSizes.fontGeneration
        Self.pass(over: document, roots: nil, rects: &rects, memo: &memo, textMeasurer: textMeasurer, options: options)
        memo.clearLog()
    }

    /// Lays out again what an invalidation names, and takes the edited document.
    ///
    /// The invalidation is translated to expanded ids against the new document
    /// (``PenLayoutIndex/expandedIDs(for:)``); what each names is forgotten, with its
    /// ancestors, and the roots holding one are walked — every clean subtree on the way
    /// answering from memory. An invalidation of everything lays the document out in full,
    /// and so does any update after a font registration
    /// (``PenFontRegistry/generation`` moved): every remembered size may be wrong. Texts
    /// the state has typeset before are answered by ``textSizes``.
    ///
    /// - Parameters:
    ///   - document: The document as edited, expanded and resolved.
    ///   - invalidation: What the edits since the last update named —
    ///     ``EditableDocument/layoutInvalidation``.
    /// - Returns: What changed against the rects before the call.
    public mutating func update(to document: PenDocument, invalidation: PenLayoutInvalidation) -> PenLayoutChange {
        update(to: document, invalidation: invalidation, options: options)
    }

    /// Lays out again what an invalidation names, with other cards drawn raw, and takes
    /// the edited document.
    ///
    /// As ``update(to:invalidation:)``, and every card that started or stopped being
    /// drawn raw is laid out again too (``PenLayoutOptions/invalidation(from:)``): an
    /// editor passes the cards it draws raw on every update, and a card entering or
    /// leaving editing grows or shrinks back.
    ///
    /// - Parameters:
    ///   - document: The document as edited, expanded and resolved.
    ///   - invalidation: What the edits since the last update named.
    ///   - options: The cards drawn raw from now on.
    /// - Returns: What changed against the rects before the call.
    public mutating func update(
        to document: PenDocument, invalidation: PenLayoutInvalidation, options: PenLayoutOptions
    ) -> PenLayoutChange {
        let invalidation = invalidation.union(options.invalidation(from: self.options))
        self.options = options
        let before = rects
        guard !invalidation.everything, textSizes.fontGeneration == fontGeneration else {
            let oldIndex = index
            self = PenLayoutState(document: document, textSizes: textSizes, options: options)
            let candidates = Set(before.keys).union(rects.keys)
            var change = Self.change(from: before, to: rects, among: candidates, index: index, oldIndex: oldIndex)
            change.affectedRoots = Set(index.roots)
            return change
        }

        var newIndex = index
        var dirty = index.expandedIDs(for: invalidation)
        if !Self.keepsShape(document, of: index, at: dirty) {
            newIndex = PenLayoutIndex(document)
            dirty = newIndex.expandedIDs(for: invalidation)
        }
        for id in dirty {
            memo.forget(id)
        }
        let dirtyRoots = Set(dirty.compactMap { newIndex[$0]?.root })
        var gone = Self.departed(under: dirty, from: index, in: newIndex)
        for id in gone {
            rects.removeValue(forKey: id)
            memo.forget(id)
        }

        memo.clearLog()
        Self.pass(
            over: document, roots: dirtyRoots, rects: &rects, memo: &memo, textMeasurer: textMeasurer, options: options
        )
        gone.formUnion(Self.dropUnplaced(memo.unplaced, index: newIndex, from: &rects))

        let candidates = Set(memo.written).union(gone)
        var change = Self.change(from: before, to: rects, among: candidates, index: newIndex, oldIndex: index)
        change.affectedRoots = dirtyRoots
        change.stats = memo.stats
        memo.clearLog()
        self.document = document
        index = newIndex
        return change
    }

    // MARK: - Passes

    /// Lays out top-level nodes in place over the rects they had.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document.
    ///   - roots: The top-level nodes to walk, by expanded id; `nil` for every one.
    ///   - rects: The rects, updated in place.
    ///   - memo: The walk's memory, read and filled.
    ///   - textMeasurer: The text measurer.
    ///   - options: The cards drawn raw.
    static func pass(
        over document: PenDocument,
        roots: Set<String>?,
        rects: inout [String: PenRect],
        memo: inout PenLayoutEngine.Memo,
        textMeasurer: TextMeasurer,
        options: PenLayoutOptions
    ) {
        for node in document.children where roots?.contains(node.id) ?? true {
            let size = PenLayoutEngine.layoutNode(
                node, availableWidth: nil, availableHeight: nil,
                textMeasurer: textMeasurer, options: options, into: &rects, memo: &memo
            )
            rects[node.id] = PenLayoutEngine.freeRect(
                of: node, x: node.common.x?.literalValue ?? 0, y: node.common.y?.literalValue ?? 0,
                size: size, placedIn: rects
            )
            memo.written.append(node.id)
        }
    }

    /// The most dirty nodes ``keepsShape(_:of:at:)`` checks one by one before it is
    /// cheaper to index the document afresh.
    static let shapeCheckLimit = 64

    /// Whether a document has the tree an index describes, judged at the dirty nodes.
    ///
    /// A node is added, removed or reordered only by an edit that dirties its parent, so a
    /// tree whose top level and whose dirty nodes' child lists are as indexed is the
    /// indexed tree, and the index can be kept — sparing a commit the cost of indexing
    /// every node.
    ///
    /// - Parameters:
    ///   - document: The document as edited.
    ///   - index: The index of the document before.
    ///   - dirty: The dirty expanded ids, as `index` translated them.
    /// - Returns: `false` when the shape differs, or there are too many dirty nodes to
    ///   check cheaply.
    static func keepsShape(_ document: PenDocument, of index: PenLayoutIndex, at dirty: Set<String>) -> Bool {
        guard dirty.count <= shapeCheckLimit, document.children.map(\.id) == index.roots else { return false }
        for id in dirty {
            guard index[id] != nil else { return false }
            let path = index.ancestors(of: id).reversed() + [id]
            guard let node = node(along: path[...], in: document.children) else { return false }
            guard (PenLayoutEngine.nodeChildren(node) ?? []).map(\.id) == index.children(of: id) else { return false }
        }
        return true
    }

    /// The node at the end of a path of ids from the top level down, if there is one.
    private static func node(along path: ArraySlice<String>, in nodes: [PenNode]) -> PenNode? {
        var level = nodes
        var found: PenNode?
        for id in path {
            guard let next = level.first(where: { $0.id == id }) else { return nil }
            found = next
            level = PenLayoutEngine.nodeChildren(next) ?? []
        }
        return found
    }

    /// The nodes of the old tree the new one no longer holds.
    ///
    /// A node leaves only by an edit its old parent's spine records — a delete, a move
    /// out, a retype to a leaf, a ref repointed to another component — so the parent is
    /// dirty, or the node was a top-level one. Reading the old children of every dirty
    /// node, and the old top-level nodes, finds every departure at the cost of what the
    /// edit reaches.
    ///
    /// - Parameters:
    ///   - dirty: The dirty expanded ids, in the new tree.
    ///   - oldIndex: The tree before.
    ///   - newIndex: The tree after.
    /// - Returns: Every departed node, its old subtree included.
    static func departed(under dirty: Set<String>, from oldIndex: PenLayoutIndex, in newIndex: PenLayoutIndex) -> Set<String> {
        var gone: Set<String> = []
        let parents = dirty.filter { oldIndex[$0] != nil }
        for child in parents.flatMap(oldIndex.children(of:)) + oldIndex.roots where newIndex[child] == nil {
            gone.formUnion(oldIndex.subtree(of: child))
        }
        // A node that left keeps no descendant in the new tree unless that one moved
        // elsewhere: keep those.
        return gone.filter { newIndex[$0] == nil }
    }

    /// Drops the rects of every node under a disabled child of a re-laid flex container:
    /// the flow gives them none, and a rect from before the child was disabled must not
    /// survive.
    ///
    /// - Returns: The ids whose rect was dropped.
    static func dropUnplaced(
        _ unplaced: [String], index: PenLayoutIndex, from rects: inout [String: PenRect]
    ) -> Set<String> {
        var dropped: Set<String> = []
        for child in unplaced {
            for id in index.subtree(of: child) where rects.removeValue(forKey: id) != nil {
                dropped.insert(id)
            }
        }
        return dropped
    }
}
