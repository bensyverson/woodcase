//
//  PenBrowserPlaceholderStyleTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// The browser placeholder's look is one public value that every renderer reads.
struct PenBrowserPlaceholderStyleTests {
    @Test("The standard style is Woodcase's placeholder")
    func standard() {
        let style = PenBrowserPlaceholder.Style.standard
        #expect(style.fillHex == "#F4F4F5")
        #expect(style.borderHex == "#D4D4D8")
        #expect(style.borderWidth == 1)
        #expect(style.borderAlignment == .inner)
        #expect(style.labelHex == "#A1A1AA")
        #expect(style.labelSize == 11)
        #expect(style.labelInset == 12)
        #expect(style.emptyLabel == "browser")
    }

    @Test("The label is the URL as stored, trimmed")
    func labelIsTheURL() {
        let data = PenNode.BrowserData(url: "  https://example.com/a  ")
        #expect(PenBrowserPlaceholder.Style.standard.label(for: data) == "https://example.com/a")
    }

    @Test("A missing or blank URL falls back to the style's empty label", arguments: [nil, "", "  \n"])
    func labelFallsBack(url: String?) {
        var style = PenBrowserPlaceholder.Style.standard
        style.emptyLabel = "web view"
        #expect(style.label(for: PenNode.BrowserData(url: url)) == "web view")
    }

    @Test("The renderer paints with the style it is given")
    func rendererReadsTheStyle() throws {
        var style = PenBrowserPlaceholder.Style.standard
        style.fillHex = "#00FF00"
        style.borderHex = "#FF0000"
        style.borderWidth = 4
        let data = PenNode.BrowserData()
        let node = PenNode(id: "b", common: PenNodeCommon(), kind: .browser(data))
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 100, height: 60, bitsPerComponent: 8, bytesPerRow: 400,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.translateBy(x: 0, y: 60)
        context.scaleBy(x: 1, y: -1)
        PenBrowserPlaceholder.render(
            data, node: node, rect: PenRect(x: 0, y: 0, width: 100, height: 60), style: style, in: context
        )
        let image = try #require(context.makeImage())
        let pixels = try #require(PenFillDomainTests.RGBA(image))
        #expect(pixels.pixel(1, 30) == .init(r: 255, g: 0, b: 0, a: 255), "border")
        #expect(pixels.pixel(8, 8) == .init(r: 0, g: 255, b: 0, a: 255), "fill")
    }
}
