//
//  PenPaintedExtentsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins ``PenLayoutEngine/paintedExtents(of:rect:layoutRects:)`` and
/// ``PenLayoutEngine/paintedExtents(in:layoutRects:)`` — every node's painted extent from
/// one bottom-up walk — to ``PenLayoutEngine/paintedExtent(of:rect:layoutRects:)``, node
/// by node and exactly, across fixtures that between them hold every node kind, refs and
/// instances, notes and prompts, clips, rotations, effects, strokes, icons and disabled
/// nodes.
struct PenPaintedExtentsTests {
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Fixtures whose node mix covers what `paintedExtent` handles.
    private static let fixtures = [
        "every-node-type", "geometry-probe", "banking", "woodcase-app", "postits", "notes-comments-prompts",
        "parser-icon-font", "instances", "addressing-nested-instance", "clip", "blur2", "component-props",
    ]

    /// Registers Inter and IBM Plex Sans, which the fixtures set, before any test walks them:
    /// registration moves the font set, so one that lands between a test's two passes sets
    /// their texts in different faces (``fixtureFamiliesAreRegistered(_:)``).
    init() {
        TestFontRegistration.registerTestFonts()
    }

    /// A board of its own for the cases the fixtures miss: a turned group holding a turned,
    /// shadowed, stroked frame; a disabled child; a clipping frame whose children still
    /// get extents; an empty group; a blurred group.
    private static let handmade = """
    {"version": "2.19", "children": [
      {"type": "group", "id": "g", "x": 40, "y": 30, "rotation": 20, "children": [
        {"type": "frame", "id": "f", "x": 0, "y": 0, "width": 120, "height": 80, "rotation": -35,
         "stroke": "#000000", "strokeWidth": 6, "strokeAlignment": "outer",
         "effect": {"type": "shadow", "offset": {"x": 8, "y": 12}, "blur": 10, "spread": 4, "color": "#00000080"},
         "children": [
          {"type": "text", "id": "t1", "x": 10, "y": 10, "content": "Overflowing italic words",
           "fontFamily": "Helvetica", "fontSize": 18, "fontStyle": "italic", "width": 40,
           "textGrowth": "fixed-width"},
          {"type": "rectangle", "id": "off", "enabled": false, "x": 300, "y": 300, "width": 50, "height": 50,
           "fill": "#FF0000"},
          {"type": "frame", "id": "clipper", "x": 60, "y": 40, "width": 30, "height": 30, "clip": true,
           "children": [
            {"type": "text", "id": "t2", "x": -20, "y": -10, "content": "Clipped away", "fontFamily": "Helvetica",
             "fontSize": 14},
            {"type": "ellipse", "id": "e", "x": 10, "y": 10, "width": 90, "height": 90, "fill": "#00FF00",
             "stroke": "#000000", "strokeWidth": 4}
          ]}
        ]},
        {"type": "group", "id": "empty", "x": 5, "y": 5, "children": []},
        {"type": "group", "id": "blurred", "x": 200, "y": 0,
         "effect": {"type": "blur", "radius": 6}, "children": [
          {"type": "polygon", "id": "p", "x": 0, "y": 0, "width": 60, "height": 60, "polygonCount": 3,
           "fill": "#0000FF", "stroke": "#000000", "strokeWidth": 8, "strokeAlignment": "outer"}
        ]}
      ]}
    ]}
    """

    @Test("Every node's extent from one walk equals paintedExtent's, across the fixtures", arguments: fixtures)
    func everyFixtureMatches(_ fixture: String) throws {
        let data = try Data(contentsOf: Self.fixturesDir.appendingPathComponent("\(fixture).pen"))
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
        try Self.expectMatches(document)
    }

