//
//  PenRendererGroupBlendTests.swift
//  Woodcase
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A node with a blend mode blends as one isolated group — its paints, effects and children
/// drawn at the normal blend together, then blended with what lies beneath at the node's
/// mode and opacity — as CSS's `mix-blend-mode` and Figma do (the integrator's ruling of
/// 2026-10-20, under Ben's W3C ruling). Node-level `blendMode` is Woodcase's own; Pen drops
/// it on load, so there is no Pen parity to check.
///
/// `group-blend.pen` is RapidPro's fixture (`Tests/RapidProTests/Fixtures/group-blend.pen`,
/// RapidPro 71e6d92), copied unchanged: for each case, the case; `<case>.backdrop`, the
/// case without its blended node; and `<case>.content`, the blended node alone at the
/// normal blend on a transparent artboard. The oracle draws the content over the backdrop
/// at the node's mode and opacity — multiply and screen, which Core Graphics draws exactly.
/// Each case is a 200×200 white artboard whose top half is yellow: a multiply group of two
/// overlapping cards, a filled multiply frame holding them, a multiply rectangle with a
/// 24 pt centered stroke, the frame in screen, the frame with a layer blur, the frame at
/// 50 % opacity, and a single-paint multiply rectangle.
struct PenRendererGroupBlendTests {
    private static let fixture = "group-blend"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    private static let scale: CGFloat = 2

    /// Every case, with its blended node's mode and opacity.
    private static let cases: [String: (mode: CGBlendMode, opacity: CGFloat)] = [
        "multiply-group": (.multiply, 1),
        "multiply-frame": (.multiply, 1),
        "fill-stroke": (.multiply, 1),
        "screen-frame": (.screen, 1),
        "multiply-blur": (.multiply, 1),
        "multiply-half": (.multiply, 0.5),
        "single-paint": (.multiply, 1),
    ]

    /// The bar, in 8-bit steps. The oracle and the render draw the same paints by the same
    /// Core Graphics calls, so only rounding through the extra layer separates them.
    private static let threshold = 0.25

    private static func artboard(_ name: String) throws -> CGImage {
        let image = try PenSnapshotTestHelpers.renderArtboard(
            named: name, in: fixture, fixturesDir: fixturesDir, scale: scale
        )
        return try #require(image)
    }

    /// `content` drawn over `backdrop` at `mode` and `opacity`.
    private static func composite(
        _ content: CGImage, _ mode: CGBlendMode, _ opacity: CGFloat, over backdrop: CGImage
    ) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: backdrop.width, height: backdrop.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let bounds = CGRect(x: 0, y: 0, width: backdrop.width, height: backdrop.height)
        context.draw(backdrop, in: bounds)
        context.setBlendMode(mode)
        context.setAlpha(opacity)
        context.draw(content, in: bounds)
        return try #require(context.makeImage())
    }

    @Test(arguments: cases.keys.sorted())
    func `Each case matches its content composited over its backdrop`(name: String) throws {
        let blend = try #require(Self.cases[name])
        let oracle = try Self.composite(
            Self.artboard("\(name).content"), blend.mode, blend.opacity, over: Self.artboard("\(name).backdrop")
        )
        let mae = try PenSnapshotTestHelpers.meanAbsoluteError(between: Self.artboard(name), and: oracle)
        #expect(mae <= Self.threshold, "\(name): MAE \(mae)")
    }

    /// Where the blue card covers the red one over the yellow, the group shows blue alone
    /// multiplied onto yellow: #60A5FA × #FACC15 = (94, 132, 21). Blending each card on its
    /// own multiplies blue × red × yellow, #530F06.
    @Test func `Overlapping children of a multiply group blend normally with each other`() throws {
        let grid = try #require(PixelGrid(Self.artboard("multiply-group")))
        let pixel = grid.pixel(100 * 2, 60 * 2)
        let expected = PixelGrid.RGBA(r: 94, g: 132, b: 21, a: 255)
        #expect((0 ..< 4).allSatisfy { abs(pixel[$0] - expected[$0]) <= 2 }, "\(pixel)")
    }
}
