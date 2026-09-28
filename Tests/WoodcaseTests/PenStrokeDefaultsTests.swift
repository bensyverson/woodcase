//
//  PenStrokeDefaultsTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import CoreGraphics
import Testing
@testable import Woodcase

/// Covers the defaults the flat 2.17 stroke keys imply when they are absent.
///
/// Pen.app omits `strokeAlignment: "center"` and `strokeLinejoin: "miter"` on save,
/// so absent means *center* and *miter* — not the `inside` the 2.9 model defaulted to.
struct PenStrokeDefaultsTests {
    private func render(_ node: PenNode) -> CGImage? {
        let document = PenDocument(children: [node])
        let rect = PenRect(x: 20, y: 20, width: 60, height: 60)
        return PenRenderer.render(
            document, layoutRects: [node.id: rect], size: CGSize(width: 100, height: 100)
        )
    }

    private func isRed(_ image: CGImage, x: Int, y: Int) -> Bool {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = y * bytesPerRow + x * 4
        return pixels[offset] > 150 && pixels[offset + 1] < 80 && pixels[offset + 2] < 80
    }

    @Test("A stroke with no alignment straddles the shape edge, as center alignment does")
    func absentAlignmentIsCenter() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FFFFFF")),
                stroke: .single(.shorthand("#FF0000")),
                strokeWidth: .uniform(.literal(8))
            ))
        )
        let image = try #require(render(node))
        // The shape spans 20…80. A centered 8pt stroke paints 16…24 — inside *and* outside
        // the edge; an inner-aligned one would leave x = 18 untouched.
        #expect(isRed(image, x: 18, y: 50), "A centered stroke paints outside the shape edge")
        #expect(isRed(image, x: 22, y: 50), "A centered stroke paints inside the shape edge")
    }

    @Test("An inner stroke stays inside the shape edge")
    func innerAlignmentStaysInside() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FFFFFF")),
                stroke: .single(.shorthand("#FF0000")),
                strokeWidth: .uniform(.literal(8)),
                strokeAlignment: .inner
            ))
        )
        let image = try #require(render(node))
        #expect(!isRed(image, x: 18, y: 50), "An inner stroke must not paint outside the edge")
        #expect(isRed(image, x: 22, y: 50), "An inner stroke paints inside the edge")
    }

    @Test("A node with a stroke width but no stroke paint draws nothing")
    func paintlessStrokeDrawsNothing() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FFFFFF")),
                strokeWidth: .uniform(.literal(8))
            ))
        )
        let image = try #require(render(node))
        #expect(!isRed(image, x: 22, y: 50))
    }

    @Test("A node with a stroke width but no stroke paint emits no border")
    func paintlessStrokeEmitsNoBorder() {
        let styles = ReactEmitter.emitStroke(PenNode.RectangleData(strokeWidth: .uniform(.literal(2))))
        #expect(styles.isEmpty)
    }

    @Test("An absent alignment emits the same inset shadow as an explicit center")
    func absentAlignmentEmitsCenterStyles() {
        let implicit = ReactEmitter.emitStroke(PenNode.RectangleData(
            stroke: .single(.shorthand("#000000")), strokeWidth: .uniform(.literal(2))
        ))
        let explicit = ReactEmitter.emitStroke(PenNode.RectangleData(
            stroke: .single(.shorthand("#000000")),
            strokeWidth: .uniform(.literal(2)),
            strokeAlignment: .center
        ))
        #expect(implicit.map(\.0) == explicit.map(\.0))
        #expect(implicit.map(\.1) == explicit.map(\.1))
        #expect(implicit.first?.0 == "boxShadow")
    }
}
