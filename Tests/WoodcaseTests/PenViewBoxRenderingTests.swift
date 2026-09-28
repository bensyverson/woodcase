//
//  PenViewBoxRenderingTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Testing
@testable import Woodcase

/// Covers how `PenShapeBuilder` maps path geometry onto the node box, with and
/// without a `viewBox`. The four cases mirror `Fixtures/v2.17/viewbox-experiment.pen`.
struct PenViewBoxRenderingTests {
    /// The triangle used by every case of the viewbox experiment: (10,10) (90,10) (50,90).
    private let triangle = "M10 10l80 0-40 80z"

    private func bounds(
        viewBox: PenViewBox?,
        rect: PenRect
    ) throws -> CGRect {
        let path = try #require(PenShapeBuilder.buildPath(
            for: .path(geometry: triangle, viewBox: viewBox),
            rect: rect
        ))
        return path.boundingBox
    }

    private func expectBounds(
        _ box: CGRect,
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(box.minX - x) < 0.01, "minX \(box.minX) != \(x)", sourceLocation: sourceLocation)
        #expect(abs(box.minY - y) < 0.01, "minY \(box.minY) != \(y)", sourceLocation: sourceLocation)
        #expect(abs(box.width - width) < 0.01, "width \(box.width) != \(width)", sourceLocation: sourceLocation)
        #expect(abs(box.height - height) < 0.01, "height \(box.height) != \(height)", sourceLocation: sourceLocation)
    }

    // MARK: - No viewBox (tight bounding box stretched onto the node box)

    @Test("Without a viewBox the tight bounding box is stretched onto the node box")
    func noViewBoxStretchesTightBoundingBox() throws {
        let box = try bounds(viewBox: nil, rect: PenRect(x: 20, y: 20, width: 200, height: 200))
        expectBounds(box, x: 20, y: 20, width: 200, height: 200)
    }

    // MARK: - viewBox present

    @Test("A viewBox matching the node box places the geometry at its own coordinates")
    func viewBoxSameSize() throws {
        let box = try bounds(
            viewBox: PenViewBox(x: 0, y: 0, width: 200, height: 200),
            rect: PenRect(x: 240, y: 20, width: 200, height: 200)
        )
        // (10,10)–(90,90) in viewBox space, offset by the node origin.
        expectBounds(box, x: 250, y: 30, width: 80, height: 80)
    }

    @Test("A smaller viewBox scales up and lets the geometry overflow the node box")
    func viewBoxSmallerOverflows() throws {
        let box = try bounds(
            viewBox: PenViewBox(x: 25, y: 25, width: 50, height: 50),
            rect: PenRect(x: 460, y: 20, width: 200, height: 200)
        )
        // 4x scale about (25,25): (10,10) → (-60,-60), (90,90) → (260,260), plus the node origin.
        expectBounds(box, x: 400, y: -40, width: 320, height: 320)
    }

    @Test("A viewBox with a different aspect ratio stretches non-uniformly")
    func viewBoxNonUniform() throws {
        let box = try bounds(
            viewBox: PenViewBox(x: 0, y: 0, width: 100, height: 100),
            rect: PenRect(x: 680, y: 20, width: 200, height: 100)
        )
        // 2x horizontally, 1x vertically — no aspect preservation.
        expectBounds(box, x: 700, y: 30, width: 160, height: 80)
    }

    @Test("A viewBox translation moves the geometry within the node box")
    func viewBoxTranslationOnly() throws {
        let box = try bounds(
            viewBox: PenViewBox(x: 10, y: 10, width: 100, height: 100),
            rect: PenRect(x: 0, y: 0, width: 100, height: 100)
        )
        expectBounds(box, x: 0, y: 0, width: 80, height: 80)
    }

    // MARK: - Degenerate viewBox

    @Test("A viewBox with a zero dimension falls back to the tight bounding box")
    func degenerateViewBoxFallsBack() throws {
        let box = try bounds(
            viewBox: PenViewBox(x: 0, y: 0, width: 0, height: 200),
            rect: PenRect(x: 0, y: 0, width: 200, height: 200)
        )
        expectBounds(box, x: 0, y: 0, width: 200, height: 200)
    }

    // MARK: - Node-level building

    @Test("buildPath(for:rect:) reads the viewBox from a path node")
    func buildPathFromNodeUsesViewBox() throws {
        let node = PenNode(
            id: "p1",
            common: PenNodeCommon(),
            kind: .path(PenNode.PathData(
                width: .fixed(200),
                height: .fixed(200),
                geometry: triangle,
                viewBox: PenViewBox(x: 0, y: 0, width: 200, height: 200)
            ))
        )
        let path = try #require(PenShapeBuilder.buildPath(
            for: node,
            rect: PenRect(x: 0, y: 0, width: 200, height: 200)
        ))
        expectBounds(path.boundingBox, x: 10, y: 10, width: 80, height: 80)
    }
}
