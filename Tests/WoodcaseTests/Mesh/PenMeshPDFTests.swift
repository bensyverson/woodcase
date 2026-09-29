//
//  PenMeshPDFTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins that a mesh gradient reaches a PDF as a raster image, at twice the page's scale.
///
/// A PDF has no primitive CoreGraphics can write for a mesh, so the fill is rasterized.
/// A PDF context's device space is its point space, and a 1x raster of a gradient is
/// soft when zoomed; Pen's own PDF export carries a 2x image (a 200 pt page, a 400 px
/// XObject; `project/2026-09-26-mesh-gradients.md` §3), and Ben ruled that Woodcase
/// does the same.
struct PenMeshPDFTests {
    @Test("A mesh fill in a PDF is an image XObject at 2x the node's box")
    func imageXObjectAtTwiceTheBox() throws {
        let images = try Self.imageXObjects(in: Self.pdf(width: 120, height: 80))
        #expect(images.count == 1)
        let image = try #require(images.first)
        #expect(image.width == 240 && image.height == 160, "XObject \(image.width) × \(image.height)")
    }

    // MARK: - Helpers

    /// A one-page PDF of a frame carrying a 2×2 mesh fill.
    private static func pdf(width: Double, height: Double) throws -> Data {
        let frame = PenNode(
            id: "m",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: .single(.meshGradient(PenFill.PenMeshGradientFill(
                    columns: 2,
                    rows: 2,
                    colors: ["#FF0000", "#00FF00", "#0000FF", "#FFFF00"].map(PenValue.literal),
                    points: [.bare(.init(0, 0)), .bare(.init(1, 0)), .bare(.init(0, 1)), .bare(.init(1, 1))]
                )))
            ))
        )
        let document = PenDocument(version: "2.19", children: [frame])
        let rects = ["m": PenRect(x: 0, y: 0, width: width, height: height)]
        return try PDFExporter.data(pages: [
            PDFExporter.Page(width: width, height: height) { context in
                PenRenderer.render(document, layoutRects: rects, into: context)
            },
        ])
    }

    /// The pixel size of each image XObject on the first page.
    private static func imageXObjects(in data: Data) throws -> [(width: Int, height: Int)] {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let pageDictionary = try #require(page.dictionary)
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDictionary, "Resources", &resources), let resources else { return [] }
        var xObjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects), let xObjects else { return [] }

        var found: [(width: Int, height: Int)] = []
        CGPDFDictionaryApplyBlock(xObjects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream)
            else { return true }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype,
                  String(cString: subtype) == "Image"
            else { return true }
            var width: CGPDFInteger = 0
            var height: CGPDFInteger = 0
            CGPDFDictionaryGetInteger(dictionary, "Width", &width)
            CGPDFDictionaryGetInteger(dictionary, "Height", &height)
            found.append((Int(width), Int(height)))
            return true
        }, nil)
        return found
    }
}
