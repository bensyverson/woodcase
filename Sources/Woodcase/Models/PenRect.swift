//
//  PenRect.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import CoreGraphics
import Foundation

/// A rectangle with position and size, used for layout computation results.
///
/// As a layout rect it is extent (i) of the three the library names, the **bounds**: the
/// axis-aligned bounds of the node's turned, flipped box, in its parent's coordinates —
/// what a parent allocates and aligns, what a group unions and what `tree` reports.
/// Strokes, shadows and blur never enter it. Extent (ii), the box and the map that draws
/// it, is ``PenPlacement`` (``PenLayoutEngine/placement(of:rect:layoutRects:)``); extent
/// (iii), everything the node may paint, is
/// ``PenLayoutEngine/paintedExtent(of:rect:layoutRects:)``.
///
/// Unlike `CGRect`, `PenRect` conforms to `Friendly` (Codable, Equatable, Hashable, Sendable).
/// The layout engine returns `[String: PenRect]` keyed by node ID.
///
/// ## Turned nodes
///
/// A turned node's layout rect is the bounds of its box turned, which is not the size it is
/// drawn at: a 70×30 frame turned 45° settles in a 70.7-point square, and so does every
/// frame whose sides add up to 100. So the layout keeps the size it gave the node before it
/// turned it in ``unturnedSize``, and every reader of the rect —
/// ``PenLayoutEngine/unturnedBox(of:rect:layoutRects:)``, and through it the renderers and
/// ``PenLayoutEngine/placement(of:rect:layoutRects:)`` — reads it there rather than
/// reconstructing it from the bounds. ``drawnSize`` answers for every rect.
public struct PenRect: Friendly {
    /// The left edge, in the parent's coordinates.
    public let x: Double
    /// The top edge, in the parent's coordinates.
    public let y: Double
    /// The width.
    public let width: Double
    /// The height.
    public let height: Double

    /// The size the node is drawn at before it turns, when the layout turned it; `nil` when
    /// the rect's own size is that size.
    ///
    /// The layout writes it for every node with a rotation. Encoded only when present, so
    /// an unturned rect encodes as its four numbers.
    public let unturnedSize: PenSize?

    /// Creates a rect.
    ///
    /// - Parameters:
    ///   - x: The left edge.
    ///   - y: The top edge.
    ///   - width: The width.
    ///   - height: The height.
    ///   - unturnedSize: The node's size before it turns, when the rect is the bounds of
    ///     its turned box; `nil` when the rect's own size is the drawn size.
    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        unturnedSize: PenSize? = nil
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.unturnedSize = unturnedSize
    }

    /// The size the node is drawn at before any turn: ``unturnedSize`` when the layout
    /// turned it, the rect's own size otherwise.
    public var drawnSize: PenSize {
        unturnedSize ?? PenSize(width: width, height: height)
    }

    /// The rect's position and size alone, without an ``unturnedSize``: its bounds as a
    /// plain rect, for a reader that reports bounds rather than draws the node.
    public var bounds: PenRect {
        PenRect(x: x, y: y, width: width, height: height)
    }

    /// Converts to a Core Graphics rect for rendering.
    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// The empty rect at the origin.
    public static let zero = PenRect(x: 0, y: 0, width: 0, height: 0)
}
