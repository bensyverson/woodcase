//
//  PenClipFixture.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The document the ``PenClip`` suites copy from (`Fixtures/clip.pen`, which the
/// `woodcase clip` tests read too), and what they ask of every clip.
///
/// - `Lib` holds the components: `Icon` (filled with `$accent`), `Btn` (a label and
///   an instance of `Icon`), `Alias` (a component that is only a ref to `Btn`), `Outer`
///   (which defines `Inner` inside itself) and `Unrelated`, which nothing uses.
/// - `Page` sits at (100, 200) and holds `Card` at (10, 20) — a vertical stack of the
///   instance `BtnI` and the rectangle `Fill`, which fills the card's width — plus the
///   free rectangle `Free` at (5, 6), `AliasI` and `OuterI`.
/// - `$accent` is `$brand`, which is themed on `mode`; `$unused` and the `density`
///   axis are defined and used by nothing.
enum PenClipFixture {
    /// A fresh editable copy of the source document.
    static func document() throws -> EditableDocument {
        let url = try #require(Bundle.module.url(forResource: "clip", withExtension: "pen", subdirectory: "Fixtures"))
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// Every node id in a forest, in pre-order.
    static func allIDs(in roots: [PenNode]) -> [String] {
        var ids: [String] = []
        var pending = Array(roots.reversed())
        while let node = pending.popLast() {
            ids.append(node.id)
            pending.append(contentsOf: node.kind.inlineChildren.reversed())
        }
        return ids
    }

    /// Every node in a forest, keyed by id.
    static func index(_ roots: [PenNode]) -> [String: PenNode] {
        var index: [String: PenNode] = [:]
        var pending = roots
        while let node = pending.popLast() {
            index[node.id] = node
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        return index
    }

    /// Checks what every clip must be: no id twice, and a document that stands alone.
    static func expectSelfContained(_ clip: PenClip, sourceLocation: SourceLocation = #_sourceLocation) {
        let ids = allIDs(in: clip.document.children)
        #expect(Set(ids).count == ids.count, "an id appears twice", sourceLocation: sourceLocation)
        #expect(clip.document.imports == nil, sourceLocation: sourceLocation)
    }
}
