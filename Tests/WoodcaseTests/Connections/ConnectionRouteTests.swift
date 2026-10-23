//
//  ConnectionRouteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// A connection's route: the points its stroke runs through, from its source's anchor to
/// its target's, given every node's box on the canvas. Straight is the two anchors; elbow
/// is an orthogonal route that leaves and enters perpendicular to the anchors' sides
/// (Penumbra ruling R11, spec §11.1).
struct ConnectionRouteTests {
    private typealias Anchor = PenNode.ConnectionData.Anchor

    /// A box of 40×20 at (0,0) and another at `target`.
    private func rects(target: PenRect) -> [String: PenRect] {
        ["A": PenRect(x: 0, y: 0, width: 40, height: 20), "B": target]
    }

    private func route(
        _ source: Anchor, _ target: Anchor, routing: PenNode.ConnectionData.Routing = .elbow,
        in rects: [String: PenRect]
    ) throws -> [PenPoint] {
        let data = PenNode.ConnectionData(
            source: .init(path: "A", anchor: source), target: .init(path: "B", anchor: target)
        )
        return try #require(data.route(in: rects, routing: routing)).points
    }

    private func points(_ pairs: [(Double, Double)]) -> [PenPoint] {
        pairs.map { PenPoint(x: $0.0, y: $0.1) }
    }

    private let below = PenRect(x: 100, y: 60, width: 40, height: 20)

    @Test("A straight route is the two anchors")
    func straight() throws {
        #expect(try route(.right, .left, routing: .straight, in: rects(target: below)) == points([(40, 10), (100, 70)]))
    }

    @Test("Facing sides that do not line up meet in the middle: one step")
    func facingStep() throws {
        #expect(try route(.right, .left, in: rects(target: below))
            == points([(40, 10), (70, 10), (70, 70), (100, 70)]))
    }

    @Test("Facing sides that line up are one straight run")
    func facingAligned() throws {
        let target = PenRect(x: 100, y: 0, width: 40, height: 20)
        #expect(try route(.right, .left, in: rects(target: target)) == points([(40, 10), (100, 10)]))
    }

    @Test("A target behind the source is reached round the gap between the boxes")
    func behindThroughGap() throws {
        let source = PenRect(x: 100, y: 0, width: 40, height: 20)
        let target = PenRect(x: 0, y: 60, width: 40, height: 20)
        let route = try route(.right, .left, in: ["A": source, "B": target])
        #expect(route == points([(140, 10), (156, 10), (156, 40), (-16, 40), (-16, 70), (0, 70)]))
    }

    @Test("A target behind and level with the source is reached round both, below on a tie")
    func behindLevel() throws {
        let source = PenRect(x: 100, y: 0, width: 40, height: 20)
        let target = PenRect(x: 0, y: 0, width: 40, height: 20)
        let route = try route(.right, .left, in: ["A": source, "B": target])
        #expect(route == points([(140, 10), (156, 10), (156, 36), (-16, 36), (-16, 10), (0, 10)]))
        // A taller target reaching further down makes the way over the top the shorter.
        let taller = PenRect(x: 0, y: -10, width: 40, height: 60)
        let over = try self.route(.right, .left, in: ["A": source, "B": taller])
        #expect(over == points([(140, 10), (156, 10), (156, -26), (-16, -26), (-16, 20), (0, 20)]))
    }

    @Test("Two sides facing the same way are joined round the farther one")
    func sameWay() throws {
        #expect(try route(.right, .right, in: rects(target: below))
            == points([(40, 10), (156, 10), (156, 70), (140, 70)]))
    }

    @Test("Same way and level: the route steps round the target rather than through it")
    func sameWayLevel() throws {
        let target = PenRect(x: 100, y: 0, width: 40, height: 20)
        #expect(try route(.right, .right, in: rects(target: target))
            == points([(40, 10), (70, 10), (70, 36), (156, 36), (156, 10), (140, 10)]))
    }

    @Test("A side and a perpendicular side within reach are one corner")
    func corner() throws {
        #expect(try route(.right, .top, in: rects(target: below)) == points([(40, 10), (120, 10), (120, 60)]))
    }

    @Test("A perpendicular side facing away is reached from below it")
    func perpendicularAround() throws {
        #expect(try route(.right, .bottom, in: rects(target: below))
            == points([(40, 10), (70, 10), (70, 96), (120, 96), (120, 80)]))
    }

    @Test("Vertical sides route as horizontal ones do, turned")
    func vertical() throws {
        let aligned = PenRect(x: 0, y: 100, width: 40, height: 20)
        #expect(try route(.bottom, .top, in: rects(target: aligned)) == points([(20, 20), (20, 100)]))
        let offset = PenRect(x: 100, y: 100, width: 40, height: 20)
        #expect(try route(.bottom, .top, in: rects(target: offset))
            == points([(20, 20), (20, 60), (120, 60), (120, 100)]))
    }

    @Test("A center anchor leaves toward the other end, along its longer axis")
    func center() throws {
        let target = PenRect(x: 100, y: 0, width: 40, height: 20)
        #expect(try route(.center, .left, in: rects(target: target)) == points([(20, 10), (100, 10)]))
    }

    @Test("An endpoint naming no node has no route")
    func dangling() {
        let data = PenNode.ConnectionData(
            source: .init(path: "A", anchor: .right), target: .init(path: "Nope", anchor: .left)
        )
        #expect(data.route(in: rects(target: below), routing: .elbow) == nil)
    }

    /// Every pair of anchors, the target on each of eight sides of the source.
    private static let cases: [(Anchor, Anchor, PenRect)] = {
        let offsets: [(Double, Double)] = [(-200, -200), (0, -200), (200, -200), (-200, 0), (200, 0),
                                           (-200, 200), (0, 200), (200, 200)]
        return Anchor.allCases.flatMap { source in
            Anchor.allCases.flatMap { target in
                offsets.map { (source, target, PenRect(x: $0.0, y: $0.1, width: 40, height: 20)) }
            }
        }
    }()

    @Test("Every elbow route runs along the axes, starts and ends at the anchors, and has no empty run")
    func elbowInvariants() throws {
        for (source, target, box) in Self.cases {
            let rects = rects(target: box)
            let route = try route(source, target, in: rects)
            let label = "\(source) → \(target) at \(box.x),\(box.y): \(route)"
            let origin = try #require(rects["A"])
            #expect(route.first == source.point(on: origin), "\(label)")
            #expect(route.last == target.point(on: box), "\(label)")
            for (from, to) in zip(route, route.dropFirst()) {
                #expect(from.x == to.x || from.y == to.y, "diagonal run in \(label)")
                #expect(from != to, "empty run in \(label)")
            }
            if let leaving = source.outwardNormal, route.count > 1 {
                #expect(Self.direction(route[0], route[1]) == leaving, "leaves along its side in \(label)")
            }
            if let entering = target.outwardNormal, route.count > 1 {
                let last = Self.direction(route[route.count - 2], route[route.count - 1])
                #expect(last == PenPoint(x: -entering.x, y: -entering.y), "enters against its side in \(label)")
            }
        }
    }

    /// The unit axis direction from one point to another on the same axis.
    private static func direction(_ from: PenPoint, _ to: PenPoint) -> PenPoint {
        PenPoint(x: (to.x - from.x).sign == .minus ? -1 : (to.x == from.x ? 0 : 1),
                 y: (to.y - from.y).sign == .minus ? -1 : (to.y == from.y ? 0 : 1))
    }
}
