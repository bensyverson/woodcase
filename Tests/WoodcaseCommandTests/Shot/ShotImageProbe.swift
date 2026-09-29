//
//  ShotImageProbe.swift
//  WoodcaseCommandTests
//

import Foundation
import PixelPeeper

/// A PNG written by `shot`, decoded into RGBA bytes so a test can ask what
/// color a given pixel is.
///
/// `shot --outline` and `shot --grid` are judged on *geometry* — did the box land on
/// the node's rect, did the image grow by exactly the gutter — and geometry is only
/// checkable by reading pixels back out of the file the binary wrote. Everything the
/// overlay tests need to do that lives here, so neither suite grows its own decoder.
///
/// ```swift
/// let image = try ShotImageProbe(contentsOf: path)
/// #expect(image.outlineInkColumns(inRow: 100) == [39, 200])
/// ```
struct ShotImageProbe {
    /// The decoded image: row-major RGBA bytes, four per pixel, premultiplied against an
    /// sRGB space — decoded by PixelPeeper itself, so a byte read here is the byte
    /// PixelPeeper wrote.
    let image: PixelImage

    /// The image's width in pixels.
    var width: Int {
        image.width
    }

    /// The image's height in pixels.
    var height: Int {
        image.height
    }

    /// Decodes a PNG from disk.
    ///
    /// - Parameter path: The file to read.
    /// - Throws: A ``PixelPeeperError`` when the file is missing or cannot be decoded.
    init(contentsOf path: String) throws {
        image = try PixelImage.load(from: URL(fileURLWithPath: path))
    }

    /// The red, green and blue of one pixel.
    ///
    /// - Parameters:
    ///   - x: The column, from the left edge.
    ///   - y: The row, from the top edge.
    /// - Returns: The three channels, or `nil` when the coordinate is off the image.
    func color(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let offset = (y * width + x) * 4
        return (image.pixels[offset], image.pixels[offset + 1], image.pixels[offset + 2])
    }

    /// Whether a pixel carries the default outline's inner, near-black band.
    ///
    /// PixelPeeper paints that band `(17, 17, 20)` at full alpha. A small tolerance
    /// absorbs any rounding a PNG round-trip introduces without letting a genuinely
    /// different color through — the fixture's own fills are `#F0F0F0`, `#E23B3B`
    /// and `#3B6FE2`, none of them near this.
    ///
    /// - Parameters:
    ///   - x: The column.
    ///   - y: The row.
    /// - Returns: `true` when the pixel is the outline's dark band.
    func isOutlineInk(x: Int, y: Int) -> Bool {
        guard let color = color(x: x, y: y) else { return false }
        func near(_ value: UInt8, _ target: Int) -> Bool {
            abs(Int(value) - target) <= 4
        }
        return near(color.red, 17) && near(color.green, 17) && near(color.blue, 20)
    }

    /// Every column in one row that carries the outline's dark band.
    ///
    /// A row taken through the middle of an outlined rect crosses the ring exactly
    /// twice, so this returns the box's left and right edges as pixel columns.
    ///
    /// - Parameter row: The row to scan.
    /// - Returns: The matching columns, ascending.
    func outlineInkColumns(inRow row: Int) -> [Int] {
        (0 ..< width).filter { isOutlineInk(x: $0, y: row) }
    }

    /// Every row in one column that carries the outline's dark band.
    ///
    /// - Parameter column: The column to scan.
    /// - Returns: The matching rows, ascending.
    func outlineInkRows(inColumn column: Int) -> [Int] {
        (0 ..< height).filter { isOutlineInk(x: column, y: $0) }
    }

    /// The mean absolute error against another image, in 8-bit channel steps (0–255).
    ///
    /// PixelPeeper's ``ImageComparator`` figure, the same measure ``PenSnapshotTests``
    /// uses on the library side: the average per-channel absolute difference, alpha
    /// included, `0` for identical images.
    ///
    /// - Parameter other: The image to compare against.
    /// - Returns: The MAE, or `255` when the two differ in size.
    func meanAbsoluteError(against other: ShotImageProbe) -> Double {
        guard let result = try? ImageComparator.compare(image, other.image) else { return 255 }
        return result.maeSteps.value
    }
}
