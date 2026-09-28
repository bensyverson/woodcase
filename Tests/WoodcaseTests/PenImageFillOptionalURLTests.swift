//
//  PenImageFillOptionalURLTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// The 2.17 schema makes an image fill's `url` optional (an image fill can exist
/// with no image assigned yet). Covers decode/encode and every consumer that
/// previously assumed a non-nil `url`.
struct PenImageFillOptionalURLTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Model

    @Test("An image fill with no url decodes to nil")
    func decodesWithoutURL() throws {
        let json = #"{"type":"image","mode":"fill"}"#
        let fill = try decoder.decode(PenFill.self, from: Data(json.utf8))
        guard case let .image(data) = fill else {
            Issue.record("Expected .image, got \(fill)")
            return
        }
        #expect(data.url == nil)
    }

    @Test("An image fill with no url omits the key on encode")
    func encodesWithoutURLOmitsKey() throws {
        let fill = PenFill.image(PenFill.PenImageFill())
        let data = try encoder.encode(fill)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"url\""))
    }

    @Test("An image fill with a url still round-trips")
    func encodesWithURL() throws {
        let fill = PenFill.image(PenFill.PenImageFill(url: "photo.png"))
        let data = try encoder.encode(fill)
        let decoded = try decoder.decode(PenFill.self, from: data)
        #expect(decoded == fill)
    }

    // MARK: - Renderer

    @Test("The renderer skips an image fill with no url instead of crashing")
    func rendererSkipsMissingURL() throws {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 10, height: 10,
            bitsPerComponent: 8, bytesPerRow: 40,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
        // Should not crash and should not call the image provider.
        var providerCalled = false
        PenFillRenderer.renderFills(
            .single(.image(PenFill.PenImageFill())),
            clip: path, fillRule: .winding, domain: path.boundingBox, in: context,
            imageProvider: { _ in providerCalled = true; return nil }
        )
        #expect(!providerCalled)
    }

    // MARK: - ComponentAnalyzer

    @Test("ComponentAnalyzer skips an image fill with no url when inferring a prop")
    func componentAnalyzerSkipsMissingURL() {
        let imageNode = PenNode(
            id: "img1",
            common: PenNodeCommon(name: "Thumbnail"),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.image(PenFill.PenImageFill()))))
        )
        let component = PenNode(
            id: "comp",
            common: PenNodeCommon(
                name: "Component/Card",
                reusable: true,
                metadata: ["type": "component", "_props": .dictionary(["image": .string("Thumbnail")])]
            ),
            kind: .frame(PenNode.FrameData(children: [imageNode]))
        )
        let document = PenDocument(version: "2.9", children: [component])

        let components = ComponentAnalyzer.analyze(document)

        #expect(!components[0].props.contains { $0.type == .imageURL })
    }

    // MARK: - ReactEmitter+Images

    @Test("collectImageURLs(from:) skips an image fill with no url")
    func collectImageURLsSkipsMissingURL() {
        let node = PenNode(
            id: "r1", common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.image(PenFill.PenImageFill()))))
        )
        #expect(ReactEmitter.collectImageURLs(from: node).isEmpty)
    }
}
