//
//  DocumentLinterShaderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `shader-not-drawn`: a shader fill, which Pen runs and Woodcase does not.
///
/// Pen runs a node's WebGL shader fill in its editor and its exporter
/// (`render-shader-fills.pen`); Woodcase draws nothing for one on any target, so a render,
/// a shot or generated code leaves the paint out
/// (`project/2026-09-27-fidelity-gaps.md`, finding F1).
@MainActor
struct DocumentLinterShaderTests {
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

    private func shaders(_ document: EditableDocument) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document).filter { $0.check == .shaderNotDrawn }
    }

    private static let shader = ##"{"type": "shader", "url": "./uv.frag"}"##

    // MARK: - The check

    @Test("The check is a warning, and its id is shader-not-drawn")
    func checkIsAWarning() {
        #expect(LintCheck.shaderNotDrawn.rawValue == "shader-not-drawn")
        #expect(LintCheck.shaderNotDrawn.severity == .warning)
        #expect(LintCheck.shaderNotDrawn.summary.contains("shader"))
    }

    // MARK: - Findings

    @Test("A shader fill is a finding naming its file and saying Woodcase does not draw it")
    func fill() throws {
        let found = try shaders(board(
            ##"{"type": "rectangle", "id": "Rct01", "name": "Swatch", "width": 40, "height": 40, "fill": \##(Self.shader)}"##
        ))
        #expect(found.count == 1)
        let finding = try #require(found.first)
        #expect(finding.nodeID == "Rct01")
        #expect(finding.message.contains("./uv.frag"), "\(finding.message)")
        #expect(finding.message.contains("Woodcase does not draw"), "\(finding.message)")
        #expect(finding.message.contains("Pen"), "\(finding.message)")
    }

    @Test("Each shader is its own finding, a stroke's too, placed in its list")
    func eachShader() throws {
        let found = try shaders(board(
            ##"{"type": "rectangle", "id": "Rct01", "name": "Swatch", "width": 40, "height": 40, "##
                + ##""fill": ["#FF0000", \##(Self.shader)], "stroke": \##(Self.shader), "strokeWidth": 2}"##
        ))
        #expect(found.count == 2)
        #expect(found.first?.message.contains("fill 2 of 2") == true, "\(found.map(\.message))")
        #expect(found.last?.message.contains("stroke") == true, "\(found.map(\.message))")
    }

    @Test("A shader on text and on an icon is a finding")
    func textAndIcon() throws {
        let found = try shaders(board(
            ##"{"type": "text", "id": "Txt01", "name": "Label", "content": "Hi", "fill": \##(Self.shader)}, "##
                + ##"{"type": "icon", "id": "Ic001", "name": "Glyph", "icon": "square", "library": "lucide", "##
                + ##""width": 24, "height": 24, "fill": \##(Self.shader)}"##
        ))
        #expect(found.map(\.nodeID) == ["Txt01", "Ic001"])
    }

    @Test("A disabled shader is clean: nothing is drawn either way")
    func disabledIsClean() throws {
        let found = try shaders(board(
            ##"{"type": "rectangle", "id": "Rct01", "name": "Swatch", "width": 40, "height": 40, "##
                + ##""fill": {"type": "shader", "url": "./uv.frag", "enabled": false}}"##
        ))
        #expect(found.isEmpty)
    }

    @Test("Every shader in render-shader-fills.pen is a finding")
    func fixture() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/render-shader-fills.pen")
        let document = try EditableDocument(from: PenParser.parse(Data(contentsOf: url)))
        #expect(try shaders(document).count == 10)
    }
}
