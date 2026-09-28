//
//  DocumentLinterPerSideShapeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `per-side-stroke-on-shape`: a per-side stroke width on a shape without box sides.
///
/// Pen strokes an ellipse, a polygon, a path or a line with a per-side width as one
/// uniform stroke of the top width, the other sides ignored, and with no top draws no
/// stroke at all (`render-per-side-shapes.pen`; finding F6 of
/// `project/2026-09-27-fidelity-gaps.md`). Every Woodcase target draws the same.
@MainActor
struct DocumentLinterPerSideShapeTests {
    // MARK: - Helpers

    /// A document whose one root is a frame holding `child`.
    private func board(_ child: String) throws -> EditableDocument {
        let json = """
        {"version": "2.17", "children": [
          {"type": "frame", "id": "Brd01", "name": "Board", "x": 0, "y": 0,
           "width": 400, "height": 200, "layout": "none", "children": [\(child)]}
        ]}
        """
        return try EditableDocument(from: PenParser.parse(json))
    }

    private func findings(_ document: EditableDocument) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document).filter { $0.check == .perSideStrokeOnShape }
    }

    /// A node of `type` named Ring with a red stroke of `width`.
    private func shape(_ type: String, width: String, extra: String = "") -> String {
        ##"{"type": "\##(type)", "id": "Shp01", "name": "Ring", "width": 40, "height": 40, "stroke": "#FF0000", "strokeWidth": \##(width)\##(extra)}"##
    }

    // MARK: - Findings

    @Test("Uneven sides on an ellipse, a polygon, a path or a line are a warning naming the top width",
          arguments: ["ellipse", "polygon", "path", "line"])
    func unevenSides(type: String) throws {
        let found = try findings(board(shape(type, width: ##"{"top": 12, "right": 2, "bottom": 6, "left": 0}"##)))
        #expect(found.count == 1)
        let finding = try #require(found.first)
        #expect(finding.nodeID == "Shp01")
        #expect(finding.severity == .warning)
        #expect(finding.message.contains("top width"), "\(finding.message)")
        #expect(finding.message.contains("12"), "\(finding.message)")
        #expect(finding.message.contains(type), "\(finding.message)")
    }

    @Test("A per-side width with no top says Pen draws no stroke")
    func noTop() throws {
        let found = try findings(board(shape("ellipse", width: ##"{"right": 10, "bottom": 4}"##)))
        let finding = try #require(found.first)
        #expect(finding.message.contains("no stroke"), "\(finding.message)")
    }

    @Test("Every board in render-per-side-shapes.pen is a finding; equal sides, a lone top, a uniform width, a box and no paint are clean")
    func fixture() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/render-per-side-shapes.pen")
        let document = try EditableDocument(from: PenParser.parse(Data(contentsOf: url)))
        #expect(try findings(document).count == 14)
        #expect(LintCheck.perSideStrokeOnShape.rawValue == "per-side-stroke-on-shape")
        #expect(LintCheck.perSideStrokeOnShape.summary.contains("top width"))

        let clean = try board([
            shape("ellipse", width: ##"{"top": 4, "right": 4, "bottom": 4, "left": 4}"##),
            shape("polygon", width: ##"{"top": 4}"##).replacingOccurrences(of: "Shp01", with: "Shp02"),
            shape("path", width: "3").replacingOccurrences(of: "Shp01", with: "Shp03"),
            shape("rectangle", width: ##"{"top": 12, "left": 2}"##).replacingOccurrences(of: "Shp01", with: "Shp04"),
            ##"{"type": "ellipse", "id": "Shp05", "name": "Bare", "width": 40, "height": 40, "strokeWidth": {"top": 12, "left": 2}}"##,
            shape("ellipse", width: ##"{"top": 12, "left": 2}"##).replacingOccurrences(of: "Shp01", with: "Shp06"),
        ].joined(separator: ", "))
        #expect(try findings(clean).map(\.nodeID) == ["Shp06"])
    }
}
