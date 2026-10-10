import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Woodcase

/// Pins what an icon renderer draws from: the glyph's one Core Text line, where that line
/// sits in Core Text's y-up space over the box, the map back to the box's y-down space,
/// the glyph's outlines and its tight ink — so Woodcase's CG renderer, icon ink and
/// RapidPro's rasterizer all draw the one line ``PenIconGlyph`` sets, with no attributed
/// string of their own.
///
/// Serialized: each case resolves an icon face through Core Text's registry, and parallel
/// cold font lookups have wedged in `fontd` (see `project/gotchas.md`).
@Suite(.serialized)
struct PenIconGlyphDrawingTests {
    /// One icon per bundled library, in square, wide and tall boxes.
    static let cases: [(library: String, icon: String, box: CGSize)] = [
        ("lucide", "bell", CGSize(width: 48, height: 48)),
        ("feather", "chevron-down", CGSize(width: 64, height: 32)),
        ("phosphor", "chat-dots-thin", CGSize(width: 32, height: 64)),
        ("Material Symbols Outlined", "vpn_lock", CGSize(width: 24, height: 24)),
        ("Material Symbols Rounded", "home", CGSize(width: 48.5, height: 31.25)),
        ("Material Symbols Sharp", "search", CGSize(width: 17, height: 23)),
    ]

    private static func glyph(_ probe: (library: String, icon: String, box: CGSize)) throws -> PenIconGlyph {
        try #require(PenIconGlyph(library: probe.library, icon: probe.icon, weight: nil, box: probe.box))
    }

    /// The glyph's outline bounds in its font, y up from the baseline at the pen.
    private static func outline(of glyph: PenIconGlyph) throws -> CGRect {
        let characters = Array(glyph.string.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        #expect(CTFontGetGlyphsForCharacters(glyph.font, characters, &glyphs, characters.count))
        return try #require(CTFontCreatePathForGlyph(glyph.font, glyphs[0], nil)).boundingBoxOfPath
    }

    @Test("The glyph keeps the box it was placed in", arguments: cases.indices)
    func keepsItsBox(_ index: Int) throws {
        let probe = Self.cases[index]
        #expect(try Self.glyph(probe).box == probe.box)
    }

    @Test("The line sets the glyph's one character in its face and the given color", arguments: cases.indices)
    func lineSetsTheGlyph(_ index: Int) throws {
        let glyph = try Self.glyph(Self.cases[index])
        let color = CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let line = glyph.line(color: color)
        let runs = try #require(CTLineGetGlyphRuns(line) as? [CTRun])
        #expect(runs.count == 1)
        let attributes = try #require(CTRunGetAttributes(runs[0]) as? [CFString: Any])
        let font = try #require(attributes[kCTFontAttributeName].map { $0 as! CTFont })
        #expect(CFEqual(font, glyph.font))
        let foreground = try #require(attributes[kCTForegroundColorAttributeName].map { $0 as! CGColor })
        #expect(foreground == color)
        #expect(CTLineGetStringRange(line).length == glyph.string.utf16.count)
    }

    @Test("A line built without a color is opaque black, as a text layout's is")
    func lineDefaultsToBlack() throws {
        let line = try Self.glyph(Self.cases[0]).line()
        let run = try #require((CTLineGetGlyphRuns(line) as? [CTRun])?.first)
        let attributes = try #require(CTRunGetAttributes(run) as? [CFString: Any])
        let foreground = try #require(attributes[kCTForegroundColorAttributeName].map { $0 as! CGColor })
        #expect(foreground == PenTextLayout.defaultColor)
    }

    @Test("The line's origin is the glyph's origin in Core Text's y-up space over the box", arguments: cases.indices)
    func lineOriginIsFlipped(_ index: Int) throws {
        let probe = Self.cases[index]
        let glyph = try Self.glyph(probe)
        #expect(glyph.lineOrigin == CGPoint(x: glyph.origin.x, y: probe.box.height - glyph.origin.y))
    }

    @Test("The text space maps the line's origin back onto the glyph's origin", arguments: cases.indices)
    func textSpaceMapsBack(_ index: Int) throws {
        let glyph = try Self.glyph(Self.cases[index])
        let mapped = glyph.lineOrigin.applying(glyph.textSpace)
        #expect(abs(mapped.x - glyph.origin.x) < 1e-9)
        #expect(abs(mapped.y - glyph.origin.y) < 1e-9)
    }

    @Test("The ink is the glyph's outline at its origin, in the box's y-down space", arguments: cases.indices)
    func inkIsTheOutline(_ index: Int) throws {
        let glyph = try Self.glyph(Self.cases[index])
        let outline = try Self.outline(of: glyph)
        let ink = try #require(glyph.inkBounds)
        #expect(abs(ink.minX - (glyph.origin.x + outline.minX)) < 1e-9)
        #expect(abs(ink.minY - (glyph.origin.y - outline.maxY)) < 1e-9)
        #expect(abs(ink.width - outline.width) < 1e-9)
        #expect(abs(ink.height - outline.height) < 1e-9)
    }

    @Test("The outlines are the glyph's, in the box's y-down space", arguments: cases.indices)
    func outlinesCoverTheInk(_ index: Int) throws {
        let glyph = try Self.glyph(Self.cases[index])
        let outlines = glyph.outlines()
        let ink = try #require(glyph.inkBounds)
        let bounds = outlines.path.boundingBoxOfPath
        #expect(abs(bounds.minX - ink.minX) < 1e-6 && abs(bounds.minY - ink.minY) < 1e-6)
        #expect(abs(bounds.maxX - ink.maxX) < 1e-6 && abs(bounds.maxY - ink.maxY) < 1e-6)
        #expect(outlines.textSpace == glyph.textSpace)
        #expect(outlines.colorRuns.isEmpty)
    }

    /// Draws `glyph`'s line at its origin into a y-down bitmap of its box.
    private static func drawLine(of glyph: PenIconGlyph, color: CGColor, scale: CGFloat) throws -> [UInt8] {
        let width = Int(glyph.box.width * scale), height = Int(glyph.box.height * scale)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: glyph.box.height)
        context.scaleBy(x: 1, y: -1)
        context.concatenate(glyph.textSpace)
        context.textPosition = glyph.lineOrigin
        CTLineDraw(glyph.line(color: color), context)
        return pixels
    }

