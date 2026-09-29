//
//  GradientGeometryTests.swift
//  WoodcaseTests
//

#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation
import Testing
@testable import Woodcase

/// Pins Pen's gradient map in the node's normalized box, which the emitters share.
struct GradientGeometryTests {
    private static func gradient(
        rotation: Double? = nil,
        center: (Double, Double)? = nil,
        size: (Double, Double)? = nil
    ) -> PenFill.PenGradientFill {
        PenFill.PenGradientFill(
            gradientType: .linear,
            center: center.map { PenFill.PenFillPosition(x: $0.0, y: $0.1) },
            size: size.map { PenFill.PenFillSize(width: .literal($0.0), height: .literal($0.1)) },
            rotation: rotation.map { .literal($0) }
        )
    }

    private static func isClose(_ lhs: NormalizedPoint, _ rhs: NormalizedPoint) -> Bool {
        abs(lhs.x - rhs.x) < 1e-9 && abs(lhs.y - rhs.y) < 1e-9
    }

    @Test("A default linear gradient runs from the bottom edge's middle to the top edge's")
    func defaultLinear() {
        let geometry = GradientGeometry(Self.gradient())
        #expect(Self.isClose(geometry.linearStart, NormalizedPoint(x: 0.5, y: 1)))
        #expect(Self.isClose(geometry.linearEnd, NormalizedPoint(x: 0.5, y: 0)))
        #expect(geometry.rotation == 0)
    }

    @Test("A rotation turns the line counter-clockwise on screen")
    func quarterTurn() {
        let geometry = GradientGeometry(Self.gradient(rotation: 90))
        #expect(Self.isClose(geometry.linearStart, NormalizedPoint(x: 1, y: 0.5)))
        #expect(Self.isClose(geometry.linearEnd, NormalizedPoint(x: 0, y: 0.5)))
        #expect(geometry.rotation == 90)
    }

    @Test("A radial gradient's ellipse is half its size around its center")
    func radialEllipse() {
        let geometry = GradientGeometry(Self.gradient(center: (0.3, 0.6), size: (0.5, 1)))
        #expect(geometry.radiusX == 0.25)
        #expect(geometry.radiusY == 0.5)
        #expect(geometry.center == NormalizedPoint(x: 0.3, y: 0.6))
        #expect(!geometry.isDefaultEllipse)
        #expect(GradientGeometry(Self.gradient()).isDefaultEllipse)
    }

    @Test(
        "`affineComponents` is the map's row-vector matrix: x′ = a·x + c·y + tx, y′ = b·x + d·y + ty",
        arguments: [
            (0.0, (0.5, 0.5), (1.0, 1.0)),
            (30.0, (0.25, 0.75), (2.0, 0.5)),
            (-135.0, (0.6, 0.2), (0.5, 1.5)),
        ]
    )
    func affineComponentsMatchTheFormula(rotation: Double, center: (Double, Double), size: (Double, Double)) {
        let geometry = GradientGeometry(Self.gradient(rotation: rotation, center: center, size: size))
        let radians = rotation * Double.pi / 180
        let m = geometry.affineComponents
        #expect(abs(m.a - size.0 * cos(radians)) < 1e-9)
        #expect(abs(m.b - -size.0 * sin(radians)) < 1e-9)
        #expect(abs(m.c - size.1 * sin(radians)) < 1e-9)
        #expect(abs(m.d - size.1 * cos(radians)) < 1e-9)
        #expect(m.tx == center.0)
        #expect(m.ty == center.1)
    }

    #if canImport(CoreGraphics)
        @Test(
            "The renderer's `frameTransform(in:)` is `affineComponents` plus the stretch to the box — the one map, checked at both ends",
            arguments: [
                (0.0, (0.5, 0.5), (1.0, 1.0)),
                (30.0, (0.25, 0.75), (2.0, 1.0)),
                (-135.0, (0.6, 0.2), (0.5, 1.5)),
            ]
        )
        func agreesWithRenderer(rotation: Double, center: (Double, Double), size: (Double, Double)) {
            let fill = Self.gradient(rotation: rotation, center: center, size: size)
            let geometry = GradientGeometry(fill)
            let frame = fill.frameTransform(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            for point in [(0.0, 0.5), (0.0, -0.5), (0.5, 0.0), (0.3, -0.2)] {
                let expected = CGPoint(x: point.0, y: point.1).applying(frame)
                let actual = geometry.point(NormalizedPoint(x: point.0, y: point.1))
                #expect(Self.isClose(actual, NormalizedPoint(x: expected.x, y: expected.y)), "\(point)")
            }
        }
    #endif
}
