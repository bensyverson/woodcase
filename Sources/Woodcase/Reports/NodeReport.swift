//
//  NodeReport.swift
//  Woodcase
//

import Foundation

/// The `--json` shape of `woodcase get`: one node, and the revision it was read at.
///
/// The revision is the token a later write quotes back, so the two travel together —
/// a reader that had to make a second call for it would be reasoning about a node it
/// could not safely change. It is ``EditableDocument/revision(of:)`` for the node the
/// address names; for an address *inside* a component instance it is the revision of
/// the instance's `ref` node, because that is where an override to this target is
/// written.
///
/// This is the one struct both the producer and any consumer decode, so the wire
/// shape cannot drift. ``TreeReport`` is its sibling for `woodcase tree`.
public struct NodeReport: Friendly {
    /// Creates a report.
    ///
    /// - Parameters:
    ///   - revision: The revision the node was read at.
    ///   - node: The node, as `.pen` JSON.
    ///   - props: The parameters the node publishes, or `nil` when it publishes none.
    public init(revision: String, node: PenNode, props: [ComponentParameter]? = nil) {
        self.revision = revision
        self.node = node
        self.props = props
    }

    /// The revision the node was read at.
    public let revision: String

    /// The node itself.
    public let node: PenNode

    /// The parameters the node publishes in `common.metadata._props`, resolved to the
    /// descendant and property each one writes — omitted entirely for a node that
    /// publishes none, so a consumer branches on presence rather than on an empty list.
    public let props: [ComponentParameter]?
}
