//
//  PenPostItRenderTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// The CG renderer draws notes, prompts and contexts from their expansion
/// (``PenPostIt/expansion(of:width:height:style:measure:)``) in the rev 2 look, and leaves
/// comments to Penumbra.
///
/// There is no Pen reference: Pen draws notes its own way and cannot draw rich text
/// (Penumbra's notes design, decision 11). `postits.png` is Woodcase's own render, blessed
/// with `UPDATE_GOLDEN=1` and read by eye; the probes say what it must show whatever the
/// reference.
struct PenPostItRenderTests {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    private static let scale: CGFloat = 2
    private static let board = PixelGrid.RGBA(r: 0xF2, g: 0xF1, b: 0xEE, a: 255)

    init() {
        TestFontRegistration.registerTestFonts()
    }

    /// The fixture, resolved and laid out.
    private func load() throws -> (document: PenDocument, rects: [String: PenRect]) {
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("postits.pen"))
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
        return (document, PenLayoutEngine.layout(document))
    }

    /// Renders the fixture's board at @2x.
    private func render() throws -> CGImage {
        let (document, rects) = try load()
        let root = try #require(rects["PiRt0"])
        return try #require(PenRenderer.render(
            document, layoutRects: rects, size: CGSize(width: root.width, height: root.height),
            scale: Self.scale, rootNodeID: "PiRt0"
        ))
    }

    /// The pixel at a point of the board.
    private func pixel(_ grid: PixelGrid, _ x: Double, _ y: Double) -> PixelGrid.RGBA {
        grid.pixel(Int(x * Double(Self.scale)), Int(y * Double(Self.scale)))
    }

    /// The darkest red channel in a region of the board, in points.
    private func darkest(_ grid: PixelGrid, xs: ClosedRange<Double>, ys: ClosedRange<Double>) -> Int {
        var darkest = 255
        for y in stride(from: ys.lowerBound, through: ys.upperBound, by: 0.5) {
            for x in stride(from: xs.lowerBound, through: xs.upperBound, by: 0.5) {
                darkest = min(darkest, pixel(grid, x, y).r)
            }
        }
        return darkest
    }

    /// Whether two colors agree within a tolerance per channel.
    private func near(_ lhs: PixelGrid.RGBA, _ rhs: PenHexColor, tolerance: Int = 2) -> Bool {
        abs(lhs.r - Int(rhs.red)) <= tolerance && abs(lhs.g - Int(rhs.green)) <= tolerance
            && abs(lhs.b - Int(rhs.blue)) <= tolerance
    }

    // MARK: - The reference

    @Test("The post-its render matches Woodcase's committed reference")
    func matchesReference() throws {
        let rendered = try render()
        let url = Self.fixtures.appendingPathComponent("postits.png")
        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
            try PNGEncoder.write(rendered, to: url)
        }
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "postits", fixturesDir: Self.fixtures),
            "no reference at \(url.path); bless one with UPDATE_GOLDEN=1 and read it"
        )
        #expect(reference.width == rendered.width)
        #expect(reference.height == rendered.height)
        #expect(PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference) < 0.5)
    }

    // MARK: - What it must show

    @Test("A note's paper is its tint, and an empty Pen-saved note draws at 200×200 in Post-it yellow")
    func paper() throws {
        let grid = try #require(PixelGrid(render()))
        // PiN05: 40,400, laid out 200×200, no content and no author.
        #expect(near(pixel(grid, 140, 500), PenPostIt.Tint.yellow.color))
        #expect(near(pixel(grid, 238, 500), PenPostIt.Tint.yellow.color))
        #expect(pixel(grid, 242, 500) != pixel(grid, 140, 500), "the paper runs past its 200 points")
    }

    @Test("A note casts a soft shadow below it; a context casts none")
    func shadows() throws {
        let grid = try #require(PixelGrid(render()))
        let belowNote = pixel(grid, 140, 602)
        #expect(belowNote.r < Self.board.r - 2, "no shadow below the empty note: \(belowNote)")
        // PiX01: 1280,40 240×160 — 2 points below its bottom.
        #expect(pixel(grid, 1400, 202) == Self.board)
    }

    @Test("The author's identity dot is drawn in the fallback identity color")
    func identityDot() throws {
        let (document, rects) = try load()
        let grid = try #require(PixelGrid(render()))
        guard case let .frame(frame) = document.children.first?.kind,
              let note = frame.children?.first(where: { $0.id == "PiN03" }),
              let rect = rects["PiN03"],
              let expansion = PenPostIt.expansion(of: note, width: rect.width, height: rect.height),
              let dot = expansion.part(.identityDot)
        else { throw CocoaError(.coderInvalidValue) }
        let center = pixel(grid, rect.x + dot.frame.midX, rect.y + dot.frame.midY)
        #expect(near(center, PenPostIt.identityColor(for: "ben"), tolerance: 6), "\(center)")
    }

    @Test("A long note draws all its text in its grown height, with no clip or fade")
    func longNoteDrawsAll() throws {
        let (_, rects) = try load()
        let grid = try #require(PixelGrid(render()))
        let rect = try #require(rects["PiN04"])
        #expect(rect.height > 200)
        // Below the set height there is still text, and the footer sits at the grown bottom.
        #expect(darkest(grid, xs: rect.x + 14 ... rect.x + 120, ys: rect.y + 205 ... rect.y + rect.height - 40) < 120)
        #expect(darkest(grid, xs: rect.x + 30 ... rect.x + 80, ys: rect.y + rect.height - 26 ... rect.y + rect.height - 16) < 160)
        let paper = try #require(PenHexColor("#C5E1A5"))
        #expect(near(pixel(grid, rect.x + rect.width - 4, rect.y + rect.height - 4), paper, tolerance: 3))
    }

    @Test("A prompt draws its dark Run button, and a context its quiet paper")
    func cards() throws {
        let grid = try #require(PixelGrid(render()))
        let style = PenPostIt.Style.standard
        let (document, rects) = try load()
        guard case let .frame(frame) = document.children.first?.kind,
              let prompt = frame.children?.first(where: { $0.id == "PiP01" }),
              let rect = rects["PiP01"],
              let button = PenPostIt.expansion(of: prompt, width: rect.width, height: rect.height)?.part(.runButton)
        else { throw CocoaError(.coderInvalidValue) }
        #expect(near(pixel(grid, rect.x + button.frame.x + 3, rect.y + button.frame.midY), style.runButtonFill))
        #expect(near(pixel(grid, 1300, 190), style.contextPaper))
        #expect(near(pixel(grid, 1236, 120), style.promptPaper))
    }

    @Test("A comment is not drawn: the board shows through")
    func commentNotDrawn() throws {
        let grid = try #require(PixelGrid(render()))
        // PiC01 at 1280,400 would be a 200×200 note.
        #expect(darkest(grid, xs: 1282 ... 1478, ys: 402 ... 598) == Self.board.r)
    }

    @Test("A note's painted extent reaches its shadow")
    func paintedExtent() throws {
        let (document, rects) = try load()
        guard case let .frame(frame) = document.children.first?.kind,
              let note = frame.children?.first(where: { $0.id == "PiN01" }),
              let rect = rects["PiN01"]
        else { throw CocoaError(.coderInvalidValue) }
        let extent = PenLayoutEngine.paintedExtent(of: note, rect: rect, layoutRects: rects)
        #expect(extent.y + extent.height > rect.y + rect.height + 10)
        #expect(extent.x < rect.x)
    }
}
