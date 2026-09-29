//
//  TreeView.swift
//  Woodcase
//

import Foundation

/// The settled tree read: one ``TreeRow`` per node, in pre-order.
///
/// This is the cheap structural answer that a screenshot is usually standing in for.
/// Every rect on it is computed by the layout engine after ref expansion and variable
/// resolution for the chosen theme, so a read taken straight after a write reports
/// settled geometry, never an authored size.
///
/// ```swift
/// let rows = try TreeView.rows(of: document, depth: 2)
/// print(TreeFormatter.text(rows))
/// // frame      Card         0,0 200×100               Card1
/// // rectangle    overflows  160,20 80×40   ⚠ partial  Ovr01
/// ```
///
/// Component instances are one row by default — a `ref` is a node like any other.
/// Pass `expandInstances: true` to walk into them; those rows are addressed by the
/// id-path (`"Nav01/Bdg01/Cnt01"`) that
/// ``EditableDocument/resolve(_:tags:)-(String,_)`` accepts and an override writes to.
/// A `ref` to a component the chain is already inside — a component placing itself,
/// two placing each other — is circular: the expansion leaves it as written, and so
/// does the read, as one `ref` row with nothing below it.
///
/// An expanded instance shows what it puts in a **slot**. The children an instance
/// writes into a component's slot frame live in its `descendants` map rather than in
/// the document's tree, and they get id-path rows like every other node inside the
/// instance — including a `ref` among them, which expands in turn. Those ids are
/// addresses: ``EditableDocument/resolve(_:tags:)-(String,_)`` accepts them, `get`
/// answers them and `override` writes to them, storing the write on the instance under
/// the key ``PenRefExpander`` applies. What a slot *holds* is still one value — adding,
/// removing or reordering an injected child means writing the slot frame's `children`
/// again.
public enum TreeView {
    /// Reads the document — or one subtree of it — as settled rows.
    ///
    /// - Parameters:
    ///   - document: The document to read.
    ///   - root: The address of the subtree to read, in any form
    ///     ``EditableDocument/resolve(_:tags:)-(String,_)`` accepts. `nil` reads every
    ///     root node in ``EditableDocument/rootOrder``.
    ///   - depth: How many levels below the root to descend. `0` lists the root rows
    ///     alone, `nil` descends without limit. A row whose children are left out
    ///     still reports its ``TreeRow/childCount``.
    ///   - expandInstances: Whether to descend into component instances. When `false`
    ///     a `ref` is a single row of type `"ref"`.
    ///   - theme: Theme axes to pin for variable resolution, merged over the
    ///     document's default theme. `nil` uses the default theme.
    ///   - properties: Property paths — the ``NodePropertyCodec`` vocabulary — to
    ///     read onto each row, in the order given.
    /// - Returns: The rows, in pre-order.
    /// - Throws: ``EditingError/addressNotFound(address:nearMisses:)`` or
    ///   ``EditingError/ambiguousAddress(address:candidates:)`` when `root` names no
    ///   single node. An address that matches nothing is an error, never an empty
    ///   listing.
    public static func rows(
        of document: EditableDocument,
        root: String? = nil,
        depth: Int? = nil,
        expandInstances: Bool = false,
        theme: [String: String]? = nil,
        properties: [String] = []
    ) throws -> [TreeRow] {
        try rows(
            of: document,
            settled: SettledTree(document: document, theme: theme ?? [:]),
            root: root,
            depth: depth,
            expandInstances: expandInstances,
            properties: properties
        )
    }

