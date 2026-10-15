//
//  PenNode+StrokeDash.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    /// The dash the node's stroke is drawn with, or `nil` for a solid stroke.
    ///
    /// Read from ``PenMetadata/WoodcaseKey/strokeDash`` and
    /// ``PenMetadata/WoodcaseKey/strokeDashOffset`` (``PenStrokeDash``). Every target draws
    /// the stroke solid where this is `nil`: no dash, an empty one, one no target can draw
    /// (``PenStrokeDash/problem(in:)``), or a dash on a stroke of per-side widths, whose
    /// bands the dashes cannot flow around — an edit refuses the last two, and lint's
    /// `stroke-dash-ignored` names them in a file. An offset that is not a number is 0.
    var strokeDash: PenStrokeDash? {
        guard let metadata = common.metadata, let value = metadata[woodcase: .strokeDash],
              let lengths = PenStrokeDash.lengths(in: value), !lengths.isEmpty, !hasPerSideStroke
        else { return nil }
        let phase: Double = switch metadata[woodcase: .strokeDashOffset] {
        case let .int(number)?: Double(number)
        case let .double(number)? where number.isFinite: number
        default: 0
        }
        return PenStrokeDash(lengths: lengths, phase: phase)
    }

    /// Whether the node's stroke keys write a width per side.
    internal var hasPerSideStroke: Bool {
        guard case .perSide? = PenLayoutEngine.strokable(self)?.strokeWidth else { return false }
        return true
    }
}
