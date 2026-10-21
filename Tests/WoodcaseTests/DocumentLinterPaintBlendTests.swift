//
//  DocumentLinterPaintBlendTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// `paint-blend-lowest`: a node whose lowest paint has a blend mode. A paint's blend blends
/// only within its node's paint stack (Ben's reading-1 ruling, 2026-10-20), so the lowest
/// paint blends with nothing and draws as if normal — where Pen blends it with whatever lies
/// behind the node. The fix moves the blend to the node, whose blend reaches the backdrop,
/// which restores the Pen-style look.
@MainActor
struct DocumentLinterPaintBlendTests {
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    private func findings(_ document: PenDocument) throws -> [LintFinding] {
        try DocumentLinter.findings(in: EditableDocument(from: document)).filter { $0.check == .paintBlendLowest }
    }

    private func findings(node: String) throws -> [LintFinding] {
        let json = """
        {"version": "2.20", "children": [
          {"type": "frame", "id": "Brd01", "name": "Board", "x": 0, "y": 0, "width": 200, "height": 200,
           "layout": "none", "children": [\(node)]}
        ]}
        """
        return try findings(PenParser.parse(json))
    }

    @Test("A lone blended fill is a warning naming the node and its blend")
    func loneFill() throws {
        let found = try findings(PenRendererPaintIsolationTests.fixture())
        let finding = try #require(found.first)
        #expect(found.count == 1, "\(found)")
        #expect(finding.nodeID == "a")
        #expect(finding.severity == .warning)
        #expect(finding.message.contains("multiply"), "\(finding.message)")
        #expect(finding.message.contains("kind.blendMode=multiply"), "\(finding.message)")
    }

    @Test("A blend above an unblended paint, or on no paint at all, is clean")
    func cleanStacks() throws {
        #expect(try findings(node: """
        {"type": "rectangle", "id": "r", "width": 10, "height": 10,
         "fill": [{"type": "color", "color": "#FFFF00"}, {"type": "color", "color": "#0000FF", "blendMode": "multiply"}]}
        """).isEmpty)
        #expect(try findings(node: """
        {"type": "rectangle", "id": "r", "width": 10, "height": 10, "fill": "#0000FF",
         "stroke": {"type": "color", "color": "#0000FF", "blendMode": "screen"}, "strokeWidth": 2}
        """).isEmpty)
        #expect(try findings(node: """
        {"type": "rectangle", "id": "r", "width": 10, "height": 10,
         "fill": {"type": "color", "color": "#0000FF", "blendMode": "normal"}}
        """).isEmpty)
    }

    @Test("A disabled paint beneath does not count: the lowest drawn paint is")
    func disabledBeneath() throws {
        let found = try findings(node: """
        {"type": "rectangle", "id": "r", "width": 10, "height": 10,
         "fill": [{"type": "color", "color": "#FFFF00", "enabled": false},
                  {"type": "color", "color": "#0000FF", "blendMode": "screen"}]}
        """)
        #expect(found.map(\.nodeID) == ["r"])
    }

    @Test("A stroke-only node's blended stroke is flagged, and its fix writes the stroke")
    func strokeOnly() throws {
        let found = try findings(node: """
        {"type": "rectangle", "id": "r", "width": 10, "height": 10,
         "stroke": {"type": "color", "color": "#0000FF", "blendMode": "screen"}, "strokeWidth": 2}
        """)
        let finding = try #require(found.first)
        #expect(finding.message.contains("kind.stroke="), "\(finding.message)")
        #expect(finding.message.contains("kind.blendMode=screen"), "\(finding.message)")
    }

    @Test("A node with a blend of its own is told its paint's blend does nothing, with no move")
    func nodeAlreadyBlended() throws {
        let found = try findings(node: """
        {"type": "rectangle", "id": "r", "width": 10, "height": 10,
         "fill": {"type": "color", "color": "#0000FF", "blendMode": "screen"},
         "metadata": {"type": "woodcase", "woodcase": {"blendMode": "multiply"}}}
        """)
        let finding = try #require(found.first)
        #expect(!finding.message.contains("kind.blendMode="), "\(finding.message)")
    }

    @Test("The fix moves the blend to the node, and the node then draws as Pen draws it")
    func fixRestoresPenLook() throws {
        let document = try EditableDocument(from: PenRendererPaintIsolationTests.fixture())
        let node = try #require(document.node(id: "a"))
        let fix = try #require(DocumentLinter.paintBlendFix(for: node))
        #expect(fix["kind.blendMode"] == .string("multiply"))
        let plan = try EditPlanner.plan(.set(fix), routedAt: .node(id: "a"), in: document)
        for operation in plan.operations {
            try document.apply(operation)
        }
        #expect(try findings(document.materialize()).isEmpty)

        // Pen's preview is drawn at half scale: rectangle `a`'s center, 70, 60, is 35, 30.
        let preview = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "paint-blend-pen-preview", fixturesDir: Self.fixturesDir
        ))
        let pen = try #require(PixelGrid(preview)).pixel(35, 30)
        let fixed = try PenRendererPaintIsolationTests.render(document.materialize()).pixel(70, 60)
        #expect(abs(pen.r - fixed.r) <= 2 && abs(pen.g - fixed.g) <= 2 && abs(pen.b - fixed.b) <= 2,
                "Pen \(pen), fixed \(fixed)")
        #expect(fixed.r < 3 && fixed.g < 3 && fixed.b < 3, "\(fixed)")
    }
}
