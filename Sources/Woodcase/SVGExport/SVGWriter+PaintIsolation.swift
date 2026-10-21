//
//  SVGWriter+PaintIsolation.swift
//  Woodcase
//

extension SVGWriter {
    /// `paints` — a node's fills, inner shadows and stroke — in an isolated group when any of
    /// the node's paints blends, as `PenRenderer` draws them; otherwise as they are.
    ///
    /// A paint blends only with the paints beneath it on its node (Ben's reading-1 ruling,
    /// 2026-10-20; `PenPaintStack`). Each blended paint's element keeps its own
    /// `mix-blend-mode`, which reaches as far as the nearest isolated group: this one, so it
    /// never blends with what lies behind the node. The node's outer shadows stay outside it.
    ///
    /// - Parameters:
    ///   - node: The node the paints belong to.
    ///   - paints: Its paint elements, bottom first.
    func isolatingPaints(of node: PenNode, _ paints: [SVGElement]) -> [SVGElement] {
        guard !paints.isEmpty, PenPaintStack(node).blends else { return paints }
        return [SVGElement("g", ["style": "isolation:isolate"], children: paints)]
    }
}
