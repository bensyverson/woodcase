//
//  PenBrowserRenderTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// The renderer draws a `browser` node as a quiet placeholder — a light neutral fill,
/// a thin border and the URL as a small gray label, all clipped to the corner radius —
/// and never loads the page. A node's own stroke and effects replace or add to the
/// placeholder's defaults.
///
/// There is no Pen reference to hold this against: Pen draws a live snapshot of the
/// page. `browser.png` is Woodcase's own render, blessed with `UPDATE_GOLDEN=1` and
/// read by eye; the pixel probes below say what it must show whatever the reference.
struct PenBrowserRenderTests {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    private static let scale: CGFloat = 2

    /// The placeholder's look, pinned here so a change to it is a change to a test.
    private static let fill = RGB(0xF4, 0xF4, 0xF5)
    private static let border = RGB(0xD4, 0xD4, 0xD8)
    private static let labelGray = RGB(0xA1, 0xA1, 0xAA)

    /// Renders the browser fixture's root frame at @2x.
    private func render() throws -> CGImage {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("browser.pen"))
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
        let rects = PenLayoutEngine.layout(document)
        let root = try #require(rects["BrRt0"])
        return try #require(PenRenderer.render(
            document, layoutRects: rects,
            size: CGSize(width: root.width, height: root.height),
            scale: Self.scale, rootNodeID: "BrRt0"
        ))
    }

    // MARK: - The reference

    @Test("The placeholder render matches Woodcase's committed reference")
    func matchesReference() throws {
        let rendered = try render()
        let url = Self.fixtures.appendingPathComponent("browser.png")
        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
            try PNGEncoder.write(rendered, to: url)
        }
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "browser", fixturesDir: Self.fixtures),
            "no reference at \(url.path); bless one with UPDATE_GOLDEN=1 and read it"
        )
        #expect(reference.width == rendered.width)
        #expect(reference.height == rendered.height)
        #expect(PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference) < 0.5)
    }

    @Test("Two renders of the placeholder are identical to the byte")
    func deterministic() throws {
        let first = try Pixels(render(), scale: Self.scale)
        let second = try Pixels(render(), scale: Self.scale)
        #expect(first.rgb(x: 40, y: 80) == Self.fill, "no placeholder was drawn")
        #expect(first.bytes == second.bytes)
    }

    // MARK: - What the placeholder shows

    @Test("The inside is the placeholder's light neutral fill")
    func fill() throws {
        let pixels = try Pixels(render(), scale: Self.scale)
        // Web: 10,60 300×120, radius 12. Well inside, away from the label.
        #expect(pixels.rgb(x: 40, y: 80) == Self.fill)
        // Blank: 10,290 300×60, no radius.
        #expect(pixels.rgb(x: 40, y: 300) == Self.fill)
    }

    @Test("The corner radius clips the placeholder")
    func clippedToRadius() throws {
        let pixels = try Pixels(render(), scale: Self.scale)
        // Web's top-left corner pixel is outside a 12pt radius: the root's white shows.
        #expect(pixels.rgb(x: 10.25, y: 60.25) == RGB(255, 255, 255))
        // Device's bottom corners are square ([16, 16, 0, 0]): its stroke reaches the corner.
        #expect(pixels.rgb(x: 10.25, y: 279.75) == RGB(0x10, 0xB9, 0x81))
    }

    @Test("With no stroke of its own, a thin neutral border runs inside the edge")
    func defaultBorder() throws {
        let pixels = try Pixels(render(), scale: Self.scale)
        #expect(pixels.rgb(x: 10.25, y: 120) == Self.border)
        #expect(pixels.rgb(x: 309.75, y: 120) == Self.border)
        #expect(pixels.rgb(x: 11.5, y: 120) == Self.fill, "the border is thicker than 1pt")
    }

    @Test("A node's own stroke replaces the placeholder's border")
    func ownStroke() throws {
        let pixels = try Pixels(render(), scale: Self.scale)
        // Device: 10,190 300×90, stroke #10B981, 2pt, inner.
        #expect(pixels.rgb(x: 10.25, y: 235) == RGB(0x10, 0xB9, 0x81))
        #expect(pixels.rgb(x: 11.75, y: 235) == RGB(0x10, 0xB9, 0x81))
    }

    @Test("A node's own effects are drawn: Device's outer shadow darkens the gap below it")
    func ownEffects() throws {
        let pixels = try Pixels(render(), scale: Self.scale)
        let below = pixels.rgb(x: 160, y: 283)
        #expect(below.red < 250, "no shadow under the browser: \(below)")
    }

    @Test("The URL is a small gray label centered in the node", arguments: [
        ("Web", 160.0, 120.0),
        ("Device", 160.0, 235.0),
        ("Blank", 160.0, 320.0),
    ])
    func label(name: String, centerX: Double, centerY: Double) throws {
        let pixels = try Pixels(render(), scale: Self.scale)
        let band = pixels.darkest(xs: centerX - 20 ... centerX + 20, ys: centerY - 5 ... centerY + 5)
        #expect(band.red < 200, "\(name) has no label at its center")
        #expect(band.red >= Self.labelGray.red, "\(name)'s label is darker than the label gray")
        let above = pixels.darkest(xs: centerX - 20 ... centerX + 20, ys: centerY - 20 ... centerY - 12)
        #expect(above.red > 230, "\(name)'s label is taller than a small label")
    }

    @Test("A URL too long for the node is truncated inside its inset")
    func truncated() throws {
        let pixels = try Pixels(render(), scale: Self.scale)
        // Device: 10…310 wide. The label keeps an inset of its own from the stroke.
        let leftMargin = pixels.darkest(xs: 13 ... 17, ys: 228 ... 242)
        let rightMargin = pixels.darkest(xs: 303 ... 307, ys: 228 ... 242)
        #expect(leftMargin == Self.fill)
        #expect(rightMargin == Self.fill)
        let spansTheWidth = pixels.darkest(xs: 30 ... 50, ys: 228 ... 242)
        #expect(spansTheWidth.red < 200, "a long URL should fill the width before it is cut")
    }
}

// MARK: - Pixel probing

extension PenBrowserRenderTests {
    /// An sRGB color, 8 bits per channel.
    struct RGB: Equatable, CustomStringConvertible {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        var description: String {
            "(\(red), \(green), \(blue))"
        }
    }

    /// A rendered image's pixels, addressed in points.
    struct Pixels {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        let scale: CGFloat

        init(_ image: CGImage, scale: CGFloat) throws {
            let width = image.width
            let height = image.height
            self.width = width
            self.height = height
            self.scale = scale
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
                guard let context = CGContext(
                    data: raw.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            try #require(drawn)
            bytes = buffer
        }

        /// The color at a point, measured from the top-left.
        func rgb(x: Double, y: Double) -> RGB {
            let column = min(width - 1, Int(x * Double(scale)))
            let row = min(height - 1, Int(y * Double(scale)))
            let offset = (row * width + column) * 4
            return RGB(bytes[offset], bytes[offset + 1], bytes[offset + 2])
        }

        /// The pixel with the lowest red channel in a region, in points.
        func darkest(xs: ClosedRange<Double>, ys: ClosedRange<Double>) -> RGB {
            var darkest = RGB(255, 255, 255)
            var y = ys.lowerBound
            while y <= ys.upperBound {
                var x = xs.lowerBound
                while x <= xs.upperBound {
                    let color = rgb(x: x, y: y)
                    if color.red < darkest.red { darkest = color }
                    x += 0.5
                }
                y += 0.5
            }
            return darkest
        }
    }
}
