//
//  ConnectionContractTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What Penumbra's contract leaf for connectors relies on, against
/// `Fixtures/connectors-routes.pen`: a connection with arrowheads and elbow routing
/// round-trips and yields its route points; the connections attached to a moved node are
/// listed; a connection hit-tests on its route, not its layout rect.
struct ConnectionContractTests {
    private static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/connectors-routes.pen")

    private struct Laid {
        let document: PenDocument
        let layoutRects: [String: PenRect]
        let canvasRects: [String: PenRect]

        func node(_ id: String) throws -> PenNode {
            try #require(document.children.first { $0.id == id })
        }
    }

    private func laid(_ document: PenDocument) -> Laid {
        let resolved = PenVariableResolver.resolve(PenRefExpander.expand(document))
        let layoutRects = PenLayoutEngine.layout(resolved)
        return Laid(
            document: resolved, layoutRects: layoutRects,
            canvasRects: PenLayoutEngine.canvasRects(in: resolved, layoutRects: layoutRects)
        )
    }

    @Test("A connection with arrowheads and elbow routing round-trips and yields its route points")
    func roundTripAndRoute() throws {
        let original = try PenParser.parse(contentsOf: Self.url)
        let reread = try PenParser.parse(PenParser.encode(original))
        let laid = laid(reread)
        let step = try laid.node("Step")
        #expect(step.connectionStyle == PenNode.ConnectionData.Style(
            routing: .elbow, startArrowhead: .none, endArrowhead: .triangle
        ))
        let route = try #require(step.connectionRoute(in: laid.canvasRects))
        #expect(route.points == [PenPoint(x: 100, y: 100), PenPoint(x: 100, y: 210), PenPoint(x: 260, y: 210)])
        let around = try laid.node("Around")
        #expect(around.connectionStyle?.startArrowhead == .circle)
        #expect(around.connectionStyle?.endArrowhead == .chevron)
    }

    @Test("The connections attached to a moved node, or to a node inside it, are listed")
    func movedNode() throws {
        let index = try PenConnectionIndex(PenParser.parse(contentsOf: Self.url))
        #expect(index.connections(affectedBy: ["Start"]) == ["Plain", "Step"])
        #expect(index.connections(affectedBy: ["Card"]) == ["Nested"])
        #expect(index.connections(affectedBy: ["Board"]) == ["Plain", "Step", "Around", "Nested"])
    }

    @Test("A connection hit-tests on its route, not its layout rect")
    func hitTest() throws {
        let laid = try laid(PenParser.parse(contentsOf: Self.url))
        let step = try laid.node("Step")
        let hit = { (x: Double, y: Double) in
            PenLayoutEngine.connectionBandContains(PenPoint(x: x, y: y), of: step, canvasRects: laid.canvasRects)
        }
        #expect(hit(100, 150), "on the route's first run")
        #expect(hit(200, 210), "on its second run")
        #expect(!hit(180, 150), "inside the route's box, off the route")
        let layoutRect = laid.layoutRects["Step"] ?? PenRect(x: 0, y: 0, width: 0, height: 0)
        #expect(!hit(layoutRect.x, layoutRect.y), "at the layout rect, which is not where it draws")
    }

    @Test("A connection's painted extent covers its route, stroke and arrowheads")
    func paintedExtent() throws {
        let laid = try laid(PenParser.parse(contentsOf: Self.url))
        let extent = try #require(PenLayoutEngine.connectionPaintedExtent(
            of: laid.node("Step"), canvasRects: laid.canvasRects
        ))
        // The vertical run's band starts 1 pt left of x 100; the triangle (14 long, 7 either
        // side for a 2-pt stroke) ends at the target's side, x 260, spanning y 203…217.
        #expect(extent == PenRect(x: 99, y: 100, width: 161, height: 117))
    }
}
