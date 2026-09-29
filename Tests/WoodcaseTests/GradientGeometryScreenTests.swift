//
//  GradientGeometryScreenTests.swift
//  WoodcaseTests
//

#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import Testing
@testable import Woodcase

/// Pins what an emitter reads off Pen's gradient map to state it in a target's own terms:
/// a linear gradient's stop position over the box, an angular gradient's bearing on a
/// stretched box, and whether a radial gradient's ellipse keeps to the box's axes.
struct GradientGeometryScreenTests {
    private static func gradient(
        _ type: PenGradientType = .linear,
        rotation: Double? = nil,
        center: (Double, Double)? = nil,
        size: (Double, Double)? = nil
    ) -> PenFill.PenGradientFill {
        PenFill.PenGradientFill(
            gradientType: type,
            center: center.map { PenFill.PenFillPosition(x: $0.0, y: $0.1) },
            size: size.map { PenFill.PenFillSize(width: .literal($0.0), height: .literal($0.1)) },
            rotation: rotation.map { .literal($0) }
        )
    }

    /// Rotation, center and size of each geometry the ramp and bearing tests walk.
    private static let geometries: [(Double, (Double, Double), (Double, Double))] = [
        (0, (0.5, 0.5), (1, 1)),
        (45, (0.5, 0.5), (1, 1)),
        (30, (0.3, 0.4), (1, 1)),
        (315, (0.3, 0.4), (0.5, 0.6)),
        (210, (0.6, 0.2), (2, 0.5)),
    ]

    @Test("A linear ramp reads 0 at stop 0's point and 1 at stop 1's", arguments: geometries)
    func rampEnds(rotation: Double, center: (Double, Double), size: (Double, Double)) throws {
        let geometry = GradientGeometry(Self.gradient(rotation: rotation, center: center, size: size))
        let ramp = try #require(geometry.linearRamp)
        #expect(abs(ramp.position(at: geometry.linearStart)) < 1e-9)
        #expect(abs(ramp.position(at: geometry.linearEnd) - 1) < 1e-9)
    }

    @Test("A linear ramp is constant along the gradient's own x axis", arguments: geometries)
    func rampIsolines(rotation: Double, center: (Double, Double), size: (Double, Double)) throws {
        let geometry = GradientGeometry(Self.gradient(rotation: rotation, center: center, size: size))
        let ramp = try #require(geometry.linearRamp)
        for y in [-0.5, 0.1, 0.5] {
            let left = ramp.position(at: geometry.point(NormalizedPoint(x: -0.7, y: y)))
            let right = ramp.position(at: geometry.point(NormalizedPoint(x: 0.4, y: y)))
            #expect(abs(left - right) < 1e-9)
            #expect(abs(left - (0.5 - y)) < 1e-9)
        }
    }

    @Test("A gradient of zero size has no ramp")
    func collapsedRamp() {
        #expect(GradientGeometry(Self.gradient(size: (0, 1))).linearRamp == nil)
    }

    @Test("On a square box an angular gradient's bearing is its turn, less the rotation")
    func squareBearing() {
        let geometry = GradientGeometry(Self.gradient(.angular, rotation: 90))
        #expect(abs(geometry.angularBearing(atTurn: 0, width: 100, height: 100) - 270) < 1e-9)
        #expect(abs(geometry.angularBearing(atTurn: 0.25, width: 100, height: 100)) < 1e-9)
        #expect(geometry.keepsAngles(width: 100, height: 100))
    }

    @Test("A stretched box bends an angular gradient's bearings")
    func stretchedBearing() {
        let geometry = GradientGeometry(Self.gradient(.angular, rotation: 45))
        // Straight up turned 45° counter-clockwise points at (−½√2, −½√2) in the unit
        // box; stretched to 2:1 that is (−√2, −½√2), a bearing of 296.57°.
        #expect(abs(geometry.angularBearing(atTurn: 0, width: 200, height: 100) - 296.565) < 1e-3)
        #expect(!geometry.keepsAngles(width: 200, height: 100))
        #expect(GradientGeometry(Self.gradient(.angular, size: (0.5, 1))).keepsAngles(width: 200, height: 100))
    }

    @Test("A mirrored map does not keep angles")
    func mirroredBearing() {
        #expect(!GradientGeometry(Self.gradient(.angular, size: (-1, 1))).keepsAngles(width: 100, height: 100))
    }

    #if canImport(CoreGraphics)
        @Test("The bearing is where the renderer's frame puts that turn", arguments: geometries)
        func bearingAgreesWithRenderer(rotation: Double, center: (Double, Double), size: (Double, Double)) {
            let fill = Self.gradient(.angular, rotation: rotation, center: center, size: size)
            let geometry = GradientGeometry(fill)
            let box = CGRect(x: 0, y: 0, width: 240, height: 72)
            let toGradient = fill.frameTransform(in: box).inverted()
            let origin = CGPoint(x: center.0 * 240, y: center.1 * 72)
            for turn in [0.0, 0.2, 0.5, 0.9] {
                let bearing = geometry.angularBearing(atTurn: turn, width: 240, height: 72) * .pi / 180
                let onRay = CGPoint(x: origin.x + 10 * sin(bearing), y: origin.y - 10 * cos(bearing))
                let q = onRay.applying(toGradient)
                let found = (atan2(q.y, q.x) / (2 * .pi) + 0.25 - turn).truncatingRemainder(dividingBy: 1)
                // A whole turn apart is the same ray.
                #expect(min(abs(found), 1 - abs(found)) < 1e-9, "turn \(turn)")
            }
        }
    #endif

    @Test("A radial ellipse keeps to the box's axes unless it is turned off them")
    func axisAlignedRadii() throws {
        let plain = try #require(GradientGeometry(Self.gradient(.radial, size: (0.5, 1))).axisAlignedRadii)
        #expect(plain.x == 0.25 && plain.y == 0.5)
        let quarter = try #require(GradientGeometry(Self.gradient(.radial, rotation: 90, size: (0.5, 1))).axisAlignedRadii)
        #expect(abs(quarter.x - 0.5) < 1e-9 && abs(quarter.y - 0.25) < 1e-9)
        let circle = try #require(GradientGeometry(Self.gradient(.radial, rotation: 30, size: (0.8, 0.8))).axisAlignedRadii)
        #expect(abs(circle.x - 0.4) < 1e-9 && abs(circle.y - 0.4) < 1e-9)
        #expect(GradientGeometry(Self.gradient(.radial, rotation: 45, size: (0.5, 1))).axisAlignedRadii == nil)
    }
}
