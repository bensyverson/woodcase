//
//  EditableDocument+RootRects.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Where every root settles, measured without settling the document.
    ///
    /// A root's rect is its own `x`/`y` and the size ``PenLayoutEngine`` gives it with
    /// nothing around it to fill — no root's size depends on another's, or on anything
    /// outside its own subtree. So the answer a full ``SettledTree`` gives for the roots
    /// can be had for much less, in two passes:
    ///
    /// 1. **Declared.** Every root is resolved on its own, children left out. One whose
    ///    width and height both resolve to a fixed number *is* that size, whatever its
    ///    descendants do, so it is answered here and its subtree is never materialized,
    ///    expanded or laid out.
    /// 2. **Laid out.** Everything else — a root sized to its content on either axis, a
    ///    group, a component instance (whose size is its component's) — is materialized
    ///    with its subtree, expanded for ``PenRefExpander/Purpose/canvas`` against the
    ///    whole document's components, resolved, and laid out: its own subtree, and no
    ///    other root's.
    ///
    /// Both passes are the pipeline ``SettledTree`` runs — the same expansion, the same
    /// resolution at the default theme, the same font registration, the same engine —
    /// restricted to the nodes a root's rect can depend on, so the rects are equal, not
    /// close: `RootRectsEquivalenceTests` compares every root of every fixture, turned and
    /// unturned, against a full settle.
    ///
    /// A root that is a component instance settles under its expanded id
    /// (`Inst1/Card1`), and is keyed here by its own — the id a caller addresses it by.
    ///
    /// - Parameter textMeasurer: A function that measures text bounding boxes.
    /// - Returns: Root id → its settled rect in canvas coordinates, for every root in
    ///   ``rootOrder`` the store holds.
    package func rootRects(
        textMeasurer: TextMeasurer = PenLayoutEngine.defaultTextMeasurer
    ) -> [String: PenRect] {
        let present = rootOrder.filter { nodes[$0] != nil }
        var rects: [String: PenRect] = [:]

        var declared = document(withRoots: [])
        declared.children = present.compactMap { nodes[$0] }
        for root in PenVariableResolver.resolve(declared, theme: [:]).children {
            guard let size = Self.declaredSize(of: root) else { continue }
            rects[root.id] = Self.rect(of: root, size: size)
        }

        let laidOut = present.filter { rects[$0] == nil }
        guard !laidOut.isEmpty else { return rects }

        var subtrees = document(withRoots: laidOut)
        let registry = materializedComponents()
        subtrees.children = subtrees.children.map { PenRefExpander.expand($0, registry: registry) }
        let resolved = PenVariableResolver.resolve(subtrees, theme: [:])
        registerFonts(forSettling: resolved)
        let layout = PenLayoutEngine.layout(resolved, textMeasurer: textMeasurer)
        for (id, root) in zip(laidOut, resolved.children) {
            rects[id] = layout[root.id]
        }
        return rects
    }

    /// The document's metadata with the imports' variables and theme axes merged in —
    /// what resolution reads — and the given roots materialized with their subtrees.
    ///
    /// - Parameter roots: The root ids to materialize, in order.
    /// - Returns: The document, holding only those roots.
    func document(withRoots roots: [String]) -> PenDocument {
        importedDefinitions.merged(into: Self.buildDocument(from: FlatStoreSnapshot(
            nodes: nodes, children: children, rootOrder: roots,
            version: version, themes: themes, imports: imports, variables: variables,
            fileToken: fileToken, fonts: fonts, extras: extras
        )))
    }

    /// A resolved root's size when it is fixed on both axes, which is the size the
    /// layout engine gives it whatever its children are.
    ///
    /// - Parameter root: A variable-resolved root node, children stripped or not.
    /// - Returns: Its width and height, or `nil` when either depends on layout.
    private static func declaredSize(of root: PenNode) -> (width: Double, height: Double)? {
        guard case let .fixed(width) = PenLayoutEngine.widthSizing(of: root),
              case let .fixed(height) = PenLayoutEngine.heightSizing(of: root)
        else { return nil }
        return (width, height)
    }

    /// A root's rect, the way ``PenLayoutEngine/layout(_:textMeasurer:)`` writes it:
    /// placed by its own `x`/`y`, or the origin, turned and flipped about that anchor
    /// (``PenLayoutEngine/freeRect(of:x:y:width:height:)``).
    ///
    /// - Parameters:
    ///   - root: The resolved root.
    ///   - size: Its size.
    /// - Returns: Its rect in canvas coordinates.
    private static func rect(of root: PenNode, size: (width: Double, height: Double)) -> PenRect {
        PenLayoutEngine.freeRect(
            of: root,
            x: root.common.x?.literalValue ?? 0,
            y: root.common.y?.literalValue ?? 0,
            width: size.width,
            height: size.height
        )
    }
}
