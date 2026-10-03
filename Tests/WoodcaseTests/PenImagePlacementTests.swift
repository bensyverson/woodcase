//
//  PenImagePlacementTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins ``PenImagePlacement`` to the numbers Pen 1.2.15 draws: each expectation below is a case
/// of `render-image-crops.pen`, read off its reference with a least-squares fit of the UV
/// image's red and green against the pixel position (the image is 256×128; the wide node
/// 200×120, the tall one 100×160).
struct PenImagePlacementTests {
    private typealias Map = PenLayoutEngine.PlaneTransform

    private static let image = PenSize(width: 256, height: 128)
    private static let wide = PenRect(x: 0, y: 0, width: 200, height: 120)
    private static let tall = PenRect(x: 0, y: 0, width: 100, height: 160)

    private static let rightHalf = PenImageTransform(a: 2, tx: -1)
    private static let zoomCenter = PenImageTransform(a: 2, d: 2, tx: -0.5, ty: -0.5)
    private static let shiftedPastEdge = PenImageTransform(a: 1.5, d: 1.5, tx: -0.9, ty: -0.25)
    private static let largerThanImage = PenImageTransform(a: 0.5, d: 0.5, tx: 0.25, ty: 0.25)
    private static let sheared = PenImageTransform(c: 0.3, tx: -0.15)
    private static let quarterTurn = PenImageTransform(a: 0, b: 1, c: -1, d: 0, tx: 1)

    private func place(
        _ placement: PenImageFillMode.Placement,
        _ bounds: PenRect = wide,
        _ transform: PenImageTransform? = nil
    ) throws -> PenImagePlacement {
        try #require(PenImagePlacement(bounds: bounds, imageSize: Self.image, placement: placement, transform: transform))
    }

