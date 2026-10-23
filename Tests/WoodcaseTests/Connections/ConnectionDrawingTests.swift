//
//  ConnectionDrawingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// What a connection paints, as geometry every renderer draws alike: the line it strokes
/// (its route, cut back where an arrowhead covers its end) and each arrowhead's shape —
/// and from them its painted extent and its hit test, on the route rather than on the
/// layout rect, which means nothing for a connection.
struct ConnectionDrawingTests {
    private typealias Data = PenNode.ConnectionData
    private typealias Shape = PenNode.ConnectionData.Arrowhead.Shape

    /// A at (0,0) 40×20, B at (100,0) 40×20: a level run from (40,10) to (100,10).
    private let level: [String: PenRect] = [
        "A": PenRect(x: 0, y: 0, width: 40, height: 20),
        "B": PenRect(x: 100, y: 0, width: 40, height: 20),
    ]

    /// B at (100,60): an elbow from (40,10) through (70,10) and (70,70) to (100,70).
    private let stepped: [String: PenRect] = [
        "A": PenRect(x: 0, y: 0, width: 40, height: 20),
        "B": PenRect(x: 100, y: 60, width: 40, height: 20),
    ]

    private func data(width: Double = 2, cap: PenStrokeCap? = nil, join: PenStrokeJoin? = nil) -> Data {
        Data(
            source: .init(path: "A", anchor: .right), target: .init(path: "B", anchor: .left),
            stroke: .single(.shorthand("#FF0000")), strokeWidth: .uniform(.literal(width)),
            strokeLinecap: cap, strokeLinejoin: join
        )
    }

    private func drawing(_ style: Data.Style, in rects: [String: PenRect], width: Double = 2) throws -> Data.Drawing {
        try #require(data(width: width).drawing(in: rects, style: style))
    }

    private func close(_ one: PenPoint, _ other: PenPoint) -> Bool {
        abs(one.x - other.x) < 1e-9 && abs(one.y - other.y) < 1e-9
    }

    @Test("With no arrowheads the line is the whole route")
    func bare() throws {
        let drawing = try drawing(.plain, in: level)
        #expect(drawing.line == [PenPoint(x: 40, y: 10), PenPoint(x: 100, y: 10)])
        #expect(drawing.route.points == drawing.line)
        #expect(drawing.start == nil && drawing.end == nil)
        #expect(drawing.strokeWidth == 2)
    }

    @Test("A triangle's tip is on the anchor, and the line stops at its base")
    func triangle() throws {
        let drawing = try drawing(Data.Style(routing: .straight, startArrowhead: .none, endArrowhead: .triangle), in: level)
        // 2-pt stroke: 3 × 2 + 8 = 14 long, 7 either side of the line.
        #expect(drawing.end == .filled([PenPoint(x: 100, y: 10), PenPoint(x: 86, y: 17), PenPoint(x: 86, y: 3)]))
        #expect(drawing.line == [PenPoint(x: 40, y: 10), PenPoint(x: 86, y: 10)])
    }

    @Test("A circle touches the anchor, and the line stops at its center")
    func circle() throws {
        let drawing = try drawing(Data.Style(routing: .straight, startArrowhead: .circle, endArrowhead: .none), in: level)
        // 2-pt stroke: radius 1.5 × 2 + 3 = 6, pointing back at the source.
        #expect(drawing.start == .disc(center: PenPoint(x: 46, y: 10), radius: 6))
        #expect(drawing.line == [PenPoint(x: 46, y: 10), PenPoint(x: 100, y: 10)])
    }

    @Test("A chevron is stroked, set back so its mitered tip lands on the anchor")
    func chevron() throws {
        let drawing = try drawing(Data.Style(routing: .straight, startArrowhead: .none, endArrowhead: .chevron), in: level)
        let inset = 5.0.squareRoot() // half the 2-pt width over sin(atan(7 / 14))
        guard case let .stroked(arms) = drawing.end else {
            Issue.record("expected a stroked chevron, got \(String(describing: drawing.end))")
            return
        }
        let tip = 100 - inset
        #expect(arms.count == 3)
        #expect(close(arms[0], PenPoint(x: tip - 14, y: 17)))
        #expect(close(arms[1], PenPoint(x: tip, y: 10)))
        #expect(close(arms[2], PenPoint(x: tip - 14, y: 3)))
        #expect(close(drawing.line[1], PenPoint(x: tip, y: 10)))
    }

