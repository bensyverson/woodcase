//
//  DeepDocuments+InMemory.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Deep trees built from Swift values rather than parsed, for the walks that start from a
/// node in memory: comparing, hashing, encoding, freeing and inserting.
extension DeepDocuments {
    /// The deepest frame tree a file can hold: Foundation refuses JSON nested past 512
    /// arrays and objects, and each level of a node tree is an object and its `children`
    /// array, under the document's own two.
    static let deepestParsableDepth = 255

    /// A chain of frames `D0` … `D<depth - 1>`, each the only child of the one before,
    /// the last a rectangle named `leaf`.
    ///
    /// Built bottom-up, so building it never recurses.
    ///
    /// - Parameter depth: The number of nodes on the one path.
    /// - Returns: The root, `D0`.
    static func chain(depth: Int) -> PenNode {
        var node = PenNode(
            id: "D\(depth - 1)",
            common: PenNodeCommon(name: "leaf"),
            kind: .rectangle(PenNode.RectangleData())
        )
        for level in stride(from: depth - 2, through: 0, by: -1) {
            node = PenNode(
                id: "D\(level)",
                common: PenNodeCommon(name: "level \(level)"),
                kind: .frame(PenNode.FrameData(children: [node]))
            )
        }
        return node
    }

    /// The settings mockup Ben crashed Penumbra with (2026-10-17), as parsed.
    ///
    /// - Returns: The document.
    /// - Throws: Whatever parsing the fixture throws.
    static func settingsMockup() throws -> PenDocument {
        guard let url = Bundle.module.url(forResource: "settings-mockup", withExtension: "pen", subdirectory: "Fixtures")
        else { throw CocoaError(.fileNoSuchFile) }
        return try PenParser.parse(Data(contentsOf: url))
    }

    /// A tree as wide at every level as the settings mockup and as deep as a file can
    /// be: the mockup's first board with the tree one level shallower appended to its
    /// children, `wraps` times over.
    ///
    /// Every level holds a copy of the board's own frames, texts, icons and ellipses, its
    /// ids prefixed `w<wrap>-` so the tree can be inserted, so each comparison, hash,
    /// encode and free does a real node's work and not only a chain's.
    ///
    /// - Parameter wraps: How many times the board is nested; the tree is `wraps + 8`
    ///   deep.
    /// - Returns: The root.
    /// - Throws: Whatever parsing the fixture throws.
    static func mockupShaped(wraps: Int = deepestParsableDepth - 10) throws -> PenNode {
        guard let board = try settingsMockup().children.first else { throw CocoaError(.fileReadCorruptFile) }
        var tree = board
        for wrap in 0 ..< wraps {
            guard var wrapped = PenTreeRewrite.rewrite(board, context: (), visit: { node, _ in
                .descend(PenNode(id: "w\(wrap)-\(node.id)", common: node.common, kind: node.kind, extras: node.extras), ())
            }) else { break }
            wrapped.kind = wrapped.kind.replacingInlineChildren(with: wrapped.kind.inlineChildren + [tree])
            tree = wrapped
        }
        return tree
    }

    /// The tree with the deepest leaf on its last-child path renamed — a difference a
    /// comparison only finds at the bottom.
    ///
    /// Rebuilt bottom-up from a work list, so it never recurses either.
    ///
    /// - Parameters:
    ///   - root: The tree.
    ///   - name: The leaf's new name.
    /// - Returns: The changed tree.
    static func renamingDeepestLastLeaf(of root: PenNode, to name: String) -> PenNode {
        var path = [root]
        while let next = path.last?.kind.inlineChildren.last {
            path.append(next)
        }
        var rebuilt = path.removeLast()
        rebuilt.common.name = name
        while var parent = path.popLast() {
            var children = parent.kind.inlineChildren
            children[children.count - 1] = rebuilt
            parent.kind = parent.kind.replacingInlineChildren(with: children)
            rebuilt = parent
        }
        return rebuilt
    }
}
