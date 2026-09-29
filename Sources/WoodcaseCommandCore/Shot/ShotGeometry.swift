//
//  ShotGeometry.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// The rectangle arithmetic `shot` judges its refusals by.
///
/// Four one-line predicates, kept together and named, because each one encodes a
/// *ruling* rather than a formula: what counts as on the image, what counts as inside a
/// crop, and what the tool offers back when the answer is no. `CGRect` has near-namesakes
/// for three of them and disagrees with all three at the edges — it treats an empty rect
/// as intersecting nothing, and normalizes negative sizes — so the arithmetic lives here
/// in layout points, where a zero-height text run still has a position worth pointing at.
enum ShotGeometry {
    /// Whether two layout rects touch at all.
    ///
    /// Deliberately inclusive where `CGRect.intersects` is not: a zero-width or
    /// zero-height node — an empty text run, a collapsed frame — has a real position
    /// worth pointing at, and a rect that only meets the region's edge still draws a
    /// visible band.
    ///
    /// - Parameters:
    ///   - rect: One rect.
    ///   - other: The other.
    /// - Returns: `true` when the two overlap or touch.
    static func overlaps(_ rect: PenRect, _ other: PenRect) -> Bool {
        rect.x <= other.x + other.width
            && rect.x + rect.width >= other.x
            && rect.y <= other.y + other.height
            && rect.y + rect.height >= other.y
    }

    /// Whether `outer` wholly contains `inner`.
    ///
    /// - Parameters:
    ///   - outer: The containing rect.
    ///   - inner: The rect that must fit.
    /// - Returns: `true` when no edge of `inner` falls outside `outer`.
    static func contains(_ outer: PenRect, _ inner: PenRect) -> Bool {
        inner.x >= outer.x
            && inner.y >= outer.y
            && inner.x + inner.width <= outer.x + outer.width
            && inner.y + inner.height <= outer.y + outer.height
    }

    /// The smallest rect covering both.
    ///
    /// - Parameters:
    ///   - first: One rect.
    ///   - second: The other.
    /// - Returns: Their union.
    static func union(_ first: PenRect, _ second: PenRect) -> PenRect {
        let x = min(first.x, second.x)
        let y = min(first.y, second.y)
        return PenRect(
            x: x,
            y: y,
            width: max(first.x + first.width, second.x + second.width) - x,
            height: max(first.y + first.height, second.y + second.height) - y
        )
    }

    /// A rect trimmed to fit inside another.
    ///
    /// - Parameters:
    ///   - rect: The rect to trim.
    ///   - bounds: What it must fit inside.
    /// - Returns: The intersection, whose width or height is `0` or less when the two do
    ///   not meet — so a caller offering the result as a remedy must check it has area.
    static func clamp(_ rect: PenRect, to bounds: PenRect) -> PenRect {
        let x = min(max(rect.x, bounds.x), bounds.x + bounds.width)
        let y = min(max(rect.y, bounds.y), bounds.y + bounds.height)
        return PenRect(
            x: x,
            y: y,
            width: min(rect.x + rect.width, bounds.x + bounds.width) - x,
            height: min(rect.y + rect.height, bounds.y + bounds.height) - y
        )
    }
}
