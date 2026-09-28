//
//  DeepDocuments.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Generated documents nested far deeper than any fixture, and walks over them that
/// do not recurse.
enum DeepDocuments {
    /// `C0` is a leaf holding `Leaf`; each `C<i>` wraps an instance of `C<i-1>` in
    /// `frames` plain frames and writes a rectangle `Inj<i>` into that instance's slot.
    /// `Top` places the last one and renames the rectangle its component wrote.
    ///
    /// - Parameters:
    ///   - depth: How many components nest; the expansion is `(depth - 1) * (frames + 1) + 2`
    ///     nodes deep.
    ///   - frames: Plain frames around each nested instance.
    /// - Returns: The document's JSON.
    static func nestedInstances(depth: Int, frames: Int) -> String {
        var components: [String] = [
            #"{"id": "C0", "type": "frame", "reusable": true, "children": ["#
                + #"{"id": "Hole0", "type": "frame", "children": []},"#
                + #"{"id": "Leaf", "type": "rectangle", "width": 4, "height": 4}]}"#,
        ]
        for level in 1 ..< depth {
            var wrapped = #"{"id": "I\#(level)", "type": "ref", "ref": "C\#(level - 1)", "descendants": {"#
                + #""Hole\#(level - 1)": {"children": [{"id": "Inj\#(level)", "type": "rectangle", "width": 2}]}}}"#
            for frame in 0 ..< frames {
                wrapped = #"{"id": "F\#(level)x\#(frame)", "type": "frame", "children": [\#(wrapped)]}"#
            }
            components.append(
                #"{"id": "C\#(level)", "type": "frame", "reusable": true, "children": ["#
                    + #"{"id": "Hole\#(level)", "type": "frame", "children": []}, \#(wrapped)]}"#
            )
        }
        let top = #"{"id": "Top", "type": "ref", "ref": "C\#(depth - 1)", "descendants": {"#
            + #""Inj\#(depth - 1)": {"name": "patched"}}}"#
        return #"{"version": "2.17", "children": [\#(components.joined(separator: ", ")), \#(top)]}"#
    }

    /// One root frame `D0` with frames `D1` … `D<depth - 1>` nested below it.
    ///
    /// - Parameter depth: The number of nodes on the one path.
    /// - Returns: The document's JSON.
    static func frameTree(depth: Int) -> String {
        var tree = #"{"id": "D\#(depth - 1)", "type": "frame"}"#
        for level in stride(from: depth - 2, through: 0, by: -1) {
            tree = #"{"id": "D\#(level)", "type": "frame", "children": [\#(tree)]}"#
        }
        return #"{"version": "2.17", "children": [\#(tree)]}"#
    }

    /// The number of nodes on the longest root-to-leaf path.
    static func depth(of node: PenNode) -> Int {
        var deepest = 0
        var pending: [(PenNode, Int)] = [(node, 1)]
        while let (next, level) = pending.popLast() {
            deepest = max(deepest, level)
            pending.append(contentsOf: next.kind.inlineChildren.map { ($0, level + 1) })
        }
        return deepest
    }

    /// The number of nodes on the longest root-to-leaf path of any root.
    static func depthOfDeepestRoot(in document: PenDocument) -> Int {
        document.children.map(depth(of:)).max() ?? 0
    }

    /// The first node whose id ends in `/<suffix>`.
    static func node(endingIn suffix: String, in root: PenNode) -> PenNode? {
        var pending = [root]
        while let next = pending.popLast() {
            if next.id.hasSuffix("/\(suffix)") { return next }
            pending.append(contentsOf: next.kind.inlineChildren)
        }
        return nil
    }
}
