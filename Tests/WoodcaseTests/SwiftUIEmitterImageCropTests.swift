//
//  SwiftUIEmitterImageCropTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the SwiftUI emitter places a format 2.20 image paint: a missing mode is cover, and a
/// crop (`transform`) is drawn through the support file's `PenImageCrop`, which places the crop
/// box as ``PenImagePlacement`` does. ``SwiftUIRenderTests`` measures the result against Pen's
/// renders of `render-image-crops.pen`; these pin each decision.
struct SwiftUIEmitterImageCropTests {
    private static let local = "./images/uv-map.png"
    private static let bundled = ##"Image(penResource: "uv-map.png", bundle: .module)"##

    @Test("A 2.20 image paint with no mode is cover: scaled to fill and centered")
    func missingModeIsCover() throws {
        let code = try body(fill: ##"{"type": "image", "url": "\##(Self.local)"}"##)
        #expect(code.contains(".scaledToFill()"))
        #expect(code.contains("Color.clear"))
    }

    @Test("A 2.20 remote image paint with no mode is cover too")
    func remoteMissingModeIsCover() throws {
        let code = try body(fill: ##"{"type": "image", "url": "https://example.com/a.png"}"##)
        #expect(code.contains(".scaledToFill()"))
    }

    @Test("A cropped image is drawn through PenImageCrop with its mode and crop, not scaled by SwiftUI")
    func cropIsPenImageCrop() throws {
        let code = try body(fill: ##"{"type": "image", "url": "\##(Self.local)", "mode": "contain", "transform": [2, 0, 0, 1, -1, 0]}"##)
        #expect(code.contains(
            "PenImageCrop(\(Self.bundled), placement: .contain, crop: CGAffineTransform(a: 2, b: 0, c: 0, d: 1, tx: -1, ty: 0))"
        ))
        #expect(!code.contains(".scaledTo"))
        #expect(!code.contains(".resizable()"))
    }

    @Test("A stretched crop keeps its crop as written, past the image's edge")
    func stretchCropAsWritten() throws {
        let code = try body(fill: ##"{"type": "image", "url": "\##(Self.local)", "mode": "stretch", "transform": [1.5, 0, 0, 1.5, -0.9, -0.25]}"##)
        #expect(code.contains("placement: .stretch, crop: CGAffineTransform(a: 1.5, b: 0, c: 0, d: 1.5, tx: -0.9, ty: -0.25))"))
    }

    @Test("A cover crop is written already kept inside the image, so the view never moves it")
    func coverCropKeptInside() throws {
        let shifted = try body(fill: ##"{"type": "image", "url": "\##(Self.local)", "transform": [1.5, 0, 0, 1.5, -0.9, -0.25]}"##)
        #expect(shifted.contains("placement: .cover, crop: CGAffineTransform(a: 1.5, b: 0, c: 0, d: 1.5, tx: -0.5, ty: -0.25))"))
        let sheared = try body(fill: ##"{"type": "image", "url": "\##(Self.local)", "mode": "cover", "transform": [1, 0, 0.3, 1, -0.15, 0]}"##)
        #expect(sheared.contains("placement: .cover, crop: CGAffineTransform(a: 1.3, b: 0, c: 0.39, d: 1.3, tx: -0.345, ty: -0.15))"))
    }

    @Test("A cropped remote image is drawn through PenImageCrop inside AsyncImage's content closure")
    func remoteCrop() throws {
        let code = try body(fill: ##"{"type": "image", "url": "https://example.com/a.png", "mode": "contain", "transform": [2, 0, 0, 2, -0.5, -0.5]}"##)
        #expect(code.contains(##"AsyncImage(url: URL(string: "https://example.com/a.png"))"##))
        #expect(code.contains("PenImageCrop(image, placement: .contain, crop: CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: -0.5, ty: -0.5))"))
        #expect(!code.contains(".scaledTo"))
    }

    @Test("The paint support file holds PenImageCrop, which sizes the crop box from the image's own size")
    func supportTemplate() throws {
        let support = try #require(SwiftUIEmitter.supportTemplates()["PenSupport+Image.swift"])
        #expect(support.contains("struct PenImageCrop: View"))
        #expect(support.contains("context.resolve(image)"))
    }

    // MARK: - Helpers

    private func body(fill: String) throws -> String {
        let json = ##"""
        {"version": "2.20", "children": [{"type": "frame", "id": "root", "name": "Board", "children": [
          {"type": "rectangle", "id": "r", "width": 200, "height": 120, "fill": \##(fill)}
        ]}]}
        """##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        )
        return try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
    }
}
