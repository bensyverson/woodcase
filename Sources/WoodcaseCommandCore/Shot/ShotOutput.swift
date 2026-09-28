//
//  ShotOutput.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// What `shot` printed: the node it rendered, the scale it chose, the region it drew in
/// layout points, the PNG's pixel size, the gutters `--grid` added, and — on `--json` —
/// every rect it drew.
///
/// Together these map a pixel back to a point:
///
/// ```text
/// point = (pixel − gutter) / scale + origin
/// ```
///
/// where `origin` is ``rect``'s `x`/`y` — the same offset ``PenRenderer`` subtracts
/// before drawing — and `gutter` is ``gutterLeft``/``gutterTop``, which are `0` unless
/// `--grid` was asked for. The formula inverts exactly what the render did, and it is
/// the same formula with and without a grid, so a caller never has to branch on it.
struct ShotOutput: Friendly {
    /// The id of the node that was rendered — already in the post-expansion form for
    /// a node inside a component instance (see ``ResolvedNodeAddress/address``).
    let node: String

    /// `min(1, --max / longestSide)`, or `--scale` verbatim when it was given —
    /// `--scale` takes precedence over `--max` and, unlike it, can exceed 1.
    let scale: Double

    /// The region actually drawn, in points: the node's own layout rect, or the
    /// sub-rectangle `--crop` narrowed the render to.
    ///
    /// Its `x`/`y` is the `origin` of the mapping formula, which is why `--crop` needs
    /// no second formula — the crop simply moves the origin. The frame is the one the
    /// layout engine computed the node's rect in: parent-local for a nested node,
    /// document-absolute for a top-level one. The node's *own* rect is always the first
    /// entry of ``rects``, cropped or not.
    ///
    /// For `--extent painted` with no `--crop`, this is grown to a whole number of
    /// pixels at `scale` first — the same rounding Pen's own PNG export does
    /// (``Woodcase/PenRect/grownToWholePixels(at:)``) — so its `x`/`y` stays at the
    /// painted extent's own corner, fractional or not, while `width`/`height` grow just
    /// enough that `pixelWidth`/`pixelHeight` are whole.
    let rect: PenRect

    /// Every rect this run drew: the rendered node, then one entry per `--outline` in
    /// the order the flags were given.
    ///
    /// All of them are in the rendered node's own coordinate space — the space ``rect``
    /// establishes — so `pixel = (point − origin) × scale + gutter` places any of them
    /// in the image. Text output does not carry these: a shot's one line stays one line,
    /// and a caller that needs to locate what it is looking at asks for `--json`.
    let rects: [ShotRect]

    /// The PNG's width, in pixels, gutters included.
    ///
    /// Without `--grid` this is `rect.width × scale`, which is at most `--max`. With
    /// it, the image is wider by ``gutterLeft`` — a gridded shot exceeds `--max` by
    /// design, because a ruler scaled down with the picture cannot be read.
    let pixelWidth: Int

    /// The PNG's height, in pixels, gutters included.
    let pixelHeight: Int

    /// The width of the ruler gutter down the PNG's left edge, in pixels; `0` without
    /// `--grid`.
    let gutterLeft: Int

    /// The height of the ruler gutter across the PNG's top edge, in pixels; `0`
    /// without `--grid`.
    let gutterTop: Int

    /// The PNG's path on disk.
    let output: String

    /// One line: node, scale, rect, pixel size, gutters, output path.
    ///
    /// Fields are `key=value`, space-separated, so a script can split on whitespace;
    /// `scale` and `rect` print at full `Double` precision — this is coordinate data
    /// an agent computes with, not a table meant for scanning — so the round-trip
    /// math in the type's discussion stays exact. `gutter` prints on every shot, `0,0`
    /// included: a field that appears only sometimes is a field every parser gets
    /// wrong once.
    var text: String {
        "\(node)  scale=\(scale)  rect=\(rect.x),\(rect.y),\(rect.width),\(rect.height)  "
            + "pixels=\(pixelWidth)x\(pixelHeight)  gutter=\(gutterLeft),\(gutterTop)  "
            + "out=\(output)"
    }

    /// The same fields as JSON, sorted keys, pretty-printed, no trailing newline.
    ///
    /// - Returns: The JSON text.
    /// - Throws: Whatever `JSONEncoder` throws.
    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
