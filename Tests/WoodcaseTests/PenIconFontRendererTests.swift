//
//  PenIconFontRendererTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Testing
@testable import Woodcase

struct PenIconFontRendererTests {
    // MARK: - Helpers

    private func renderIconFont(
        _ data: PenNode.IconData,
        rect: PenRect = PenRect(x: 0, y: 0, width: 48, height: 48)
    ) -> CGImage? {
        let node = PenNode(
            id: "icon1",
            common: PenNodeCommon(),
            kind: .icon(data)
        )
        let size = CGSize(width: Double(rect.width), height: Double(rect.height))
        let doc = PenDocument(version: "2.9", children: [node])
        let layoutRects: [String: PenRect] = [node.id: rect]
        return PenRenderer.render(doc, layoutRects: layoutRects, size: size)
    }

    private func hasAnyInk(_ image: CGImage) -> Bool {
        let w = image.width
        let h = image.height
        let bpr = w * 4
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        for i in stride(from: 3, to: pixels.count, by: 4) {
            if pixels[i] > 0 { return true }
        }
        return false
    }

    /// Raw RGBA pixel bytes of `image`, for exact-equality comparisons between two renders.
    private func pixelBytes(of image: CGImage) -> [UInt8] {
        let w = image.width
        let h = image.height
        let bpr = w * 4
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }

    // MARK: - Tests

