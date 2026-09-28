//
//  PenMeshPatchTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Positions and colours of one patch at known parameters, against hand-computed values.
struct PenMeshPatchTests {
    typealias Vector = PenMeshPoint.Vector
    typealias Support = MeshTestSupport

    private func close(_ a: Vector, _ b: Vector, _ tolerance: Double = 1e-12) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    private func close(_ a: PenMeshColor, _ b: PenMeshColor, _ tolerance: Double = 1e-12) -> Bool {
        abs(a.red - b.red) <= tolerance && abs(a.green - b.green) <= tolerance
            && abs(a.blue - b.blue) <= tolerance && abs(a.alpha - b.alpha) <= tolerance
    }

    @Test("Smoothstep at known parameters")
    func ease() {
        #expect(PenMeshPatch.ease(0) == 0)
        #expect(PenMeshPatch.ease(1) == 1)
        #expect(PenMeshPatch.ease(0.5) == 0.5)
        #expect(PenMeshPatch.ease(0.25) == 5.0 / 32)
        #expect(PenMeshPatch.ease(0.75) == 27.0 / 32)
    }

    @Test("The control net follows the zero-twist rule")
    func controlNet() throws {
        let patch = try Support.curved().patch(column: 0, row: 0)
        let net = patch.controlPoints
        #expect(net.count == 16)
        #expect(close(net[0], Vector(0, 0)))
        #expect(close(net[1], Vector(1.0 / 3, 0.3)))
        #expect(close(net[2], Vector(0.75, 0)))
        #expect(close(net[3], Vector(1, 0)))
        #expect(close(net[4], Vector(0.1, 0.4)))
        #expect(close(net[5], Vector(1.0 / 3 + 0.1, 0.7)))
        #expect(close(net[6], Vector(0.75, 0.25)))
        #expect(close(net[7], Vector(1, 0.25)))
        #expect(close(net[9], Vector(0.25, 0.75)))
        #expect(close(net[10], Vector(0.75, 0.75)))
        #expect(close(net[13], Vector(0.25, 1)))
        #expect(close(net[15], Vector(1, 1)))
    }

    @Test("Straight third-length handles on a square reproduce bilinear geometry exactly", arguments: [0.0, 0.1, 0.25, 0.5, 0.7, 1.0])
    func straightHandlesAreBilinear(_ u: Double) throws {
        let patch = try Support.fourColor(handles: Support.thirdHandles(columns: 2, rows: 2)).patch(column: 0, row: 0)
        for v in [0.0, 0.3, 0.5, 0.9, 1.0] {
            #expect(close(patch.position(u: u, v: v), Vector(u, v)))
        }
    }

    @Test("Default quarter-length handles parametrise the square non-uniformly")
    func defaultHandles() throws {
        let patch = try Support.fourColor().patch(column: 0, row: 0)
        // x(u) = B(u; 0, 1/4, 3/4, 1); at u = 1/4 that is 29/128.
        #expect(close(patch.position(u: 0.25, v: 0.5), Vector(29.0 / 128, 0.5)))
        #expect(close(patch.position(u: 0.5, v: 0.25), Vector(0.5, 29.0 / 128)))
    }

    @Test("Curved handles move points to the evaluated tensor Bézier surface")
    func curvedHandles() throws {
        let patch = try Support.curved().patch(column: 0, row: 0)
        #expect(close(patch.position(u: 0.5, v: 0), Vector(17.0 / 32, 9.0 / 80)))
        #expect(close(patch.position(u: 0.5, v: 0.5), Vector(171.0 / 320, 187.0 / 320)))
        #expect(close(patch.position(u: 0.25, v: 0.75), Vector(9991.0 / 40960, 33219.0 / 40960)))
    }

    @Test("Colour is the bilinear blend of the corners at smoothstep-eased parameters")
    func colorEasing() throws {
        let patch = try Support.fourColor().patch(column: 0, row: 0)
        #expect(close(patch.color(u: 0, v: 0), Support.red))
        #expect(close(patch.color(u: 1, v: 1), Support.yellow))
        #expect(close(patch.color(u: 0.5, v: 0.5), PenMeshColor(red: 0.5, green: 0.5, blue: 0.25)))
        let s = 5.0 / 32
        let t = 27.0 / 32
        let expected = Support.bilinear(Support.red, Support.green, Support.blue, Support.yellow, s: s, t: t)
        #expect(close(patch.color(u: 0.25, v: 0.75), expected))
    }

    @Test("Colour follows the parameters, not the position, so curved handles do not change it")
    func colorIgnoresGeometry() throws {
        let straight = try Support.fourColor().patch(column: 0, row: 0)
        let curved = try Support.curved().patch(column: 0, row: 0)
        #expect(close(straight.color(u: 0.3, v: 0.6), curved.color(u: 0.3, v: 0.6)))
    }

    @Test("Alpha blends unpremultiplied, like the other channels")
    func alpha() throws {
        let clear = PenMeshColor(red: 1, green: 0, blue: 0, alpha: 0)
        let grid = try Support.regularGrid(columns: 2, rows: 2, colors: [clear, Support.green, Support.green, Support.green])
        let color = grid.patch(column: 0, row: 0).color(u: 0.5, v: 0.5)
        #expect(close(color, PenMeshColor(red: 0.25, green: 0.75, blue: 0, alpha: 0.75)))
    }
}
