import CoreGraphics
import Testing
@testable import Woodcase

struct PenTransformBuilderTests {
    // MARK: - Identity

    @Test("No transform properties produces identity")
    func identityTransform() {
        let node = PenNode(id: "n", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        let transform = PenTransformBuilder.buildTransform(for: node, rect: rect)
        #expect(transform.isIdentity)
    }

    // MARK: - Rotation

    @Test("90 degree rotation")
    func rotation90() {
        let node = PenNode(
            id: "n",
            common: PenNodeCommon(rotation: .literal(90)),
            kind: .rectangle(PenNode.RectangleData())
        )
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        let transform = PenTransformBuilder.buildTransform(for: node, rect: rect)
        #expect(!transform.isIdentity)
        // Center point (50,50) should map to itself (rotation around center)
        let center = CGPoint(x: 50, y: 50).applying(transform)
        #expect(abs(center.x - 50) < 0.01)
        #expect(abs(center.y - 50) < 0.01)
        // Top-left (0,0) should rotate to (100,0) for 90° CW
        // .pen rotation is counter-clockwise, so 90° CCW maps (0,0) → (0,100)
        let topLeft = CGPoint(x: 0, y: 0).applying(transform)
        #expect(abs(topLeft.x - 0) < 0.5 || abs(topLeft.x - 100) < 0.5)
    }

    @Test("45 degree rotation keeps center fixed")
    func rotation45() {
        let node = PenNode(
            id: "n",
            common: PenNodeCommon(rotation: .literal(45)),
            kind: .rectangle(PenNode.RectangleData())
        )
        let rect = PenRect(x: 0, y: 0, width: 80, height: 80)
        let transform = PenTransformBuilder.buildTransform(for: node, rect: rect)
        let center = CGPoint(x: 40, y: 40).applying(transform)
        #expect(abs(center.x - 40) < 0.01)
        #expect(abs(center.y - 40) < 0.01)
    }

    // MARK: - Pivot vs. the 2.17 schema wording

    /// The 2.17 schema's doc comment for `rotation` reads "Degrees CCW around
    /// top-left corner." Read literally, the renderer's transform should pivot
    /// at the node's own `(0, 0)`. It does not — it pivots at the rect's
    /// center, as it always has (see the `Transform` step in
    /// `Documentation.docc/PenRendering.md`).
    ///
    /// Measured against Pen.app's own rendered PNG for
    /// `render-transforms-and-effects.pen` (`PenSnapshotTests`, fixture holds a
    /// rectangle rotated 45°), pivoting at `(0, 0)` instead of the center raises
    /// that fixture's MAE from 1.12 to 10.77 against an 8.0 threshold — center
    /// pivot is what Pen.app actually draws. The schema's "top-left corner" is
    /// the position anchor that does not move as a node rotates (the *layout*
    /// bounding box that ``PenLayoutEngine`` expands for a rotated node keeps
    /// its top-left at the node's declared `x`/`y`), not the transform's pivot
    /// point. See the correction under decision 10 in
    /// `project/2026-08-29-pen-2.17-migration.md`.
    @Test("Rotation pivots at the rect's center, not its top-left corner")
    func rotationDoesNotPivotAtTopLeft() {
        let node = PenNode(
            id: "n",
            common: PenNodeCommon(rotation: .literal(90)),
            kind: .rectangle(PenNode.RectangleData())
        )
        let rect = PenRect(x: 0, y: 0, width: 100, height: 40)
        let transform = PenTransformBuilder.buildTransform(for: node, rect: rect)

        // If the pivot were the top-left corner, (0, 0) would map to itself.
        let topLeft = CGPoint(x: 0, y: 0).applying(transform)
        #expect(abs(topLeft.x) > 1 || abs(topLeft.y) > 1)

        // The pivot actually used is the rect's own center.
        let midX = CGFloat(rect.width) / 2
        let midY = CGFloat(rect.height) / 2
        let center = CGPoint(x: midX, y: midY).applying(transform)
        #expect(abs(center.x - midX) < 0.01)
        #expect(abs(center.y - midY) < 0.01)
    }

    // MARK: - Flip

    @Test("FlipX mirrors horizontally around center")
    func flipX() {
        let node = PenNode(
            id: "n",
            common: PenNodeCommon(flipX: .literal(true)),
            kind: .rectangle(PenNode.RectangleData())
        )
        let rect = PenRect(x: 0, y: 0, width: 100, height: 50)
        let transform = PenTransformBuilder.buildTransform(for: node, rect: rect)
        // Left edge (0, 25) should map to right edge (100, 25)
        let left = CGPoint(x: 0, y: 25).applying(transform)
        #expect(abs(left.x - 100) < 0.01)
        #expect(abs(left.y - 25) < 0.01)
    }

    @Test("FlipY mirrors vertically around center")
    func flipY() {
        let node = PenNode(
            id: "n",
            common: PenNodeCommon(flipY: .literal(true)),
            kind: .rectangle(PenNode.RectangleData())
        )
        let rect = PenRect(x: 0, y: 0, width: 100, height: 50)
        let transform = PenTransformBuilder.buildTransform(for: node, rect: rect)
        // Top edge (50, 0) should map to bottom edge (50, 50)
        let top = CGPoint(x: 50, y: 0).applying(transform)
        #expect(abs(top.x - 50) < 0.01)
        #expect(abs(top.y - 50) < 0.01)
    }

    // MARK: - Combined

    @Test("Rotation + flipX combined")
    func rotationPlusFlipX() {
        let node = PenNode(
            id: "n",
            common: PenNodeCommon(rotation: .literal(90), flipX: .literal(true)),
            kind: .rectangle(PenNode.RectangleData())
        )
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        let transform = PenTransformBuilder.buildTransform(for: node, rect: rect)
        // Center should still be fixed
        let center = CGPoint(x: 50, y: 50).applying(transform)
        #expect(abs(center.x - 50) < 0.01)
        #expect(abs(center.y - 50) < 0.01)
    }
}
