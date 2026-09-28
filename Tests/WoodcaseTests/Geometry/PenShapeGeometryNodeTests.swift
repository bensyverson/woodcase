import Foundation
import Testing
@testable import Woodcase

/// Pins how a node's kind and properties choose its outline and its fill rule.
struct PenShapeGeometryNodeTests {
    private static let box = PenRect(x: 0, y: 0, width: 100, height: 100)

    private func node(_ kind: PenNode.Kind) -> PenNode {
        PenNode(id: "n", common: PenNodeCommon(), kind: kind)
    }

    @Test("A frame outlines as its rounded rectangle")
    func frame() {
        let frame = node(.frame(PenNode.FrameData(cornerRadius: .uniform(.literal(8)))))
        #expect(PenShapeGeometry.outline(for: frame, rect: Self.box)?.elements == [.roundedRect(Self.box, cornerRadius: 8)])
    }

    @Test("A polygon with no count is a hexagon")
    func defaultPolygon() {
        let polygon = node(.polygon(PenNode.PolygonData()))
        #expect(PenShapeGeometry.outline(for: polygon, rect: Self.box)?.elements.count == 7)
    }

    @Test("A path node maps its geometry through its viewBox")
    func pathNode() {
        let path = node(.path(PenNode.PathData(geometry: "M 0 0 L 1 1", viewBox: PenViewBox(x: 0, y: 0, width: 2, height: 2))))
        #expect(PenShapeGeometry.outline(for: path, rect: Self.box)?.elements == [
            .command(.move(to: PenPoint(x: 0, y: 0))), .command(.line(to: PenPoint(x: 50, y: 50))),
        ])
    }

    @Test("A node kind without a shape has no outline")
    func noShape() {
        #expect(PenShapeGeometry.outline(for: node(.text(PenNode.TextData())), rect: Self.box) == nil)
    }

    @Test("Even-odd for a ring and for a path that asks for it; nonzero otherwise")
    func fillRule() {
        #expect(PenShapeGeometry.fillRule(for: node(.ellipse(PenNode.EllipseData(innerRadius: .literal(0.5))))) == .evenodd)
        #expect(PenShapeGeometry.fillRule(for: node(.ellipse(PenNode.EllipseData()))) == .nonzero)
        #expect(PenShapeGeometry.fillRule(for: node(.path(PenNode.PathData(geometry: "M0 0", fillRule: .evenodd)))) == .evenodd)
        #expect(PenShapeGeometry.fillRule(for: node(.path(PenNode.PathData(geometry: "M0 0")))) == .nonzero)
        #expect(PenShapeGeometry.fillRule(for: node(.rectangle(PenNode.RectangleData()))) == .nonzero)
    }
}