    /// Reads rows from a tree that has already been settled.
    ///
    /// The only difference from ``rows(of:root:depth:expandInstances:theme:properties:)``
    /// is who runs the pipeline. A caller that needs the settled nodes *as well as* the
    /// rows — ``DocumentLinter``, which reads a node's fills and sizings beside its rect
    /// and clip flag — builds the ``SettledTree`` once and passes it here, rather than
    /// laying the document out twice. `WoodcaseScripting` does the same across a whole
    /// script run: one settle per theme, brought up to date root by root after a write.
    ///
    /// - Parameters:
    ///   - document: The document the rows describe.
    ///   - settled: The already-settled tree, built for the theme the caller wants.
    ///   - root: The address of the subtree to read, or `nil` for every root node.
    ///   - depth: How many levels below the root to descend; `nil` for all of them.
    ///   - expandInstances: Whether to descend into component instances.
    ///   - properties: Property paths to read onto each row.
    /// - Returns: The rows, in pre-order.
    /// - Throws: ``EditingError/addressNotFound(address:nearMisses:)`` or
    ///   ``EditingError/ambiguousAddress(address:candidates:)`` when `root` names no
    ///   single node.
    package static func rows(
        of document: EditableDocument,
        settled: SettledTree,
        root: String? = nil,
        depth: Int? = nil,
        expandInstances: Bool = false,
        properties: [String] = []
    ) throws -> [TreeRow] {
        let context = Context(
            document: document,
            settled: settled,
            limit: depth,
            expandInstances: expandInstances,
            properties: properties
        )

        // Pre-order from a work list rather than by recursion: a debug build's frame for
        // one row is several kilobytes, and a deep tree overflowed a Swift task's stack
        // (`project/2026-09-26-debug-stack-depth.md`).
        var rows: [TreeRow] = []
        var pending = try starts(in: document, root: root).reversed().map {
            Visit(source: $0.source, prefix: $0.prefix, scope: $0.scope, depth: 0, parentRect: nil)
        }
        while let next = pending.popLast() {
            pending.append(contentsOf: visit(next, context: context, into: &rows).reversed())
        }
        return rows
    }

    // MARK: - Walk

    /// Everything the walk needs that does not change from node to node.
    private struct Context {
        let document: EditableDocument
        let settled: SettledTree
        let limit: Int?
        let expandInstances: Bool
        let properties: [String]
    }

    /// Where one walk begins: a node, the chain of `ref` ids it sits inside (outermost
    /// first, empty in the document's own tree), and what that chain carries down.
    private struct Start {
        let source: Source
        let prefix: [String]
        let scope: InstanceScope
    }

    /// The nodes the listing starts from.
    ///
    /// A root inside an instance may name a child the instance *injected*, which the
    /// flat store has no entry for — the walk has to carry the node itself, exactly as
    /// it does for such a row reached from above.
    private static func starts(in document: EditableDocument, root: String?) throws -> [Start] {
        guard let root else {
            return document.rootOrder.map { Start(source: .stored($0), prefix: [], scope: .document) }
        }
        switch try document.resolve(root) {
        case let .node(id):
            return [Start(source: .stored(id), prefix: [], scope: .document)]
        case let .instanceDescendant(refID, key):
            let steps = key.split(separator: NodeAddress.separator).map(String.init)
            guard let last = steps.last else {
                return [Start(source: .stored(refID), prefix: [], scope: .document)]
            }
            let prefix = [refID] + steps.dropLast()
            let injected = document.injectedNodes(insideInstances: prefix)[last]
            return [Start(
                source: injected.map { Source.injected($0.node) } ?? .stored(last),
                prefix: prefix,
                scope: scope(insideInstances: prefix, document: document)
            )]
        }
    }

    /// One node the walk has still to list, and where it sits.
    private struct Visit {
        let source: Source
        let prefix: [String]
        let scope: InstanceScope
        let depth: Int
        let parentRect: PenRect?
    }

