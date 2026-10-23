//
//  PenImageCropRectTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// An image fill's crop written from a pixel rect: the rect becomes the fill's
/// `transform`, and ``PenImagePlacement`` then shows exactly that rect — the contract
/// Penumbra's crop mode writes through (interaction spec §12).
struct PenImageCropRectTests {
    /// The size of `images/uv-map.png`, the image the Pen references crop.
    private static let image = PenSize(width: 256, height: 128)

    /// An off-center crop that is neither a half nor a zoom about the center.
    private static let rect = PenRect(x: 40, y: 20, width: 120, height: 80)

    // MARK: - Pixel rect ⇄ transform

    @Test("a pixel rect (cx, cy, cw, ch) of a W×H image is [W/cw, 0, 0, H/ch, -cx/cw, -cy/ch]")
    func rectToTransform() throws {
        let crop = try #require(PenImageTransform(cropping: Self.rect, imageSize: Self.image))

        expectClose(crop, PenImageTransform(a: 256.0 / 120, b: 0, c: 0, d: 128.0 / 80, tx: -40.0 / 120, ty: -20.0 / 80))
    }

    @Test("the right half of the image is the fixture's right-half crop, [2, 0, 0, 1, -1, 0]")
    func rightHalfMatchesTheFixture() throws {
        let crop = try #require(PenImageTransform(
            cropping: PenRect(x: 128, y: 0, width: 128, height: 128), imageSize: Self.image
        ))

        expectClose(crop, PenImageTransform(a: 2, b: 0, c: 0, d: 1, tx: -1, ty: 0))
    }

    @Test("the whole image is the identity, and the identity crops the whole image")
    func wholeImageIsIdentity() throws {
        let whole = PenRect(x: 0, y: 0, width: 256, height: 128)

        try expectClose(#require(PenImageTransform(cropping: whole, imageSize: Self.image)), .identity)
        try expectClose(#require(PenImageTransform.identity.cropRect(imageSize: Self.image)), whole)
    }

    @Test("a transform turns back into the pixel rect it was made from")
    func roundTrip() throws {
        let crop = try #require(PenImageTransform(cropping: Self.rect, imageSize: Self.image))

        try expectClose(#require(crop.cropRect(imageSize: Self.image)), Self.rect)
    }

    @Test("the crop is in fractions of the image, so the same transform crops the same part of a larger copy")
    func resolutionIndependent() throws {
        let crop = try #require(PenImageTransform(cropping: Self.rect, imageSize: Self.image))

        try expectClose(
            #require(crop.cropRect(imageSize: PenSize(width: 512, height: 256))),
            PenRect(x: 80, y: 40, width: 240, height: 160)
        )
    }

    @Test("a sheared or turned transform has no pixel rect")
    func shearedHasNoRect() {
        #expect(PenImageTransform(a: 1, b: 0, c: 0.3, d: 1, tx: -0.15, ty: 0).cropRect(imageSize: Self.image) == nil)
        #expect(PenImageTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0).cropRect(imageSize: Self.image) == nil)
        #expect(PenImageTransform(a: 0, b: 0, c: 0, d: 1).cropRect(imageSize: Self.image) == nil)
    }

    @Test("an empty rect, an empty image or a non-finite number makes no transform")
    func degenerateRects() {
        #expect(PenImageTransform(cropping: PenRect(x: 0, y: 0, width: 0, height: 10), imageSize: Self.image) == nil)
        #expect(PenImageTransform(cropping: Self.rect, imageSize: PenSize(width: 0, height: 128)) == nil)
        #expect(PenImageTransform(cropping: PenRect(x: .nan, y: 0, width: 10, height: 10), imageSize: Self.image) == nil)
    }

    // MARK: - The placement shows exactly the rect

    @Test(
        "in every mode, a box of the crop's aspect shows exactly the pixel rect",
        arguments: PenImageFillMode.Placement.allCases
    )
    func placementShowsTheRect(_ placement: PenImageFillMode.Placement) throws {
        let crop = try #require(PenImageTransform(cropping: Self.rect, imageSize: Self.image))
        let bounds = PenRect(x: 10, y: 30, width: 240, height: 160)

        let placed = try #require(PenImagePlacement(
            bounds: bounds, imageSize: Self.image, placement: placement, transform: crop
        ))

        expectClose(placed.crop, crop)
        try expectClose(shownPixels(of: bounds, in: placed), Self.rect)
    }

    @Test("stretch shows exactly the rect in a box of any aspect")
    func stretchShowsTheRectInAnyBox() throws {
        let crop = try #require(PenImageTransform(cropping: Self.rect, imageSize: Self.image))
        let bounds = PenRect(x: 0, y: 0, width: 200, height: 200)

        let placed = try #require(PenImagePlacement(
            bounds: bounds, imageSize: Self.image, placement: .stretch, transform: crop
        ))

        try expectClose(shownPixels(of: bounds, in: placed), Self.rect)
    }

    @Test("contain clips to a crop box that shows exactly the rect in a box of any aspect")
    func containClipsToTheRect() throws {
        let crop = try #require(PenImageTransform(cropping: Self.rect, imageSize: Self.image))
        let bounds = PenRect(x: 0, y: 0, width: 200, height: 200)

        let placed = try #require(PenImagePlacement(
            bounds: bounds, imageSize: Self.image, placement: .contain, transform: crop
        ))

        try expectClose(shownPixels(of: #require(placed.clipRect), in: placed), Self.rect)
    }

    @Test("cover in a box of another aspect shows the middle of the rect, never more")
    func coverTrimsTheRect() throws {
        let crop = try #require(PenImageTransform(cropping: Self.rect, imageSize: Self.image))
        let bounds = PenRect(x: 0, y: 0, width: 200, height: 200)

        let placed = try #require(PenImagePlacement(
            bounds: bounds, imageSize: Self.image, placement: .cover, transform: crop
        ))

        // The 120×80 rect covers a square box by its height: the middle 80×80.
        try expectClose(shownPixels(of: bounds, in: placed), PenRect(x: 60, y: 20, width: 80, height: 80))
    }

    // MARK: - Helpers

    /// The image pixels a rect of the bounds' space shows: the rect mapped back through
    /// the placement's image transform, in pixels.
    private func shownPixels(of rect: PenRect, in placed: PenImagePlacement) throws -> PenRect {
        let back = try #require(placed.imageTransform.inverted()).bounds(of: rect)
        return PenRect(
            x: back.x * Self.image.width, y: back.y * Self.image.height,
            width: back.width * Self.image.width, height: back.height * Self.image.height
        )
    }

    private func expectClose(
        _ actual: PenImageTransform,
        _ expected: PenImageTransform,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let pairs = [
            (actual.a, expected.a), (actual.b, expected.b), (actual.c, expected.c),
            (actual.d, expected.d), (actual.tx, expected.tx), (actual.ty, expected.ty),
        ]
        #expect(pairs.allSatisfy { abs($0 - $1) < 1e-9 }, "\(actual) ≠ \(expected)", sourceLocation: sourceLocation)
    }

    private func expectClose(_ actual: PenRect, _ expected: PenRect, sourceLocation: SourceLocation = #_sourceLocation) {
        let pairs = [
            (actual.x, expected.x), (actual.y, expected.y),
            (actual.width, expected.width), (actual.height, expected.height),
        ]
        #expect(pairs.allSatisfy { abs($0 - $1) < 1e-9 }, "\(actual) ≠ \(expected)", sourceLocation: sourceLocation)
    }
}
