//
//  PreviewFixtures+Render.swift
//  WoodcaseViewer
//

import CoreGraphics
import Foundation
import Woodcase

/// The render every preview artboard is drawn with.
///
/// A state's markup is production markup, so its `<img>` asks the production route —
/// `/files/{file}/artboards/{artboard}.png` — about a fixture file that no host serves.
/// Unanswered, that was WebKit's broken-image glyph with the `alt` text drawn under the
/// overlay, in every state that shows a render (issue `4FmPKE`). So the catalog carries
/// its own picture, and ``ViewerPages`` answers the fixture files' image route with it.
///
/// The picture is the fixture layout drawn as boxes — the header band, the title, the
/// card hanging off the right edge — so a selection box or an edit marker in a preview
/// sits over the thing it names, which is exactly what an overlay review checks. It is
/// a real PNG, drawn at 2× and served as `image/png`, because that is what production
/// answers at the same `.png` address: the markup cannot tell the two routes apart, and
/// a download or a "copy image" of a preview should get the kind of file its URL names.
public extension PreviewFixtures {
    /// Every viewer file id a preview state names, and so every file whose artboard
    /// images the catalog has to answer for.
    ///
    /// `PreviewImagesTests` walks every state's `<img>` and fails on one that points
    /// anywhere else, so a new fixture id is added here or caught there.
    static let fileIDs: [String] = [
        "a1b2c3d4e5f6", "b2c3d4e5f6a1", "c3d4e5f6a1b2", "d4e5f6a1b2c3", "e5f6a1b2c3d4", "a1b2c3",
        ViewerFile(url: URL(fileURLWithPath: "/Users/ana/Designs/banking.pen")).id,
    ]

    /// Device pixels per layout point ``render`` is drawn at — the density the viewer
    /// renders a real artboard at, so the placeholder is as sharp as the thing it stands
    /// in for.
    static let renderScale = 2

    /// The fixture artboard as PNG bytes, drawn from ``layout(scale:)``'s own boxes.
    static let render: Data = {
        let layout = Self.layout()
        let scale = CGFloat(renderScale)
        let width = Int(layout.width) * renderScale
        let height = Int(layout.height) * renderScale
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return Data() }
        // Layout points, top-left origin, the way the boxes are written.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)

        fill(context, CGRect(x: 0, y: 0, width: layout.width, height: layout.height), 0xFFFFFF)
        for node in layout.nodes where node.id != layout.artboard {
            let depth = node.path.split(separator: "/").count - 1
            let box = CGRect(x: node.x, y: node.y, width: node.width, height: node.height)
            switch depth {
            case 1:
                fill(context, box, 0xE8EBF0)
            case _ where node.height > 48:
                fill(context, box, 0xDCE8F7, radius: 8, stroke: 0xA9C3E6)
            default:
                fill(context, box, 0x343A46, radius: 4)
            }
        }
        // Body copy under the header, so the artboard reads as a page and not a diagram.
        for (index, line) in [220, 260, 180, 240].enumerated() {
            fill(context, CGRect(x: 24, y: 96 + index * 28, width: line, height: 10), 0xE1E4EA, radius: 5)
        }
        guard let image = context.makeImage() else { return Data() }
        return (try? PNGEncoder.encode(image)) ?? Data()
    }()

    /// Fills one box, rounded and outlined if asked.
    private static func fill(
        _ context: CGContext, _ box: CGRect, _ color: UInt32, radius: CGFloat = 0, stroke: UInt32? = nil
    ) {
        let path = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(path)
        context.setFillColor(Self.color(color))
        context.fillPath()
        guard let stroke else { return }
        context.addPath(path)
        context.setStrokeColor(Self.color(stroke))
        context.setLineWidth(1)
        context.strokePath()
    }

    /// An opaque sRGB colour from a `0xRRGGBB` literal.
    private static func color(_ hex: UInt32) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
