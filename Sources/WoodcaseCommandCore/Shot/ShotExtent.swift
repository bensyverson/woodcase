//
//  ShotExtent.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// The `--extent` argument: which of a node's extents a shot frames.
///
/// A node has three extents (``Woodcase/PenPlacement``): its layout rect, the box it is
/// drawn as, and its painted extent — the rect grown by its stroke band, shadows, blur and
/// unclipped children. `shot` frames the layout rect by default, because every coordinate
/// a caller acts on is measured in it; `--extent painted` frames what the node paints,
/// the way Pen frames an export, so an outer stroke, a shadow or an overhanging child is
/// not cut off at the rect's edge.
enum ShotExtent: String, ExpressibleByArgument, CaseIterable, Friendly {
    /// The node's layout rect — what `tree` reports and what its parent allocates.
    case layout

    /// Everything the node paints
    /// (``Woodcase/PenLayoutEngine/paintedExtent(of:rect:layoutRects:)``).
    case painted

    /// The region this extent frames for a node, in the same coordinates as its layout
    /// rect: its parent's, or the canvas's for a top-level node.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - rect: Its layout rect.
    ///   - layoutRects: The settled rects, for its descendants.
    /// - Returns: The rect to frame.
    func region(of node: PenNode, rect: PenRect, layoutRects: [String: PenRect]) -> PenRect {
        switch self {
        case .layout: rect
        case .painted: PenLayoutEngine.paintedExtent(of: node, rect: rect, layoutRects: layoutRects)
        }
    }
}