    private func expectRect(_ rect: PenRect?, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                            sourceLocation: SourceLocation = #_sourceLocation)
    {
        guard let rect else {
            Issue.record("no rect", sourceLocation: sourceLocation)
            return
        }
        let got = [rect.x, rect.y, rect.width, rect.height], want = [x, y, width, height]
        #expect(zip(got, want).allSatisfy { abs($0 - $1) < 1e-9 }, "\(got) ≠ \(want)", sourceLocation: sourceLocation)
    }

    private func expectMap(_ map: Map, _ want: [Double], sourceLocation: SourceLocation = #_sourceLocation) {
        let got = [map.a, map.b, map.c, map.d, map.tx, map.ty]
        #expect(zip(got, want).allSatisfy { abs($0 - $1) < 1e-9 }, "\(got) ≠ \(want)", sourceLocation: sourceLocation)
    }

    private func expectCrop(_ crop: PenImageTransform?, _ want: [Double], sourceLocation: SourceLocation = #_sourceLocation) {
        guard let crop else {
            Issue.record("no crop", sourceLocation: sourceLocation)
            return
        }
        let got = [crop.a, crop.b, crop.c, crop.d, crop.tx, crop.ty]
        #expect(zip(got, want).allSatisfy { abs($0 - $1) < 1e-9 }, "\(got) ≠ \(want)", sourceLocation: sourceLocation)
    }

    // MARK: - Stretch

    @Test("Stretch fills the bounds with the crop box, and does not clip to it")
    func stretchWithoutCrop() throws {
        let placed = try place(.stretch)
        expectRect(placed.cropBox, 0, 0, 200, 120)
        expectMap(placed.imageTransform, [200, 0, 0, 120, 0, 0])
        #expect(placed.clipRect == nil)
    }

    @Test("Stretch draws the image through the crop into the bounds, past the image's edge")
    func stretchShiftedPastEdge() throws {
        let placed = try place(.stretch, Self.wide, Self.shiftedPastEdge)
        expectRect(placed.cropBox, 0, 0, 200, 120)
        // Pen: x = 300u − 180, so the image ends at x 120 and black shows to its right.
        expectMap(placed.imageTransform, [300, 0, 0, 180, -180, -30])
        expectCrop(placed.crop, [1.5, 0, 0, 1.5, -0.9, -0.25])
        #expect(placed.clipRect == nil)
    }

    @Test("Stretch keeps a shear and a quarter turn as written")
    func stretchShearAndTurn() throws {
        try expectMap(place(.stretch, Self.wide, Self.sheared).imageTransform, [200, 0, 60, 120, -30, 0])
        try expectMap(place(.stretch, Self.wide, Self.quarterTurn).imageTransform, [0, 120, -200, 0, 200, 0])
    }

    @Test("Stretch shows a window larger than the image with the image small inside it")
    func stretchLargerThanImage() throws {
        try expectMap(place(.stretch, Self.tall, Self.largerThanImage).imageTransform, [50, 0, 0, 80, 25, 40])
    }

    // MARK: - Cover

    @Test("Cover with no crop covers the bounds, centered")
    func coverWithoutCrop() throws {
        let wide = try place(.cover)
        expectRect(wide.cropBox, -20, 0, 240, 120)
        expectMap(wide.imageTransform, [240, 0, 0, 120, -20, 0])
        #expect(wide.clipRect == nil)
        try expectRect(place(.cover, Self.tall).cropBox, -110, 0, 320, 160)
    }

    @Test("Cover sizes the crop box to the cropped image's aspect: the right half is square")
    func coverRightHalf() throws {
        let placed = try place(.cover, Self.wide, Self.rightHalf)
        expectRect(placed.cropBox, 0, -40, 200, 200)
        expectMap(placed.imageTransform, [400, 0, 0, 200, -200, -40])
        try expectRect(place(.cover, Self.tall, Self.rightHalf).cropBox, -30, 0, 160, 160)
    }

    @Test("Cover zooms into the center of the image")
    func coverZoomCenter() throws {
        try expectMap(place(.cover, Self.wide, Self.zoomCenter).imageTransform, [480, 0, 0, 240, -140, -60])
        try expectMap(place(.cover, Self.tall, Self.zoomCenter).imageTransform, [640, 0, 0, 320, -270, -80])
    }

    @Test("Cover moves a window that passes the image's edge back inside it")
    func coverShiftedPastEdge() throws {
        let placed = try place(.cover, Self.wide, Self.shiftedPastEdge)
        expectCrop(placed.crop, [1.5, 0, 0, 1.5, -0.5, -0.25])
        expectRect(placed.cropBox, -20, 0, 240, 120)
        expectMap(placed.imageTransform, [360, 0, 0, 180, -140, -30])
    }

    @Test("Cover shrinks a window larger than the image to the whole image")
    func coverLargerThanImage() throws {
        let placed = try place(.cover, Self.wide, Self.largerThanImage)
        expectCrop(placed.crop, [1, 0, 0, 1, 0, 0])
        expectMap(placed.imageTransform, [240, 0, 0, 120, -20, 0])
    }

    @Test("Cover shrinks a sheared window until its bounds fit the image, about its center")
    func coverSheared() throws {
        // The sheared window's bounds in the image are 1.3 wide: shrunk by 1/1.3 about (0.5, 0.5).
        let placed = try place(.cover, Self.wide, Self.sheared)
        expectCrop(placed.crop, [1.3, 0, 0.39, 1.3, -0.345, -0.15])
        // The crop box's sides are the crop axes' lengths in image pixels, 256 and |(-76.8, 128)|,
        // over 1.3; it covers 200×120 by its height.
        let width = 120 * 256 / (76.8 * 76.8 + 128 * 128).squareRoot()
        expectRect(placed.cropBox, (200 - width) / 2, 0, width, 120)
        expectMap(
            placed.imageTransform,
            [width * 1.3, 0, width * 0.39, 156, (200 - width) / 2 - width * 0.345, -18]
        )
    }

    @Test("Cover turns the crop box with a quarter-turned crop")
    func coverQuarterTurn() throws {
        let placed = try place(.cover, Self.wide, Self.quarterTurn)
        expectRect(placed.cropBox, 0, -140, 200, 400)
        expectMap(placed.imageTransform, [0, 400, -200, 0, 200, -140])
    }

    // MARK: - Contain

    @Test("Contain with no crop fits the bounds, centered, and clips to the crop box")
    func containWithoutCrop() throws {
        let placed = try place(.contain)
        expectRect(placed.cropBox, 0, 10, 200, 100)
        expectMap(placed.imageTransform, [200, 0, 0, 100, 0, 10])
        expectRect(placed.clipRect, 0, 10, 200, 100)
        try expectRect(place(.contain, Self.tall).cropBox, 0, 55, 100, 50)
    }

    @Test("Contain fits the cropped image's aspect and clips to it")
    func containRightHalf() throws {
        let placed = try place(.contain, Self.wide, Self.rightHalf)
        expectRect(placed.cropBox, 40, 0, 120, 120)
        expectMap(placed.imageTransform, [240, 0, 0, 120, -80, 0])
        expectRect(placed.clipRect, 40, 0, 120, 120)
    }

    @Test("Contain never moves the window: past the image's edge it shows nothing")
    func containShiftedPastEdge() throws {
        let placed = try place(.contain, Self.wide, Self.shiftedPastEdge)
        expectCrop(placed.crop, [1.5, 0, 0, 1.5, -0.9, -0.25])
        expectRect(placed.cropBox, 0, 10, 200, 100)
        expectMap(placed.imageTransform, [300, 0, 0, 150, -180, -15])
    }

    @Test("Contain never shrinks a window larger than the image")
    func containLargerThanImage() throws {
        // The crop box is the 2:1 window at 100×50; the image is the middle half of it.
        let placed = try place(.contain, Self.tall, Self.largerThanImage)
        expectRect(placed.cropBox, 0, 55, 100, 50)
        expectMap(placed.imageTransform, [50, 0, 0, 25, 25, 67.5])
    }

    @Test("Contain sizes a sheared crop box by its axes' lengths in image pixels")
    func containSheared() throws {
        let height = 200 * (76.8 * 76.8 + 128 * 128).squareRoot() / 256
        let placed = try place(.contain, Self.wide, Self.sheared)
        expectRect(placed.cropBox, 0, (120 - height) / 2, 200, height)
        expectMap(placed.imageTransform, [200, 0, 60, height, -30, (120 - height) / 2])
    }

    @Test("Contain turns the crop box with a quarter-turned crop")
    func containQuarterTurn() throws {
        let placed = try place(.contain, Self.wide, Self.quarterTurn)
        expectRect(placed.cropBox, 70, 0, 60, 120)
        expectMap(placed.imageTransform, [0, 120, -60, 0, 130, 0])
        try expectRect(place(.contain, Self.tall, Self.quarterTurn).cropBox, 10, 0, 80, 160)
    }

    // MARK: - Bounds, fills and degenerate input

    @Test("Placement is in the bounds' own space")
    func boundsOffset() throws {
        let bounds = PenRect(x: 40, y: 30, width: 200, height: 120)
        let placed = try place(.contain, bounds, Self.rightHalf)
        expectRect(placed.cropBox, 80, 30, 120, 120)
        expectMap(placed.imageTransform, [240, 0, 0, 120, -40, 30])
    }

    @Test("A fill with no mode is placed as cover, through its own transform")
    func fillDefaultsToCover() throws {
        let fill = PenFill.PenImageFill(url: "x.png", transform: Self.zoomCenter)
        let placed = try #require(PenImagePlacement(bounds: Self.wide, imageSize: Self.image, fill: fill))
        expectMap(placed.imageTransform, [480, 0, 0, 240, -140, -60])
    }

    @Test("Nothing is placed for an empty image, empty bounds or a singular crop")
    func degenerateInput() {
        #expect(PenImagePlacement(bounds: Self.wide, imageSize: .zero, placement: .cover, transform: nil) == nil)
        #expect(PenImagePlacement(
            bounds: PenRect(x: 0, y: 0, width: 0, height: 10), imageSize: Self.image, placement: .stretch, transform: nil
        ) == nil)
        #expect(PenImagePlacement(
            bounds: Self.wide, imageSize: Self.image, placement: .stretch, transform: PenImageTransform(a: 0)
        ) == nil)
    }

    @Test("The cover adjustment leaves a window already inside the image alone")
    func keptInsideImageIsIdentityInside() {
        expectCrop(PenImagePlacement.keptInsideImage(Self.zoomCenter), [2, 0, 0, 2, -0.5, -0.5])
        expectCrop(PenImagePlacement.keptInsideImage(Self.quarterTurn), [0, 1, -1, 0, 1, 0])
    }

    @Test("The unscaled crop box is the image's pixel size over the crop's scale")
    func cropBoxSize() throws {
        let size = try #require(PenImagePlacement.cropBoxSize(imageSize: Self.image, crop: Self.rightHalf))
        #expect(size == PenSize(width: 128, height: 128))
        let turned = try #require(PenImagePlacement.cropBoxSize(imageSize: Self.image, crop: Self.quarterTurn))
        #expect(turned == PenSize(width: 128, height: 256))
    }
}
