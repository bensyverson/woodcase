//
//  PenNode+StrokeMiterLimit.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    /// The miter limit Pen strokes with: the longest a mitered join reaches, as a multiple of
    /// the stroke's width, before it falls back to a bevel.
    ///
    /// It is 4 — Skia's default and SVG's — not CoreGraphics' and SwiftUI's 10: headless Pen
    /// (pen CLI 0.3.11, 2026-10-15) bevels the 25° apex of an 8 pt stroked triangle, whose
    /// miter is 4.62 widths long, and miters a 40° one (2.92). Every Woodcase target strokes
    /// with this unless ``strokeMiterLimit`` says otherwise.
    static let defaultMiterLimit = 4.0

    /// What a written ``PenMetadata/WoodcaseKey/strokeMiterLimit`` must keep to: a factor of
    /// at least 1, since no miter is shorter than the stroke is wide.
    static let miterLimitConstraint = PenValueConstraint(unit: .factor, minimum: .inclusive(1))

    /// The miter limit the node's stroke is drawn with: its
    /// ``PenMetadata/WoodcaseKey/strokeMiterLimit``, or ``defaultMiterLimit`` where it has
    /// none, or one that is not a finite number of at least 1.
    ///
    /// The format has had no miter control since 2.17 dropped the legacy stroke's
    /// `miterAngle`, which migration turns into this key. Pen keeps the key on save and
    /// strokes with its own 4 regardless.
    var strokeMiterLimit: Double {
        let limit: Double? = switch common.metadata?[woodcase: .strokeMiterLimit] {
        case let .int(number)?: Double(number)
        case let .double(number)?: number
        default: nil
        }
        guard let limit, limit.isFinite, limit >= 1 else { return Self.defaultMiterLimit }
        return limit
    }
}