    @Test("An elbow's arrowhead follows its last run, into the target's side")
    func elbowHead() throws {
        let drawing = try drawing(Data.Style(routing: .elbow, startArrowhead: .none, endArrowhead: .triangle), in: stepped)
        #expect(drawing.route.points.count == 4)
        #expect(drawing.end == .filled([PenPoint(x: 100, y: 70), PenPoint(x: 86, y: 77), PenPoint(x: 86, y: 63)]))
        #expect(drawing.line.last == PenPoint(x: 86, y: 70))
    }

    @Test("An elbow's run out from a box is long enough to hold its arrowhead")
    func elbowRunHoldsArrowhead() throws {
        // B behind A: with no arrowhead the route turns 16 pt out from each box; a 6-pt
        // chevron is 26 long, so the route turns 26 + 8 out instead.
        let behind: [String: PenRect] = [
            "A": PenRect(x: 200, y: 0, width: 40, height: 20),
            "B": PenRect(x: 0, y: 100, width: 40, height: 20),
        ]
        let bare = Data.Style(routing: .elbow, startArrowhead: .none, endArrowhead: .none)
        let headed = Data.Style(routing: .elbow, startArrowhead: .none, endArrowhead: .chevron)
        let lastRun = { (drawing: Data.Drawing) in
            let points = drawing.route.points
            return points[points.count - 1].x - points[points.count - 2].x
        }
        #expect(try lastRun(drawing(bare, in: behind, width: 6)) == 16)
        #expect(try lastRun(drawing(headed, in: behind, width: 6)) == 34)
        #expect(headed.elbowMargin(strokeWidth: 6) == 34)
    }

    @Test("Arrowheads grow with the stroke width")
    func scalesWithWidth() throws {
        let drawing = try drawing(
            Data.Style(routing: .straight, startArrowhead: .none, endArrowhead: .triangle), in: level, width: 4
        )
        // 3 × 4 + 8 = 20 long, 10 either side.
        #expect(drawing.end == .filled([PenPoint(x: 100, y: 10), PenPoint(x: 80, y: 20), PenPoint(x: 80, y: 0)]))
    }

    @Test("The painted extent covers the stroke band and the arrowheads")
    func paintedExtent() throws {
        let bare = try drawing(.plain, in: level)
        #expect(bare.paintedExtent == PenRect(x: 40, y: 9, width: 60, height: 2))
        let headed = try drawing(Data.Style(routing: .straight, startArrowhead: .none, endArrowhead: .triangle), in: level)
        #expect(headed.paintedExtent == PenRect(x: 40, y: 3, width: 60, height: 14))
    }

    @Test("The hit test is the stroke band along the route, not its bounding box")
    func hitTest() throws {
        let drawing = try drawing(Data.Style(routing: .elbow, startArrowhead: .none, endArrowhead: .none), in: stepped)
        #expect(drawing.contains(PenPoint(x: 70, y: 40)), "on the middle run")
        #expect(drawing.contains(PenPoint(x: 55, y: 10.5)), "on the first run")
        #expect(!drawing.contains(PenPoint(x: 55, y: 55)), "inside the route's box, off the route")
        #expect(!drawing.contains(PenPoint(x: 73, y: 40)), "3 pt off a 2-pt line")
        #expect(drawing.contains(PenPoint(x: 73, y: 40), tolerance: 3), "within a 3-pt tolerance")
    }

    @Test("The hit test takes in the arrowheads")
    func hitTestHead() throws {
        let drawing = try drawing(Data.Style(routing: .straight, startArrowhead: .none, endArrowhead: .triangle), in: level)
        #expect(drawing.contains(PenPoint(x: 92, y: 13)))
        #expect(!drawing.contains(PenPoint(x: 80, y: 13)))
    }
}
