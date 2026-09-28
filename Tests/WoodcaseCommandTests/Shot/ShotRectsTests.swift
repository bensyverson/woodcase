//
//  ShotRectsTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `shot --json` reports every rect it drew, not just the root's.
///
/// A screenshot an agent cannot locate is a picture of an unknown place: the boxes
/// `--outline` draws are the landmarks, and until they came back as numbers the caller
/// had to guess where each one landed. Every rect here is in the rendered node's own
/// coordinate space — the space the printed `rect=` establishes — so the documented
/// `point = (pixel − gutter) / scale + origin` maps any of them to pixels.
@Suite("shot --json rects")
struct ShotRectsTests {
    @Test("With no --outline, --json lists exactly the rendered node's own rect")
    func rootRectIsListed() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("board.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath, "--json"
        )
        #expect(run.status == 0, "\(run.stderr)")

        let decoded = try JSONDecoder().decode(RectsShot.self, from: Data(run.stdout.utf8))
        #expect(decoded.rects.count == 1)
        let root = try #require(decoded.rects.first)
        #expect(root.role == "node")
        #expect(root.id == "Brd01")
        #expect(root.address == "Board")
        #expect(root.name == "Board")
        #expect(root.rect.x == 0)
        #expect(root.rect.y == 0)
        #expect(root.rect.width == 400)
        #expect(root.rect.height == 300)
    }

    @Test("Every --outline target comes back with its id, address and rect, in order")
    func outlineTargetsAreListed() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("boxes.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath,
            "--outline", "B", "--outline", "A", "--json"
        )
        #expect(run.status == 0, "\(run.stderr)")

        let decoded = try JSONDecoder().decode(RectsShot.self, from: Data(run.stdout.utf8))
        #expect(decoded.rects.map(\.role) == ["node", "outline", "outline"])
        #expect(decoded.rects.map(\.id) == ["Brd01", "RctB1", "RctA1"])
        // The order is the order the flags were given, not the document's order.
        #expect(decoded.rects.map(\.address) == ["Board", "B", "A"])
        #expect(decoded.rects.map(\.name) == ["Board", "B", "A"])

        let b = decoded.rects[1].rect
        #expect([b.x, b.y, b.width, b.height] == [240, 180, 120, 80])
        let a = decoded.rects[2].rect
        #expect([a.x, a.y, a.width, a.height] == [40, 40, 160, 120])
    }

    @Test("An outline rect is composed into the rendered node's frame, not its parent's")
    func outlineRectIsInTheRenderedNodesFrame() throws {
        let fixture = try CommandFixture(fixture: "layout-deep-nesting.pen")
        let outputPath = fixture.root.appendingPathComponent("deep.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "layout-deep-nesting", "--out", outputPath,
            "--outline", "deep-leaf-2", "--json"
        )
        #expect(run.status == 0, "\(run.stderr)")

        // Ms0rE(0,0) → S4auN(10,10) → o3V8H(193,8) → D48Fa(6,6) → YOoQM(34,0): composed,
        // (243, 24). The rect the engine stores for YOoQM alone reads (34, 0).
        let decoded = try JSONDecoder().decode(RectsShot.self, from: Data(run.stdout.utf8))
        let leaf = try #require(decoded.rects.last)
        #expect(leaf.role == "outline")
        #expect(leaf.rect.x == 243)
        #expect(leaf.rect.y == 24)
    }

    @Test("The scale, gutter and pixel size travel with the rects, so pixels can be computed")
    func mappingFieldsAccompanyTheRects() throws {
        let fixture = try CommandFixture(fixture: "shot-overlay.pen")
        let outputPath = fixture.root.appendingPathComponent("half.png").path
        let run = try fixture.run(
            "shot", fixture.file.path, "Board", "--out", outputPath,
            "--max", "200", "--outline", "A", "--json"
        )
        #expect(run.status == 0, "\(run.stderr)")

        let decoded = try JSONDecoder().decode(RectsShot.self, from: Data(run.stdout.utf8))
        #expect(decoded.scale == 0.5)
        #expect(decoded.gutterLeft == 0)
        #expect(decoded.gutterTop == 0)
        #expect(decoded.pixelWidth == 200)
        #expect(decoded.pixelHeight == 150)

        // pixel = (point − origin) × scale + gutter: A's top-left is (40,40) in a frame
        // whose origin is (0,0), so it inks pixel (20, 20).
        let a = try #require(decoded.rects.last).rect
        let origin = decoded.rect
        #expect((a.x - origin.x) * decoded.scale + Double(decoded.gutterLeft) == 20)
        #expect((a.y - origin.y) * decoded.scale + Double(decoded.gutterTop) == 20)
    }

    /// The `--json` payload, as far as these tests read it.
    struct RectsShot: Decodable {
        /// A rect entry: what was drawn, where, and how to name it again.
        struct Entry: Decodable {
            let role: String
            let id: String
            let address: String
            let name: String
            let rect: Rect
        }

        /// A rect, in layout points.
        struct Rect: Decodable {
            let x, y, width, height: Double
        }

        let rect: Rect
        let rects: [Entry]
        let scale: Double
        let pixelWidth: Int
        let pixelHeight: Int
        let gutterLeft: Int
        let gutterTop: Int
    }
}
