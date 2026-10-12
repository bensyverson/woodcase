//
//  PenRendererPostItOptionsTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// The CG renderer draws a note in the caller's words and the caller's identity colors
/// (``PenPostIt/DrawingOptions``), on every overload and for notes nested in frames.
struct PenRendererPostItOptionsTests {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    private static let scale: CGFloat = 2
    private static let chosen = PenHexColor(red: 0x12, green: 0x34, blue: 0xEF)
    private static let longRun = "Run it all now"

    init() {
        TestFontRegistration.registerTestFonts()
    }

    private func load() throws -> (document: PenDocument, rects: [String: PenRect]) {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("postits.pen"))
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
        return (document, PenLayoutEngine.layout(document))
    }

    private func node(_ id: String, in document: PenDocument) throws -> PenNode {
        guard case let .frame(frame) = document.children.first?.kind,
              let node = frame.children?.first(where: { $0.id == id })
        else { throw CocoaError(.coderInvalidValue) }
        return node
    }

    private func options() -> PenPostIt.DrawingOptions {
        PenPostIt.DrawingOptions(
            labels: { $0 == .run ? Self.longRun : $0.english },
            identityColor: { $0 == "ben" ? Self.chosen : nil }
        )
    }

    private func render(_ options: PenPostIt.DrawingOptions?) throws -> PixelGrid {
        let (document, rects) = try load()
        let root = try #require(rects["PiRt0"])
        let size = CGSize(width: root.width, height: root.height)
        let image: CGImage? = if let options {
            PenRenderer.render(
                document, layoutRects: rects, size: size, scale: Self.scale, rootNodeID: "PiRt0", postIt: options
            )
        } else {
            PenRenderer.render(document, layoutRects: rects, size: size, scale: Self.scale, rootNodeID: "PiRt0")
        }
        let rendered = try #require(image)
        return try #require(PixelGrid(rendered))
    }

    private func pixel(_ grid: PixelGrid, _ x: Double, _ y: Double) -> PixelGrid.RGBA {
        grid.pixel(Int(x * Double(Self.scale)), Int(y * Double(Self.scale)))
    }

    private func near(_ lhs: PixelGrid.RGBA, _ rhs: PenHexColor, tolerance: Int = 6) -> Bool {
        abs(lhs.r - Int(rhs.red)) <= tolerance && abs(lhs.g - Int(rhs.green)) <= tolerance
            && abs(lhs.b - Int(rhs.blue)) <= tolerance
    }

    @Test("The caller's identity color paints the author's dot")
    func identityDot() throws {
        let (document, rects) = try load()
        let note = try node("PiN03", in: document)
        let rect = try #require(rects["PiN03"])
        let dot = try #require(
            PenPostIt.expansion(of: note, width: rect.width, height: rect.height)?.part(.identityDot)
        )
        let grid = try render(options())
        #expect(near(pixel(grid, rect.x + dot.frame.midX, rect.y + dot.frame.midY), Self.chosen))
        let hashed = try render(nil)
        let center = pixel(hashed, rect.x + dot.frame.midX, rect.y + dot.frame.midY)
        #expect(near(center, ActorColor(name: "ben").color), "the default is the hashed color: \(center)")
    }

    @Test("The caller's Run label changes the measured button, and the button is drawn at that size")
    func runLabel() throws {
        let (document, rects) = try load()
        let prompt = try node("PiP01", in: document)
        let rect = try #require(rects["PiP01"])
        let english = try #require(
            PenPostIt.expansion(of: prompt, width: rect.width, height: rect.height)?.part(.runButton)
        )
        let long = try #require(
            PenPostIt.expansion(
                of: prompt, width: rect.width, height: rect.height, labels: options().labels
            )?.part(.runButton)
        )
        #expect(long.frame.x < english.frame.x - 10)
        let style = PenPostIt.Style.standard
        let probe = (x: rect.x + long.frame.x + 3, y: rect.y + long.frame.midY)
        #expect(try near(pixel(render(options()), probe.x, probe.y), style.runButtonFill, tolerance: 3))
        #expect(try !near(pixel(render(nil), probe.x, probe.y), style.runButtonFill, tolerance: 3))
    }

    @Test("The into-context overload takes the options, for notes nested in the document")
    func intoContext() throws {
        let (document, rects) = try load()
        let root = try #require(rects["PiRt0"])
        let width = Int(root.width * Double(Self.scale))
        let height = Int(root.height * Double(Self.scale))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.scaleBy(x: Self.scale, y: Self.scale)
        context.translateBy(x: 0, y: root.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -root.x, y: -root.y)
        PenRenderer.render(document, layoutRects: rects, into: context, postIt: options())
        let rendered = try #require(context.makeImage())
        let grid = try #require(PixelGrid(rendered))
        let note = try node("PiN03", in: document)
        let rect = try #require(rects["PiN03"])
        let dot = try #require(
            PenPostIt.expansion(of: note, width: rect.width, height: rect.height)?.part(.identityDot)
        )
        #expect(near(pixel(grid, rect.x + dot.frame.midX, rect.y + dot.frame.midY), Self.chosen))
    }
}
