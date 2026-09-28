//
//  PenStrokable.swift
//  Woodcase
//
//  Created by Claude on 2026-08-29.
//

import Foundation

/// A node payload that can carry a stroke.
///
/// .pen 2.17 spells a stroke as five sibling keys on the node rather than one nested
/// object, so every strokable payload — frame, text, rectangle, ellipse, path, line,
/// polygon — declares the same five properties. This protocol is how the renderer,
/// the code generator and the resolvers address them once instead of seven times.
///
/// ```swift
/// func strokeColor(of node: some PenStrokable) -> String? {
///     guard node.stroke != nil else { return nil }   // no paint, no stroke
///     ...
/// }
/// ```
///
/// A node with no ``stroke`` paint draws no stroke, whatever the other four keys say.
/// Absent values mean the .pen defaults: ``PenStrokeAlign/center``,
/// ``PenStrokeJoin/miter``, ``PenStrokeCap/butt``, and a width of 1.
public protocol PenStrokable {
    /// The stroke's paint, in the same shapes a fill accepts (`"#RRGGBB"` shorthand included).
    var stroke: PenFills? { get set }
    /// The stroke's width — uniform, or one value per side.
    var strokeWidth: PenStrokeWidth? { get set }
    /// How line ends are capped. Absent means ``PenStrokeCap/butt``.
    var strokeLinecap: PenStrokeCap? { get set }
    /// How corners are joined. Absent means ``PenStrokeJoin/miter``.
    var strokeLinejoin: PenStrokeJoin? { get set }
    /// Where the stroke sits relative to the boundary. Absent means ``PenStrokeAlign/center``.
    var strokeAlignment: PenStrokeAlign? { get set }
}

public extension PenStrokable {
    /// The resolved width of a uniform stroke, or `nil` when the stroke is per-side.
    ///
    /// Defaults to 1 when `strokeWidth` is absent, matching the .pen default.
    var uniformStrokeWidth: Double? {
        switch strokeWidth {
        case let .uniform(value): value.literalValue ?? 1
        case .perSide: nil
        case nil: 1
        }
    }
}
