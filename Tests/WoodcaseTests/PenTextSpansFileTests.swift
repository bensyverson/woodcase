//
//  PenTextSpansFileTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A .pen file's `metadata.woodcase.spans` through the whole pipeline — parse, ref
/// expansion, variable resolution, layout and the CG renderer — on `text-spans.pen`:
/// `Styled`'s runs draw, `Stale`'s are ignored.
struct PenTextSpansFileTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Fixtures/text-spans.pen")

    /// The settled document, with `strip`'s metadata removed first.
    private static func document(stripping strip: String? = nil) throws -> PenDocument {
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        if let strip { json = removingMetadata(of: strip, from: json) }
        let parsed = try PenParser.parse(JSONSerialization.data(withJSONObject: json))
        return PenVariableResolver.resolve(PenRefExpander.expand(parsed))
    }

    /// A JSON node tree with one node's `metadata` taken out.
    private static func removingMetadata(of id: String, from node: [String: Any]) -> [String: Any] {
        var node = node
        if node["id"] as? String == id { node["metadata"] = nil }
        if let children = node["children"] as? [[String: Any]] {
            node["children"] = children.map { removingMetadata(of: id, from: $0) }
        }
        return node
    }

    /// Every node of a settled document, by id.
    private static func nodes(of document: PenDocument) -> [String: PenNode] {
        var found: [String: PenNode] = [:]
        var stack = document.children
        while let node = stack.popLast() {
            found[node.id] = node
            if case let .frame(data) = node.kind { stack += data.children ?? [] }
        }
        return found
    }

    /// The pixels of one node's rect in a render of the whole board.
    private static func pixels(of id: String, in document: PenDocument) throws -> [PenFillDomainTests.RGBA.Pixel] {
        let rects = PenLayoutEngine.layout(document)
        let canvas = PenLayoutEngine.canvasRects(in: document, layoutRects: rects)
        let rect = try #require(canvas[id])
        let image = try #require(PenRenderer.render(document, layoutRects: rects, size: CGSize(width: 400, height: 300)))
        let rgba = try #require(PenFillDomainTests.RGBA(image))
        return (Int(rect.y) ..< Int(rect.y + rect.height)).flatMap { y in
            (Int(rect.x) ..< Int(rect.x + rect.width)).map { rgba.pixel($0, y) }
        }
    }

    @Test("The file's spans reach the settled nodes: Styled applies its runs, Stale none")
    func settledNodesApplyTheirRuns() throws {
        let nodes = try Self.nodes(of: Self.document())
        #expect(nodes["Sty01"]?.appliedRuns.count == 2)
        #expect(nodes["Stl01"]?.textSpans?.runs.count == 1)
        #expect(nodes["Stl01"]?.appliedRuns.isEmpty == true)
    }

    @Test("Styled draws differently from the same text without its spans; Stale draws the same")
    func spansDrawOnlyWhenTheyApply() throws {
        let styled = try Self.pixels(of: "Sty01", in: Self.document())
        let styledPlain = try Self.pixels(of: "Sty01", in: Self.document(stripping: "Sty01"))
        #expect(styled != styledPlain)
        #expect(styled.contains { $0.r > 200 && $0.g < 120 && $0.b < 120 }, "the red run is missing")

        let stale = try Self.pixels(of: "Stl01", in: Self.document())
        let stalePlain = try Self.pixels(of: "Stl01", in: Self.document(stripping: "Stl01"))
        #expect(stale == stalePlain)
    }
}
