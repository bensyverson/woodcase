//
//  PasteSite.swift
//  Woodcase
//

import Foundation

/// Where a paste's copied roots go in the target, and how they are positioned there —
/// a ``PasteTarget`` resolved against the document.
struct PasteSite: Friendly {
    /// How the copies are positioned.
    enum Arrangement: Friendly {
        /// As they were copied: canvas coordinates, unchanged.
        case asCopied

        /// In a stack's flow: no coordinates.
        case flow

        /// In a free container, at their offsets in the parents they were copied out of,
        /// or their canvas position in its coordinates — or centered in it when that
        /// misses it.
        case container(id: String)

        /// To the right of a node, top-aligned with it, a gap away.
        case beside(id: String, gap: Double)

        /// Their bounds placed by a corner, exactly, in a free container or on the
        /// canvas (`nil`).
        case corner(Corner, containerID: String?)

        /// In a free container, each at its offset from its own board's corner.
        case boardOffset(containerID: String)

        /// Each back where it came from, on its own.
        case whereCopied(documentID: String?)
    }

    /// What places the copies' bounds, all of them together.
    enum Corner: Friendly {
        /// Their top-left corner on this canvas point.
        case topLeft(PenPoint)

        /// Their center on this canvas point.
        case center(PenPoint)

        /// Their top-left corner at the container's inner top-left.
        case innerTopLeft
    }

    /// One copied root, positioned, with where it is inserted.
    struct Placed: Friendly {
        /// The root, positioned.
        var node: PenNode

        /// The parent it is inserted into, or `nil` for the canvas.
        var parentID: String?

        /// Its index among the parent's children (or the roots), or `nil` to append.
        var index: Int?
    }

    /// The parent every copy is inserted into, or `nil` for the canvas — and for
    /// ``Arrangement/whereCopied(documentID:)``, which picks one per copy.
    var parentID: String?

    /// The index of the first copy among the parent's children (or the roots), or `nil`
    /// to append.
    var index: Int?

    /// How the copies are positioned.
    var arrangement: Arrangement

    /// Resolves a paste target.
    ///
    /// - Parameters:
    ///   - target: Where the paste was asked to go.
    ///   - document: The target document.
    /// - Throws: ``PasteError/targetNotFound(id:)`` for an id the document does not
    ///   store, ``PasteError/notAContainer(id:)`` for a container that cannot hold
    ///   children.
    init(_ target: PasteTarget, in document: EditableDocument) throws {
        switch target {
        case .inPlace:
            self.init(parentID: nil, index: nil, arrangement: .asCopied)
        case let .whereCopied(documentID):
            self.init(parentID: nil, index: nil, arrangement: .whereCopied(documentID: documentID))
        case let .inside(id):
            try self.init(into: id, free: .container(id: id), in: document)
        case let .atBoardOffset(id):
            try self.init(into: id, free: .boardOffset(containerID: id), in: document)
        case let .atInnerTopLeft(id):
            try self.init(into: id, free: .corner(.innerTopLeft, containerID: id), in: document)
        case let .at(point, id):
            try self.init(by: .topLeft(point), in: id, of: document)
        case let .centered(point, id):
            try self.init(by: .center(point), in: id, of: document)
        case let .after(id):
            guard document.nodes[id] != nil else { throw PasteError.targetNotFound(id: id) }
            guard let parentID = document.parents[id] else {
                let index = (document.rootOrder.firstIndex(of: id) ?? document.rootOrder.count - 1) + 1
                self.init(parentID: nil, index: index, arrangement: .beside(id: id, gap: RootOverlap.margin))
                return
            }
            let index = ((document.children[parentID] ?? []).firstIndex(of: id) ?? 0) + 1
            let inFlow = document.nodes[parentID].map(Self.isStack) ?? false
            self.init(
                parentID: parentID, index: index,
                arrangement: inFlow ? .flow : .beside(id: id, gap: PenClip.besideGap)
            )
        }
    }

    /// Creates a site from its parts.
    init(parentID: String?, index: Int?, arrangement: Arrangement) {
        self.parentID = parentID
        self.index = index
        self.arrangement = arrangement
    }

    /// A site placed by a corner: in a container, or on the canvas when there is none.
    private init(by corner: Corner, in containerID: String?, of document: EditableDocument) throws {
        guard let containerID else {
            self.init(parentID: nil, index: nil, arrangement: .corner(corner, containerID: nil))
            return
        }
        try self.init(into: containerID, free: .corner(corner, containerID: containerID), in: document)
    }

    /// A site after a container's last child: in its flow when it is a stack, else
    /// arranged as `free` says.
    ///
    /// - Throws: ``PasteError/targetNotFound(id:)``, ``PasteError/notAContainer(id:)``.
    private init(into id: String, free: Arrangement, in document: EditableDocument) throws {
        guard let container = document.nodes[id] else { throw PasteError.targetNotFound(id: id) }
        guard Self.isContainer(container) else { throw PasteError.notAContainer(id: id) }
        self.init(parentID: id, index: nil, arrangement: Self.isStack(container) ? .flow : free)
    }

    /// Whether a node can hold pasted children: a frame or a group.
    static func isContainer(_ node: PenNode) -> Bool {
        switch node.kind {
        case .frame, .group: true
        default: false
        }
    }

    /// Whether a node lays its children out itself: a frame whose layout is not `none`
    /// (a frame that says nothing is horizontal).
    static func isStack(_ node: PenNode) -> Bool {
        guard case let .frame(data) = node.kind else { return false }
        return (data.layout ?? .horizontal) != .none
    }
}
