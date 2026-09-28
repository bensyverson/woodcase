//
//  SettledTree+Reuse.swift
//  Woodcase
//

import Foundation

extension SettledTree {
    /// Settles a document, laying out only the roots that an earlier settle cannot
    /// answer for.
    ///
    /// Roots lay out independently — ``PenLayoutEngine/layout(_:textMeasurer:)`` lays
    /// each one out with nothing around it — so a settled tree is a set of per-root
    /// pieces (``Ledger``), and a piece stays true for as long as everything it was built
    /// from does:
    ///
    /// - **The root's own subtree and every component it draws.** That is exactly what
    ///   ``EditableDocument/revision(of:)`` pins: the node, its descendants, and through
    ///   each `ref` the components it renders, transitively — the one it names, the ones
    ///   its overrides repoint at, the ones its slot content instantiates. A root whose
    ///   revision moved is laid out again; one whose revision did not is kept.
    /// - **Everything no revision covers** — the ``Basis``: the theme asked for, the
    ///   document's variables, theme axes, imports, declared fonts, version and extras,
    ///   and the document and read context themselves. When any of it differs, every
    ///   root is laid out.
    /// - **The font set.** When ``TextSizeCache/fontGeneration`` has moved since the
    ///   pieces were measured, every root is laid out.
    ///
    /// A root that left the document takes its piece with it; one that arrived is laid
    /// out. The pieces are laid out by the same pipeline a whole settle runs —
    /// expansion for ``PenRefExpander/Purpose/canvas`` over every component the document
    /// and its libraries define, resolution for the theme, font registration, layout —
    /// restricted to the roots that need it, so the answer is equal to a settle from
    /// nothing, not close to it: `IncrementalSettleEquivalenceTests` compares every map
    /// and every row over every fixture and a spread of writes.
    ///
    /// Where pieces cannot be told apart the tree is settled whole and carries no ledger,
    /// so nothing is ever reused from it: two roots that settle a node under the same id
    /// (an authored `Inst1/Card1` beside the expansion of instance `Inst1`) would leave
    /// the combined maps depending on which root came last.
    ///
    /// - Parameters:
    ///   - document: The document to settle.
    ///   - theme: Theme axes to pin, merged over the document's default theme.
    ///   - textSizes: The run's text sizes, which every text is measured through and whose
    ///     ``TextSizeCache/fontGeneration`` names the font set.
    ///   - previous: An earlier settle of this document, or `nil` to lay out every root.
    ///     It must have been measured through the same `textSizes`.
    package init(
        document: EditableDocument,
        theme: [String: String],
        textSizes: TextSizeCache,
        reusing previous: SettledTree?
    ) {
        let basis = Basis(of: document, theme: theme)
        let present = document.rootOrder.filter { document.nodes[$0] != nil }
        var revisions: [String: String] = [:]
        for id in present {
            revisions[id] = document.revision(of: id)
        }
        if let previous, let reused = Self.reassembled(
            previous, document: document, basis: basis, present: present,
            revisions: revisions, textSizes: textSizes
        ) {
            self = reused
        } else if let whole = Self.assembled(
            document: document, basis: basis, present: present,
            revisions: revisions, textSizes: textSizes
        ) {
            self = whole
        } else {
            self = SettledTree(document: document, theme: theme, textMeasurer: textSizes.measurer)
        }
    }

    // MARK: - Assembling

    /// Every root laid out, one piece each, or `nil` when two roots settle a node under
    /// the same id.
    private static func assembled(
        document: EditableDocument,
        basis: Basis,
        present: [String],
        revisions: [String: String],
        textSizes: TextSizeCache
    ) -> SettledTree? {
        let (pieces, generation) = settle(
            present, of: document, theme: basis.theme, revisions: revisions, textSizes: textSizes
        )
        var maps = Maps()
        for id in present {
            guard let piece = pieces[id], maps.insert(piece) else { return nil }
        }
        return SettledTree(
            rects: maps.rects, absoluteRects: maps.absoluteRects, nodes: maps.nodes,
            ledger: Ledger(basis: basis, fontGeneration: generation, pieces: pieces, laidOut: present)
        )
    }