    /// The suite compares two passes taken one after the other, so a family registered
    /// between them sets the second pass's texts in a face the first never saw. Every
    /// family the fixtures set must already be registered when the suite starts, not
    /// whenever a parallel suite registers it (leaf dyQakq).
    @Test("Every family the fixtures' texts set is registered before the suite walks them", arguments: fixtures)
    func fixtureFamiliesAreRegistered(_ fixture: String) throws {
        let data = try Data(contentsOf: Self.fixturesDir.appendingPathComponent("\(fixture).pen"))
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
        var families: Set<String> = []
        var pending = document.children
        while let node = pending.popLast() {
            if case let .text(text) = node.kind { families.insert(PenTextStyle(text).fontFamily) }
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        families.remove(PenTextStyle.defaultFontFamily)
        for family in families {
            #expect(PenTextMeasurer.fontFamilyAvailable(family), "\(fixture) sets \(family), which is not registered")
        }
    }

    @Test("Every node's extent from one walk equals paintedExtent's on a turned, clipped, disabled board")
    func handmadeBoardMatches() throws {
        let document = try PenParser.parse(Data(Self.handmade.utf8))
        let extents = try Self.expectMatches(document)
        // The cases the board was built for are all present. The layout settles no rect for
        // a disabled node, so "off" has none; `disabledNodeWithARect` gives it one.
        #expect(extents["off"] == nil)
        for id in ["g", "f", "t1", "clipper", "t2", "e", "empty", "blurred", "p"] {
            #expect(extents[id] != nil, "\(id) has no extent")
        }
    }

    @Test("A subtree's table holds its root and every placed descendant, and nothing else")
    func subtreeTable() throws {
        let document = try PenParser.parse(Data(Self.handmade.utf8))
        let rects = PenLayoutEngine.layout(document)
        let frame = try #require(PenLayoutEngine.node(id: "f", in: document.children))
        let extents = try PenLayoutEngine.paintedExtents(of: frame, rect: #require(rects["f"]), layoutRects: rects)
        #expect(Set(extents.keys) == ["f", "t1", "clipper", "t2", "e"])
        #expect(try extents["f"] == PenLayoutEngine.paintedExtent(of: frame, rect: #require(rects["f"]), layoutRects: rects))
    }

    @Test("A node the layout placed no rect for, and its subtree, get no extent")
    func unplacedSubtree() throws {
        let document = try PenParser.parse(Data(Self.handmade.utf8))
        var rects = PenLayoutEngine.layout(document)
        rects["clipper"] = nil
        let extents = PenLayoutEngine.paintedExtents(in: document, layoutRects: rects)
        #expect(extents["clipper"] == nil)
        #expect(extents["t2"] == nil)
        #expect(extents["e"] == nil)
        #expect(extents["f"] != nil)
    }

    @Test("A disabled node given a rect gets its own extent, which does not reach its parent's")
    func disabledNodeWithARect() throws {
        let document = try PenParser.parse(Data(Self.handmade.utf8))
        let settled = PenLayoutEngine.layout(document)
        var rects = settled
        rects["off"] = PenRect(x: 300, y: 300, width: 50, height: 50)
        let extents = try Self.expectMatches(document, layoutRects: rects)
        #expect(extents["off"] == PenRect(x: 300, y: 300, width: 50, height: 50))
        let without = PenLayoutEngine.paintedExtents(in: document, layoutRects: settled)
        #expect(extents["f"] == without["f"], "the disabled child reached its parent")
    }

    // MARK: - Helpers

    /// Lays `document` out, takes its table from one walk, and expects every entry — and
    /// every node with a rect whose ancestors all have one — to equal `paintedExtent`'s.
    ///
    /// - Returns: The table.
    @discardableResult
    private static func expectMatches(
        _ document: PenDocument, layoutRects: [String: PenRect]? = nil
    ) throws -> [String: PenRect] {
        let rects = layoutRects ?? PenLayoutEngine.layout(document)
        let extents = PenLayoutEngine.paintedExtents(in: document, layoutRects: rects)
        var expected: [String: PenRect] = [:]
        var pending = document.children
        while let node = pending.popLast() {
            guard let rect = rects[node.id] else { continue }
            expected[node.id] = PenLayoutEngine.paintedExtent(of: node, rect: rect, layoutRects: rects)
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        #expect(!expected.isEmpty)
        #expect(Set(extents.keys) == Set(expected.keys))
        for (id, extent) in expected {
            #expect(extents[id] == extent, "\(id): one walk \(String(describing: extents[id])), per node \(extent)")
        }
        return extents
    }
}
