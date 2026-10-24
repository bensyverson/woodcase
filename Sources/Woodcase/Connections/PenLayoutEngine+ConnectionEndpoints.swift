//
//  PenLayoutEngine+ConnectionEndpoints.swift
//  Woodcase
//

import Foundation

public extension PenLayoutEngine {
    /// Every box a connection's endpoint path can name, in canvas coordinates: what a
    /// renderer routes a top-level connection through.
    ///
    /// ``canvasRects(in:layoutRects:)`` keys each node by its expanded id, and an expanded
    /// instance keeps no node under the path its connector ends name: the expander roots
    /// the instance placed by `Chip` at `Chip/<component root id>`, and one placed in a
    /// slot fill or a component (`Filled/Row1`) at `Filled/Row1/<component root id>`. So
    /// this is those rects with each instance root's box also keyed by its instance path
    /// (``PenRefExpander/instancePath(ofExpandedID:parentID:)``):
    /// the `ref`'s own id, or for a nested instance the `instance/key` path an editor
    /// addresses it by. A node inside an instance is keyed by its expanded id already
    /// (`Chip/Label`), which is the path an end names it by.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document the layout ran on.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    /// - Returns: ``canvasRects(in:layoutRects:)``, plus each instance root's box under its
    ///   instance path where no node has that id.
    static func connectionEndpointRects(
        in document: PenDocument,
        layoutRects: [String: PenRect]
    ) -> [String: PenRect] {
        var rects = canvasRects(in: document, layoutRects: layoutRects)
        for (path, rootID) in instancePaths(in: document) where rects[path] == nil {
            if let rect = rects[rootID] { rects[path] = rect }
        }
        return rects
    }

    /// Each expanded instance root's id, by the instance path that places it
    /// (``PenRefExpander/instancePath(ofExpandedID:parentID:)``).
    ///
    /// - Parameter document: A ref-expanded document.
    /// - Returns: Expanded instance-root ids, keyed by instance path; the first in
    ///   pre-order wins a path.
    internal static func instancePaths(in document: PenDocument) -> [String: String] {
        var paths: [String: String] = [:]
        // A work list, not recursion, so a deep tree cannot overflow a Swift task's stack
        // in a debug build (`project/2026-09-26-debug-stack-depth.md`).
        var pending: [(node: PenNode, parentID: String?)] = document.children.reversed().map { ($0, nil) }
        while let (node, parentID) = pending.popLast() {
            if let path = PenRefExpander.instancePath(ofExpandedID: node.id, parentID: parentID), paths[path] == nil {
                paths[path] = node.id
            }
            pending.append(contentsOf: node.kind.inlineChildren.reversed().map { ($0, node.id) })
        }
        return paths
    }
}