    /// `previous` with the roots that moved laid out again, or `nil` when it cannot be
    /// reused at all and every root has to be.
    private static func reassembled(
        _ previous: SettledTree,
        document: EditableDocument,
        basis: Basis,
        present: [String],
        revisions: [String: String],
        textSizes: TextSizeCache
    ) -> SettledTree? {
        guard let ledger = previous.ledger, ledger.basis == basis else { return nil }
        let stale = present.filter { id in
            guard let revision = revisions[id] else { return true }
            return ledger.pieces[id]?.revision != revision
        }
        let kept = Set(present).subtracting(stale)
        let dropped = ledger.pieces.keys.filter { !kept.contains($0) }

        let (settled, generation) = stale.isEmpty
            ? ([:], textSizes.fontGeneration)
            : settle(stale, of: document, theme: basis.theme, revisions: revisions, textSizes: textSizes)
        guard generation == ledger.fontGeneration else { return nil }

        var maps = Maps(rects: previous.rects, absoluteRects: previous.absoluteRects, nodes: previous.nodes)
        var pieces = ledger.pieces
        for id in dropped {
            if let gone = pieces.removeValue(forKey: id) { maps.remove(gone) }
        }
        for id in stale {
            guard let piece = settled[id], maps.insert(piece) else { return nil }
            pieces[id] = piece
        }
        return SettledTree(
            rects: maps.rects, absoluteRects: maps.absoluteRects, nodes: maps.nodes,
            ledger: Ledger(basis: basis, fontGeneration: generation, pieces: pieces, laidOut: stale)
        )
    }

    // MARK: - Settling roots

    /// Lays out the given roots, each as its own piece.
    ///
    /// The whole-document pipeline of ``init(document:theme:textMeasurer:)``, over these
    /// roots alone: materialized with the document's tables and its imports' variables
    /// and theme axes, each expanded against every component the document and its
    /// libraries define, resolved for the theme, the forest's fonts registered, and each
    /// root laid out on its own.
    ///
    /// - Parameters:
    ///   - roots: The authored ids of present roots, in root order.
    ///   - document: The document they belong to.
    ///   - theme: Theme axes to pin.
    ///   - revisions: Each root's revision, recorded on its piece.
    ///   - textSizes: The run's text sizes.
    /// - Returns: The pieces keyed by authored root id, and the font generation read
    ///   after registration and before any text was measured.
    private static func settle(
        _ roots: [String],
        of document: EditableDocument,
        theme: [String: String],
        revisions: [String: String],
        textSizes: TextSizeCache
    ) -> (pieces: [String: Piece], generation: Int) {
        var forest = document.document(withRoots: roots)
        let registry = document.materializedComponents()
        forest.children = forest.children.map { PenRefExpander.expand($0, registry: registry) }
        let resolved = PenVariableResolver.resolve(forest, theme: theme)
        document.registerFonts(forSettling: resolved)
        let generation = textSizes.fontGeneration

        var pieces: [String: Piece] = [:]
        for (id, root) in zip(roots, resolved.children) {
            var single = resolved
            single.children = [root]
            let rects = PenLayoutEngine.layout(single, textMeasurer: textSizes.measurer)
            pieces[id] = Piece(
                revision: revisions[id] ?? "",
                rects: rects,
                absoluteRects: PenLayoutEngine.absoluteRects(under: root.id, in: single, layoutRects: rects),
                nodes: indexed([root])
            )
        }
        return (pieces, generation)
    }

    /// The three maps a tree answers from, assembled piece by piece.
    private struct Maps {
        var rects: [String: PenRect] = [:]
        var absoluteRects: [String: PenRect] = [:]
        var nodes: [String: PenNode] = [:]

        /// Adds a piece's entries.
        ///
        /// - Returns: `false` when an id is already present — two roots settle a node
        ///   under the same id, and the maps can no longer be kept root by root.
        mutating func insert(_ piece: Piece) -> Bool {
            guard Self.merge(piece.rects, into: &rects),
                  Self.merge(piece.absoluteRects, into: &absoluteRects),
                  Self.merge(piece.nodes, into: &nodes)
            else { return false }
            return true
        }

        /// Takes a piece's entries out.
        mutating func remove(_ piece: Piece) {
            for id in piece.rects.keys {
                rects.removeValue(forKey: id)
            }
            for id in piece.absoluteRects.keys {
                absoluteRects.removeValue(forKey: id)
            }
            for id in piece.nodes.keys {
                nodes.removeValue(forKey: id)
            }
        }

        private static func merge<Value>(_ entries: [String: Value], into map: inout [String: Value]) -> Bool {
            for (id, value) in entries {
                guard map.updateValue(value, forKey: id) == nil else { return false }
            }
            return true
        }
    }
}