    @Test("Known lucide icon renders non-blank")
    func lucideIconRendersInk() throws {
        let data = PenNode.IconData(
            icon: .literal("bell"),
            library: .literal("lucide"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let image = try #require(renderIconFont(data))
        #expect(hasAnyInk(image), "Known lucide icon should render visible pixels")
    }

    @Test("Unknown icon in a known library renders that library's question-mark placeholder")
    func unknownIconRendersPlaceholder() throws {
        // Pen.app's own engine renders the library's question-mark glyph for a
        // name it cannot resolve (verified with `pen interactive`, see leaf AuqQs),
        // rather than nothing — this pins Woodcase to the same substitution by
        // checking the unresolved render is pixel-identical to rendering the
        // placeholder icon directly, not just "some ink appeared."
        let unresolved = PenNode.IconData(
            icon: .literal("nonexistent-icon-xyz-999"),
            library: .literal("lucide"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let placeholder = PenNode.IconData(
            icon: .literal("circle-question-mark"),
            library: .literal("lucide"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let unresolvedImage = try #require(renderIconFont(unresolved))
        let placeholderImage = try #require(renderIconFont(placeholder))
        #expect(hasAnyInk(unresolvedImage), "Unknown icon should render the placeholder, not blank")
        #expect(
            pixelBytes(of: unresolvedImage) == pixelBytes(of: placeholderImage),
            "Unknown icon should render pixel-identical to lucide's circle-question-mark"
        )
    }

    @Test("Unknown icon in feather renders help-circle")
    func unknownFeatherIconRendersPlaceholder() throws {
        let unresolved = PenNode.IconData(
            icon: .literal("nonexistent-icon-xyz-999"),
            library: .literal("feather"),
            width: .fixed(24),
            height: .fixed(24),
            fills: .single(.shorthand("#000000"))
        )
        let placeholder = PenNode.IconData(
            icon: .literal("help-circle"),
            library: .literal("feather"),
            width: .fixed(24),
            height: .fixed(24),
            fills: .single(.shorthand("#000000"))
        )
        let unresolvedImage = try #require(renderIconFont(unresolved))
        let placeholderImage = try #require(renderIconFont(placeholder))
        #expect(pixelBytes(of: unresolvedImage) == pixelBytes(of: placeholderImage))
    }

    @Test("Unknown icon in phosphor renders question")
    func unknownPhosphorIconRendersPlaceholder() throws {
        let unresolved = PenNode.IconData(
            icon: .literal("nonexistent-icon-xyz-999"),
            library: .literal("phosphor"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let placeholder = PenNode.IconData(
            icon: .literal("question"),
            library: .literal("phosphor"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let unresolvedImage = try #require(renderIconFont(unresolved))
        let placeholderImage = try #require(renderIconFont(placeholder))
        #expect(pixelBytes(of: unresolvedImage) == pixelBytes(of: placeholderImage))
    }

    @Test("Unknown icon in Material Symbols renders help")
    func unknownMaterialSymbolsIconRendersPlaceholder() throws {
        let unresolved = PenNode.IconData(
            icon: .literal("nonexistent-icon-xyz-999"),
            library: .literal("Material Symbols Outlined"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let placeholder = PenNode.IconData(
            icon: .literal("help"),
            library: .literal("Material Symbols Outlined"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let unresolvedImage = try #require(renderIconFont(unresolved))
        let placeholderImage = try #require(renderIconFont(placeholder))
        #expect(pixelBytes(of: unresolvedImage) == pixelBytes(of: placeholderImage))
    }

    @Test("Unknown icon in an unbundled family still renders blank")
    func unknownFamilyIconRendersBlank() throws {
        // No placeholder is known for a family Woodcase never bundled a font for,
        // so this stays the pre-existing behavior rather than drawing anything.
        let data = PenNode.IconData(
            icon: .literal("whatever"),
            library: .literal("not-a-real-family-xyz"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let image = try #require(renderIconFont(data))
        #expect(!hasAnyInk(image), "Icon in an unbundled family should render blank")
    }

    @Test("Icon font with no family renders blank")
    func noFamilyRendersBlank() throws {
        let data = PenNode.IconData(
            icon: .literal("bell"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let image = try #require(renderIconFont(data))
        #expect(!hasAnyInk(image), "Icon with no family should render blank")
    }

    @Test("Phosphor icon renders non-blank")
    func phosphorIconRendersInk() throws {
        let data = PenNode.IconData(
            icon: .literal("chat-dots"),
            library: .literal("phosphor"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let image = try #require(renderIconFont(data))
        #expect(hasAnyInk(image), "Known phosphor icon should render visible pixels")
    }

    @Test("Phosphor icon with weight suffix renders non-blank")
    func phosphorWeightSuffixRendersInk() throws {
        let data = PenNode.IconData(
            icon: .literal("chat-dots-thin"),
            library: .literal("phosphor"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let image = try #require(renderIconFont(data))
        #expect(hasAnyInk(image), "Phosphor icon with weight suffix should render visible pixels")
    }

    @Test("Material Symbols icon renders non-blank")
    func materialSymbolsRendersInk() throws {
        let data = PenNode.IconData(
            icon: .literal("home"),
            library: .literal("Material Symbols Outlined"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#000000"))
        )
        let image = try #require(renderIconFont(data))
        #expect(hasAnyInk(image), "Known Material Symbols icon should render visible pixels")
    }

    @Test("Feather icon renders non-blank")
    func featherIconRendersInk() throws {
        let data = PenNode.IconData(
            icon: .literal("bell"),
            library: .literal("feather"),
            width: .fixed(24),
            height: .fixed(24),
            fills: .single(.shorthand("#000000"))
        )
        let image = try #require(renderIconFont(data))
        #expect(hasAnyInk(image), "Known feather icon should render visible pixels")
    }

    @Test("Fill color is applied to icon")
    func fillColorApplied() throws {
        let data = PenNode.IconData(
            icon: .literal("bell"),
            library: .literal("lucide"),
            width: .fixed(48),
            height: .fixed(48),
            fills: .single(.shorthand("#FF0000"))
        )
        let image = try #require(renderIconFont(data))
        let w = image.width
        let h = image.height
        let bpr = w * 4
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            Issue.record("Failed to create pixel context")
            return
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Find a pixel with ink and verify it has red channel > 0
        var foundRedInk = false
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = pixels[i + 3]
            if a > 0 {
                let r = pixels[i]
                if r > 100 {
                    foundRedInk = true
                    break
                }
            }
        }
        #expect(foundRedInk, "Icon should be rendered in red")
    }
}
