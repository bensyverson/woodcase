//
//  PenRefExpander+InstancePath.swift
//  Woodcase
//

import Foundation

public extension PenRefExpander {
    /// The path that names an instance whose expanded root has this id, or `nil` when the
    /// node is no instance root.
    ///
    /// The expander prefixes every id it clones with the instance's path, so each node of
    /// an instance's tree is `<path>/<id>`, and the instance's root is the one node of it
    /// whose parent is not: its id less its last step differs from its parent's. That
    /// path is what an authored reference names the instance by — the `ref`'s own id
    /// (`Chip`, rooted at `Chip/<component root id>`), or for an instance inside another
    /// instance's tree or slot fill its `instance/key` path (`Filled/Row1`, rooted at
    /// `Filled/Row1/<component root id>`) — and no node of the expanded document has it
    /// as its id. A connector end is one such reference
    /// (``PenLayoutEngine/connectionEndpointRects(in:layoutRects:)``).
    ///
    /// - Parameters:
    ///   - id: A node's id in the expanded document.
    ///   - parentID: Its parent's id, or `nil` for a top-level node.
    /// - Returns: The instance's path, or `nil` for any other node.
    static func instancePath(ofExpandedID id: String, parentID: String?) -> String? {
        guard let path = prefix(of: id) else { return nil }
        return path == parentID.flatMap(prefix(of:)) ? nil : path
    }

    /// An expanded id less its last step, or `nil` for an id with one step.
    private static func prefix(of id: String) -> String? {
        id.lastIndex(of: NodeAddress.separator).map { String(id[..<$0]) }
    }
}
