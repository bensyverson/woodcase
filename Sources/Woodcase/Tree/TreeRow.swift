//
//  TreeRow.swift
//  Woodcase
//

import Foundation

/// One node of a settled tree read: what it is, where it sits, and how to address it.
///
/// A row is the structural answer that replaces a screenshot. Everything on it is
/// settled — the rect comes from the layout engine after ref expansion and variable
/// resolution, not from the node's authored size — so a reader never sees a
/// pre-layout value.
///
/// ``TreeView/rows(of:root:depth:expandInstances:theme:properties:)`` produces rows;
/// ``TreeFormatter`` renders them.
///
/// ## Identity versus address
///
/// ``id`` is the unique handle for the row: a node's own id in the document's tree,
/// and the `refID/descendantKey` id-path for a node inside an expanded component
/// instance. ``address`` is what a later command should pass: the node's name path
/// (`"Dashboard/Header/Title"`) for a node in the document's own tree, and the same
/// id-path for an instance descendant. Both resolve through
/// ``EditableDocument/resolve(_:tags:)-(String,_)``, and for an instance descendant
/// they are equal.
public struct TreeRow: Friendly {
    /// The slack, in points, a settled rect is allowed outside its parent before it
    /// counts as clipped.
    ///
    /// A hundredth of a point is far below anything a design means — no renderer, and
    /// no reader, can tell it from nothing — and far above the residue of laying out a
    /// flex distribution in binary floating point. Fifty-nine `fill_container` bars at
    /// gap 1 across a 350-point frame divide it exactly, and the last bar's right edge
    /// lands a few parts in 10¹³ past 350; without this tolerance the whole row read as
    /// a clipped design.
    ///
    /// It is one constant on purpose: ``clip`` is computed with it once, and
    /// `DocumentLinter`'s `clipped` check reads the flag rather than deciding again, so
    /// `tree` and `lint` cannot disagree about the same node.
    public static let clipTolerance: Double = 0.01

    /// How much of the row's rect falls outside its parent's.
    ///
    /// Purely geometric: the child's rect is compared with the box
    /// `(0, 0, parent.width, parent.height)` in the parent's own coordinate space,
    /// regardless of whether the parent actually clips, and with ``clipTolerance``
    /// of slack on every edge. A row with no parent — a root of the walk — is always
    /// ``none``.
    public enum Clip: String, Friendly {
        /// The rect lies entirely within its parent.
        case none

        /// The rect crosses at least one edge of its parent.
        case partial

        /// The rect lies entirely outside its parent, so nothing of it shows.
        case full
    }

    /// One axis a row's rect can extend past its parent's box on.
    ///
    /// The same two values ``PenNode/FrameData/layout`` uses for a frame's own
    /// stacking direction, and the same two values `common.metadata._scroll`
    /// accepts to declare a designed scroll axis — the vocabulary composes because
    /// all three answer the same question: horizontal or vertical.
    public enum OverflowAxis: String, Friendly, CaseIterable {
        /// The x axis: the rect's left or right edge falls outside its parent's.
        case horizontal

        /// The y axis: the rect's top or bottom edge falls outside its parent's.
        case vertical
    }

    /// The row's unique handle: a node id, or a `refID/descendantKey` id-path inside
    /// an expanded instance.
    public let id: String

    /// The address to pass to a later command: a name path, or the id-path inside an
    /// expanded instance.
    public let address: String

    /// The content revision of what this row addresses — the token a write quotes back.
    ///
    /// ``EditableDocument/revision(of:)``, so it is a Merkle hash: it covers the
    /// node's own properties, everything the file stores under it, *and* — through each
    /// component instance in that subtree — the definition the instance draws. It is
    /// the same 16 hex characters any process computes from the same content. Reading a
    /// frame's row and composing against what it holds is therefore one pin, not one
    /// per descendant and not one more for every component it uses.
    ///
    /// A `ref` stores the component's id and its overrides rather than the component,
    /// so this is deliberately more than the file's own storage: an edit to a component
    /// *definition* moves the revision of every instance of it and of every ancestor
    /// above one, because those are the nodes whose rendering just changed.
    ///
    /// For a row inside an expanded component instance this is the *instance's*
    /// revision, not the definition node's, because an override to that target is
    /// stored on the ref — which is exactly the revision `woodcase get` hands back
    /// for the same address.
    public let rev: String

    /// How many steps below the root of this listing the row sits; a root row is `0`.
    public let depth: Int

    /// The .pen type name (``PenNode/Kind/typeName``) — `"frame"`, `"text"`, `"ref"`.
    public let type: String

    /// The node's name, or `nil` when it has none. An unnamed node is addressed by
    /// its id marker (`"#Out01"`), which is what ``address`` carries.
    public let name: String?

