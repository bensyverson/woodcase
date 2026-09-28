import CoreGraphics
import Testing
@testable import Woodcase

struct CGPathTightBoundingBoxTests {
    @Test("Tight bounding box excludes cubic control points that extend beyond curve")
    func tightBboxNarrowerThanBbox() {
        // Build a heart-like shape with cubic curves whose control points
        // bow outward beyond the rendered curve.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 50, y: 80))
        // Left lobe: control points at x=-20 and x=10 extend beyond the curve
        path.addCurve(
            to: CGPoint(x: 50, y: 20),
            control1: CGPoint(x: -20, y: 40),
            control2: CGPoint(x: 10, y: -10)
        )
        // Right lobe: control points at x=90 and x=120 extend beyond the curve
        path.addCurve(
            to: CGPoint(x: 50, y: 80),
            control1: CGPoint(x: 90, y: -10),
            control2: CGPoint(x: 120, y: 40)
        )
        path.closeSubpath()

        let bbox = path.boundingBox
        let tight = path.tightBoundingBox

        // The standard boundingBox includes control points at x=-20 and x=120
        #expect(bbox.minX < tight.minX, "Tight bbox minX should be larger (control points excluded)")
        #expect(bbox.maxX > tight.maxX, "Tight bbox maxX should be smaller (control points excluded)")
        #expect(tight.width < bbox.width, "Tight bbox should be narrower than standard bbox")
    }

    @Test("Tight bounding box matches standard bbox for straight-line paths")
    func tightBboxMatchesForLines() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 10, y: 20))
        path.addLine(to: CGPoint(x: 100, y: 50))
        path.addLine(to: CGPoint(x: 60, y: 90))
        path.closeSubpath()

        let bbox = path.boundingBox
        let tight = path.tightBoundingBox

        #expect(abs(tight.minX - bbox.minX) < 0.01)
        #expect(abs(tight.minY - bbox.minY) < 0.01)
        #expect(abs(tight.width - bbox.width) < 0.01)
        #expect(abs(tight.height - bbox.height) < 0.01)
    }

    @Test("Tight bounding box handles quadratic curves")
    func tightBboxQuadratic() {
        // Quadratic curve with control point extending beyond the curve
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: -100))
        path.closeSubpath()

        let bbox = path.boundingBox
        let tight = path.tightBoundingBox

        // The control point is at y=-100, but the curve only reaches y=-50
        // Standard bbox includes the control point
        #expect(bbox.minY < tight.minY, "Tight bbox should exclude quad control point")
        // The quadratic extremum is at t=0.5: B(0.5) = 0.25*0 + 0.5*(-100) + 0.25*0 = -50
        #expect(abs(tight.minY + 50) < 0.5, "Tight bbox minY should be at curve extremum")
    }

    @Test("SVG heart path through PenShapeBuilder fills target rect width")
    func heartSVGFillsTargetRect() throws {
        // A heart SVG geometry string — the control points extend beyond the visual curve
        let heartGeometry = "M50,80 C-20,40 10,-10 50,20 C90,-10 120,40 50,80 Z"
        let targetRect = CGRect(x: 0, y: 0, width: 60, height: 60)

        let builtPath = try #require(PenShapeBuilder.buildPath(
            for: .path(geometry: heartGeometry),
            rect: PenRect(x: 0, y: 0, width: 60, height: 60)
        ))

        let resultBbox = builtPath.boundingBox
        // The built path should fill the target rect's width reasonably well
        // (within a few points), not be squished narrow due to inflated source bbox
        #expect(resultBbox.width > targetRect.width * 0.8,
                "Heart path should fill target rect width, not be squished (\(resultBbox.width) vs \(targetRect.width))")
    }
}