    /// `image`'s RGBA bytes, drawn as ``drawLine(of:color:scale:)`` lays them out.
    private static func bytes(of image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    @Test("Drawing the line at its origin is exactly what the CG renderer draws", arguments: cases.indices)
    func lineDrawsWhatTheRendererDraws(_ index: Int) throws {
        let probe = Self.cases[index]
        let glyph = try Self.glyph(probe)
        let data = PenNode.IconData(
            icon: .literal(probe.icon), library: .literal(probe.library),
            width: .fixed(probe.box.width), height: .fixed(probe.box.height),
            fills: .single(.shorthand("#336699"))
        )
        let node = PenNode(id: "icon", common: PenNodeCommon(), kind: .icon(data))
        let rect = PenRect(x: 0, y: 0, width: probe.box.width, height: probe.box.height)
        let rendered = try #require(PenRenderer.render(
            PenDocument(version: "2.9", children: [node]), layoutRects: ["icon": rect], size: probe.box, scale: 2
        ))
        // #336699, as `PenGlyphPaint` hands it to Core Text.
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let color = try #require(CGColor(colorSpace: sRGB, components: [0.2, 0.4, 0.6, 1]))
        let drawn = try Self.drawLine(of: glyph, color: color, scale: 2)
        let expected = try Self.bytes(of: rendered)
        #expect(drawn == expected)
    }

    @Test("An icon node's ink bounds are its glyph's ink", arguments: cases.indices)
    func nodeInkIsGlyphInk(_ index: Int) throws {
        let probe = Self.cases[index]
        let glyph = try Self.glyph(probe)
        let data = PenNode.IconData(icon: .literal(probe.icon), library: .literal(probe.library))
        let box = PenRect(x: 0, y: 0, width: probe.box.width, height: probe.box.height)
        let ink = try #require(PenLayoutEngine.iconInkBounds(of: data, box: box))
        let expected = try #require(glyph.inkBounds)
        #expect(ink == PenRect(x: expected.minX, y: expected.minY, width: expected.width, height: expected.height))
    }
}