    /// The settled layout rect, in the parent's coordinate space.
    ///
    /// `nil` only when the layout engine produced no rect for this node — never a
    /// zero rect standing in for an unknown one.
    ///
    /// Parent-relative is the layout engine's own convention and the one ``clip``
    /// is computed in: a leaf six levels down reads `0,0` when it sits in its
    /// parent's corner. ``absRect`` is the same rect in document space, for a caller
    /// that wants to compare two nodes in different parents or point a renderer at
    /// one.
    public let rect: PenRect?

    /// The settled layout rect in **document space** — the canvas origin, whatever
    /// the row's depth.
    ///
    /// Composed by ``PenLayoutEngine/absoluteRects(under:in:layoutRects:)``, the one
    /// walk `shot --outline` and the viewer's overlay already use, so a row's
    /// `absRect` and the rect `shot` draws for the same node are the same number from
    /// the same code. Three separate agents re-derived this by walking parents before
    /// it was on the row.
    ///
    /// `nil` under exactly the same conditions as ``rect``: no settled rect for this
    /// node, or none for an ancestor between it and the root.
    public let absRect: PenRect?

    /// How much of ``rect`` falls outside the parent's.
    public let clip: Clip

    /// Which axes ``rect`` falls outside the parent's on.
    ///
    /// Empty exactly when ``clip`` is ``Clip/none``. Computed alongside ``clip`` by
    /// the same comparison in ``TreeView``, so a check that reads it — the `clipped`
    /// check's scroll-aware behavior — never re-derives the geometry with
    /// different arithmetic.
    ///
    /// An array, not a `Set`, in ``OverflowAxis``'s case order — horizontal before
    /// vertical — because a `Set` encodes in its per-process hash order, and the
    /// `--json` report must print the same bytes every run.
    public let overflowAxes: [OverflowAxis]

    /// Whether the node is a reusable component definition (`reusable: true`).
    public let isReusable: Bool

    /// Whether the node is a component instance (a `ref`).
    public let isInstance: Bool

    /// Whether the node is a slot frame — a frame a component definition marks with
    /// `slot`, which an instance's descendant overrides fill.
    public let isSlot: Bool

    /// How many children the node has, whether or not they appear in this listing.
    ///
    /// For a `ref` this is the referenced component's child count, because those are
    /// the children an expanded listing would show.
    public let childCount: Int

    /// The requested property columns, keyed by the property path that was asked for.
    ///
    /// `nil` when no properties were requested. A path that is not a property of this
    /// node's kind is absent from the dictionary; a path that is a property but unset
    /// is present with ``AnyCodable/null``.
    public let properties: [String: AnyCodable]?

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - id: The unique handle for the row.
    ///   - address: The address a later command should pass.
    ///   - rev: The content revision of what the row addresses.
    ///   - depth: Steps below the root of the listing.
    ///   - type: The .pen type name.
    ///   - name: The node's name, or `nil`.
    ///   - rect: The settled layout rect, or `nil` if the engine produced none.
    ///   - absRect: The same rect in document space, or `nil` if the engine produced
    ///     none for this node or for an ancestor above it. Defaults to `nil` so a
    ///     caller building a row by hand — a preview, a viewer golden — need not
    ///     invent a coordinate it has no use for.
    ///   - clip: How much of the rect falls outside the parent's.
    ///   - overflowAxes: Which axes the rect falls outside the parent's on. Defaults
    ///     to empty, matching ``Clip/none``.
    ///   - isReusable: Whether the node is a component definition.
    ///   - isInstance: Whether the node is a `ref`.
    ///   - isSlot: Whether the node is a slot frame.
    ///   - childCount: How many children the node has.
    ///   - properties: The requested property columns, or `nil` if none were requested.
    public init(
        id: String,
        address: String,
        rev: String,
        depth: Int,
        type: String,
        name: String?,
        rect: PenRect?,
        absRect: PenRect? = nil,
        clip: Clip,
        overflowAxes: [OverflowAxis] = [],
        isReusable: Bool,
        isInstance: Bool,
        isSlot: Bool,
        childCount: Int,
        properties: [String: AnyCodable]?
    ) {
        self.id = id
        self.address = address
        self.rev = rev
        self.depth = depth
        self.type = type
        self.name = name
        // A row reports bounds: the scripting contract's `Rect` has four numbers.
        self.rect = rect?.bounds
        self.absRect = absRect?.bounds
        self.clip = clip
        self.overflowAxes = overflowAxes
        self.isReusable = isReusable
        self.isInstance = isInstance
        self.isSlot = isSlot
        self.childCount = childCount
        self.properties = properties
    }
}
