//
//  ArtboardLayoutTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The map the overlay draws boxes from and the script hit-tests clicks against.
///
/// `batch.pen` is what makes this testable: three top-level frames, one at the canvas
/// origin and two away from it. A walk that returns canvas coordinates rather than the
/// artboard's own is right for the first artboard and wrong for every other one, which
/// is exactly how the bug reached a person — "clicking only selects on the first
/// artboard".
struct ArtboardLayoutTests {
    /// A scratch copy of `batch.pen`, prepared.
    private func prepared() async throws -> (scratch: URL, document: PreparedDocument) {
        let scratch = try ViewerFixtures.scratch()
        let file = try ViewerFile(url: ViewerFixtures.copy("batch.pen", into: scratch))
        let prepared = try await ViewerFixtures.renders().prepared(file)
        return (scratch, prepared)
    }

    @Test("Every artboard's boxes are measured from its own corner, not the canvas's")
    func boxesAreArtboardLocal() async throws {
        let (scratch, prepared) = try await prepared()
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Canvas at (0, 0), Board at (500, 40), Component at (0, 400).
        #expect(prepared.artboards.map(\.id) == ["Cnv01", "Brd01", "Cmp01"])

        for artboard in prepared.artboards {
            let layout = try #require(ArtboardLayout.of(artboard: artboard, in: prepared, scale: 1))
            let root = try #require(layout.node(id: artboard.id))
            #expect(root.x == 0, "\(artboard.id) draws from its own left edge")
            #expect(root.y == 0, "\(artboard.id) draws from its own top edge")
            #expect(root.width == artboard.width)
            #expect(root.height == artboard.height)
        }
    }

    @Test("Nothing an artboard contains sits outside the image it is drawn over")
    func boxesLandOnTheImage() async throws {
        let (scratch, prepared) = try await prepared()
        defer { try? FileManager.default.removeItem(at: scratch) }

        for artboard in prepared.artboards {
            let layout = try #require(ArtboardLayout.of(artboard: artboard, in: prepared, scale: 1))
            for node in layout.nodes where node.clip == .none {
                #expect(
                    node.x >= 0 && node.x < artboard.width,
                    "\(artboard.id)/\(node.path) is at x \(node.x) on a \(artboard.width)pt artboard"
                )
                #expect(
                    node.y >= 0 && node.y < artboard.height,
                    "\(artboard.id)/\(node.path) is at y \(node.y) on a \(artboard.height)pt artboard"
                )
            }
        }
    }

    @Test("The selection box of a node in a displaced artboard is placed over that node")
    func selectionIsPlacedInTheDisplacedArtboard() async throws {
        let (scratch, prepared) = try await prepared()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let board = try #require(prepared.artboard(id: "Brd01"))
        let layout = try #require(ArtboardLayout.of(artboard: board, in: prepared, scale: 1))
        let chip = try #require(layout.nodes.first { $0.id != board.id })

        // The chip is placed inside the board, in the board's own points — not at the
        // board's canvas origin plus its own offset.
        #expect(chip.x < board.width)
        #expect(chip.y < board.height)
    }

    @Test("A group's children are boxed from its anchor, and not flagged as outside it")
    func groupChildrenAreBoxedFromTheAnchor() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try ViewerFile(url: ViewerFixtures.copy("render-free-groups.pen", into: scratch))
        let prepared = try await ViewerFixtures.renders().prepared(file)
        let board = try #require(prepared.artboard(id: "Gpos"))
        let layout = try #require(ArtboardLayout.of(artboard: board, in: prepared, scale: 1))

        // The group's anchor is (50, 50); its children sit at (20, 30) and (80, 60) from it,
        // and the group's own box is their union.
        let group = try #require(layout.node(id: "GposG"))
        #expect([group.x, group.y, group.width, group.height] == [70, 80, 90, 60])
        let child = try #require(layout.node(id: "GposB"))
        #expect([child.x, child.y, child.width, child.height] == [130, 110, 30, 30])
        #expect(child.clip == .none)
    }
}
