//
//  ShaderFillsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The one warning a render prints for a document's shader fills.
///
/// Pen runs a shader fill; Woodcase draws nothing for one (`render-shader-fills.pen`,
/// finding F1 of `project/2026-09-27-fidelity-gaps.md`). A render or a shot says so once,
/// naming the nodes, rather than handing back a picture that looks authoritative.
struct ShaderFillsTests {
    /// The top-level nodes of a document holding `children` in one frame.
    private func roots(_ children: [String]) throws -> [PenNode] {
        try PenParser.parse("""
        {"version": "2.17", "children": [
          {"type": "frame", "id": "Brd01", "name": "Board", "width": 400, "height": 200, "layout": "none",
           "children": [\(children.joined(separator: ", "))]}
        ]}
        """).children
    }

    private func rectangle(_ id: String, fill: String) -> String {
        ##"{"type": "rectangle", "id": "\##(id)", "name": "Swatch \##(id)", "width": 10, "height": 10, "fill": \##(fill)}"##
    }

    private static let shader = ##"{"type": "shader", "url": "./uv.frag"}"##

    @Test("No shader, no warning")
    func noShader() throws {
        #expect(try ShaderFills.diagnostic(under: roots([rectangle("R1", fill: "\"#FF0000\"")])) == nil)
    }

    @Test("A disabled shader draws nothing in Pen either, so it is no warning")
    func disabledShader() throws {
        let disabled = ##"{"type": "shader", "url": "./uv.frag", "enabled": false}"##
        #expect(try ShaderFills.diagnostic(under: roots([rectangle("R1", fill: disabled)])) == nil)
    }

    @Test("Every shader node is named in one rendering warning")
    func oneWarning() throws {
        let stroked = ##"{"type": "path", "id": "P1", "name": "Wave", "width": 10, "height": 10, "##
            + ##""geometry": "M0 0 L10 10", "stroke": \##(Self.shader), "strokeWidth": 2}"##
        let nested = ##"{"type": "frame", "id": "F1", "name": "Inner", "width": 10, "height": 10, "##
            + ##""children": [\##(rectangle("R2", fill: Self.shader))]}"##
        let diagnostic = try #require(try ShaderFills.diagnostic(under: roots([
            rectangle("R1", fill: Self.shader), stroked, nested, rectangle("R3", fill: "\"#FF0000\""),
        ])))
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.stage == .rendering)
        for named in ["Swatch R1 (R1)", "Wave (P1)", "Swatch R2 (R2)"] {
            #expect(diagnostic.message.contains(named), "\(diagnostic.message)")
        }
        #expect(!diagnostic.message.contains("R3"))
        #expect(diagnostic.message.contains("3 nodes"), "\(diagnostic.message)")
        #expect(diagnostic.message.contains("woodcase lint"), "\(diagnostic.message)")
    }

    @Test("A long list is cut short and says how many more")
    func longList() throws {
        let many = (1 ... 12).map { rectangle("R\($0)", fill: Self.shader) }
        let diagnostic = try #require(try ShaderFills.diagnostic(under: roots(many)))
        #expect(diagnostic.message.contains("12 nodes"), "\(diagnostic.message)")
        #expect(diagnostic.message.contains("(R8)"))
        #expect(!diagnostic.message.contains("(R9)"))
        #expect(diagnostic.message.contains("and 4 more"), "\(diagnostic.message)")
    }
}