    /// Appends the row for one node.
    ///
    /// - Returns: The node's children to list next, in order; none when the depth limit
    ///   or an unexpanded instance stops the walk here.
    private static func visit(
        _ entry: Visit,
        context: Context,
        into rows: inout [TreeRow]
    ) -> [Visit] {
        let (source, prefix, depth) = (entry.source, entry.prefix, entry.depth)
        let separator = String(NodeAddress.separator)
        let nodeID = source.nodeID
        let settledID = (prefix + [nodeID]).joined(separator: separator)

        // A `ref` is replaced by the component's root, which keeps its own id under
        // the prefix — so the rect and the children live one level deeper than the id.
        // Which component that is depends on the instances the node sits inside: one
        // of them may have repointed it, and the expansion this rect map came from
        // honored that. A ref back to a component on the chain is left as written.
        let placement = placement(of: source, in: entry.scope, document: context.document)
        let componentRoot = placement.componentRootID
        let rectID = componentRoot.map { "\(settledID)\(separator)\($0)" } ?? settledID

        // The settled node, or the authored one when expansion replaced it — which is
        // exactly the `ref` case, so a ref row describes the ref, not the component.
        // An injected node carries its own authored form, because the store has none.
        let authored = source.authoredNode ?? context.document.componentNode(nodeID)
        guard let node = context.settled.nodes[settledID] ?? authored else { return [] }

        // The revision is the one a write to this row's address has to quote. Inside an
        // expanded instance that is the outermost ref's, because an override to this
        // target is stored there — the same node `NodeLookup` takes it from for `get`,
        // so the two reads cannot disagree about the same address.
        guard let rev = context.document.revision(of: prefix.first ?? nodeID) else { return [] }

        let rect = context.settled.rects[rectID]
        let children = if case .circular = placement {
            [Source]()
        } else {
            childSources(of: source, componentRoot: componentRoot, prefix: prefix, in: context.document)
        }
        let isInstance = isRef(node.kind)
        let rowOverflow = overflow(of: rect, in: entry.parentRect)

        rows.append(TreeRow(
            id: settledID,
            address: prefix.isEmpty ? context.document.namePath(of: nodeID) : settledID,
            rev: rev,
            depth: depth,
            type: node.kind.typeName,
            name: node.common.name,
            rect: rect,
            absRect: context.settled.absoluteRects[rectID],
            clip: rowOverflow.clip,
            overflowAxes: rowOverflow.axes,
            isReusable: node.common.reusable == true,
            isInstance: isInstance,
            isSlot: isSlot(node.kind),
            childCount: children.count,
            properties: propertyColumns(of: node, paths: context.properties)
        ))

        if let limit = context.limit, depth >= limit { return [] }
        if isInstance, !context.expandInstances { return [] }

        let (childPrefix, childScope) = if case let .instance(_, inner) = placement {
            (prefix + [nodeID], inner)
        } else {
            (prefix, entry.scope)
        }
        // A group has no box to clip its children to, and its rect is their union measured
        // from its anchor, not from its corner: nothing under a group is outside it.
        let clipRect = if case .group = node.kind { PenRect?.none } else { rect }
        return children.map {
            Visit(source: $0, prefix: childPrefix, scope: childScope, depth: depth + 1, parentRect: clipRect)
        }
    }

    // MARK: - Pieces

    /// Whether a kind is a component instance.
    private static func isRef(_ kind: PenNode.Kind) -> Bool {
        if case .ref = kind { return true }
        return false
    }

    /// Whether a kind is a slot frame — a frame a component definition marks with
    /// `slot`, which an instance's descendant overrides fill. A frame's `slot` is
    /// `nil` when it is not a slot, and the (possibly empty) array of accepted types
    /// otherwise — so presence, not emptiness, is what marks it.
    private static func isSlot(_ kind: PenNode.Kind) -> Bool {
        guard case let .frame(data) = kind else { return false }
        return data.slot != nil
    }

    /// How much of a child's rect falls outside its parent's box, and which axes.
    ///
    /// Both rects are in the parent's coordinate space, so the parent's box is
    /// `(0, 0, width, height)`. Every comparison carries ``TreeRow/clipTolerance`` of
    /// slack, because a settled edge that lands *on* its parent's edge lands a few
    /// parts in 10¹³ past it as often as on it, and neither is a clipped design. A row
    /// with no parent, or with no rect of its own, is ``TreeRow/Clip/none`` with no
    /// axes.
    /// Axes are listed in ``TreeRow/OverflowAxis``'s case order (see ``TreeRow/overflowAxes``).
    private static func overflow(
        of rect: PenRect?,
        in parent: PenRect?
    ) -> (clip: TreeRow.Clip, axes: [TreeRow.OverflowAxis]) {
        guard let rect, let parent else { return (.none, []) }
        let slack = TreeRow.clipTolerance
        let insideX = rect.x >= -slack && rect.x + rect.width <= parent.width + slack
        let insideY = rect.y >= -slack && rect.y + rect.height <= parent.height + slack
        if insideX, insideY { return (.none, []) }

        var axes: [TreeRow.OverflowAxis] = []
        if !insideX { axes.append(.horizontal) }
        if !insideY { axes.append(.vertical) }

        let overlapsX = rect.x < parent.width - slack && rect.x + rect.width > slack
        let overlapsY = rect.y < parent.height - slack && rect.y + rect.height > slack
        let clip: TreeRow.Clip = overlapsX && overlapsY ? .partial : .full
        return (clip, axes)
    }

    /// The requested property columns for one node.
    ///
    /// A path that is not a property of this node's kind is left out — the column is
    /// simply not applicable here — while a path that is a property but unset is
    /// present as ``AnyCodable/null``.
    private static func propertyColumns(of node: PenNode, paths: [String]) -> [String: AnyCodable]? {
        guard !paths.isEmpty else { return nil }
        var columns: [String: AnyCodable] = [:]
        for path in paths {
            if let value = try? NodePropertyCodec.value(at: path, of: node) {
                columns[path] = value
            }
        }
        return columns
    }
}
