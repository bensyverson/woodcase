//
//  FigmaImportShapeTypeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `RECTANGLE`, `LINE`, `REGULAR_POLYGON` and `STAR`. No committed capture holds any of
/// them, so each is built here as a synthetic message; E2b's line is checked from the local
/// capture in ``FigmaImportCaptureShapeTests``.
struct FigmaImportShapeTypeTests {
    private typealias Fixtures = FigmaImportFixtures

    /// The single root of a message of `nodes`, imported.
    private static func importOne(_ node: KiwiRecord, blobs: [Data] = []) throws -> (PenNode, FigmaImport) {
        let result = try FigmaImporter().clip(from: Fixtures.message([node], blobs: blobs))
        return try (#require(result.clip.document.children.first), result)
    }

    /// Where Pen draws the point `local` of `node`, on the canvas.
    private static func penCanvasPoint(_ local: PenPoint, of result: FigmaImport, node: PenNode) throws -> PenPoint {
        let document = result.clip.document
        let rects = PenLayoutEngine.layout(document)
        let map = try #require(PenLayoutEngine.canvasTransform(of: node.id, in: document, layoutRects: rects))
        return map.apply(to: local)
    }

    /// A Figma matrix turning `degrees` clockwise on screen, moved to `(x, y)`.
    private static func matrix(degrees: Double, x: Double, y: Double) -> KiwiValue {
        let radians = degrees * .pi / 180
        return .structure(KiwiRecord(typeName: "Matrix", fields: [
            "m00": .float(Float(cos(radians))), "m01": .float(Float(-sin(radians))), "m02": .float(Float(x)),
            "m10": .float(Float(sin(radians))), "m11": .float(Float(cos(radians))), "m12": .float(Float(y)),
        ]))
    }

    private static func expectClose(_ lhs: PenPoint, _ rhs: PenPoint, _ comment: Comment? = nil) {
        #expect(abs(lhs.x - rhs.x) <= 0.01 && abs(lhs.y - rhs.y) <= 0.01, "\(lhs) vs \(rhs) \(comment?.description ?? "")")
    }

    @Test("A plain rectangle maps as a rounded one does, per-corner radii included")
    func rectangle() throws {
        let node = Fixtures.nodeChange("RECTANGLE", name: "plain", id: 70, width: 40, height: 30, extra: [
            "fillPaints": .array([Fixtures.solid(0, 0, 1)]), "rectangleCornerRadiiIndependent": .bool(true),
            "rectangleTopLeftCornerRadius": .float(1), "rectangleTopRightCornerRadius": .float(2),
            "rectangleBottomRightCornerRadius": .float(3), "rectangleBottomLeftCornerRadius": .float(4),
        ])
        let (pen, result) = try Self.importOne(node)
        guard case let .rectangle(data) = pen.kind else {
            Issue.record("\(pen.kind)")
            return
        }
        #expect(data.width == .fixed(40) && data.height == .fixed(30))
        #expect(data.cornerRadius == .perCorner(topLeft: .literal(1), topRight: .literal(2), bottomRight: .literal(3), bottomLeft: .literal(4)))
        #expect(result.losses.isEmpty)
    }

    @Test("A line is a Pen line from its size and transform, its ends where Figma drew them")
    func line() throws {
        let node = Fixtures.nodeChange("LINE", name: "rule", id: 71, width: 120, height: 0, extra: [
            "transform": Self.matrix(degrees: 30, x: 10, y: 20),
            "strokePaints": .array([Fixtures.solid(0, 0, 0)]), "strokeWeight": .float(4),
            "strokeAlign": .enumeration("CENTER"), "strokeCap": .enumeration("ROUND"),
        ])
        let (pen, result) = try Self.importOne(node)
        guard case let .line(data) = pen.kind else {
            Issue.record("\(pen.kind)")
            return
        }
        #expect(data.width == .fixed(120) && data.height == .fixed(0))
        #expect(data.strokeLinecap == .round && data.strokeWidth == .uniform(.literal(4)))
        try Self.expectClose(Self.penCanvasPoint(PenPoint(x: 0, y: 0), of: result, node: pen), PenPoint(x: 10, y: 20))
        let radians = 30 * Double.pi / 180
        try Self.expectClose(
            Self.penCanvasPoint(PenPoint(x: 120, y: 0), of: result, node: pen),
            PenPoint(x: 10 + 120 * cos(radians), y: 20 + 120 * sin(radians))
        )
        #expect(result.losses.isEmpty)
    }

    @Test("A line's arrow cap is drawn butt and reported")
    func lineArrow() throws {
        let node = Fixtures.nodeChange("LINE", name: "arrow", id: 72, width: 80, height: 0, extra: [
            "strokePaints": .array([Fixtures.solid(0, 0, 0)]), "strokeCap": .enumeration("ARROW_LINES"),
        ])
        let (pen, result) = try Self.importOne(node)
        guard case let .line(data) = pen.kind else {
            Issue.record("\(pen.kind)")
            return
        }
        #expect(data.strokeLinecap == .butt)
        #expect(result.losses.map(\.feature) == [.strokeCap])
    }

    /// A polygon node of `count` sides.
    private static func polygon(count: UInt32, paints: [KiwiValue] = [Fixtures.solid(1, 0, 0)]) -> KiwiRecord {
        Fixtures.nodeChange("REGULAR_POLYGON", name: "polygon", id: 73, width: 100, height: 80, extra: [
            "transform": matrix(degrees: 20, x: 50, y: 60), "count": .uint(count), "fillPaints": .array(paints),
        ])
    }

    /// Where Pen draws each corner of an imported polygon, on the canvas.
    private static func polygonCorners(_ pen: PenNode, in result: FigmaImport) throws -> [PenPoint] {
        guard case let .polygon(data) = pen.kind else {
            Issue.record("\(pen.kind)")
            return []
        }
        let box = PenRect(x: 0, y: 0, width: data.width?.fixedValue ?? 0, height: data.height?.fixedValue ?? 0)
        let sides = Int(data.polygonCount?.literalValue ?? 0)
        let corners = try #require(PenShapeGeometry.polygonVertices(in: box, sides: sides))
        return try corners.map { try penCanvasPoint($0, of: result, node: pen) }
    }

    /// `local` through the Figma matrix of ``polygon(count:paints:)``.
    private static func figmaPoint(_ local: PenPoint) -> PenPoint {
        let radians = 20 * Double.pi / 180
        let (cosine, sine) = (Double(Float(cos(radians))), Double(Float(sin(radians))))
        return PenPoint(x: cosine * local.x - sine * local.y + 50, y: sine * local.x + cosine * local.y + 60)
    }

    @Test("A triangle is a Pen polygon whose corners land on Figma's: apex at the top, base on the bottom edge")
    func triangle() throws {
        let (pen, result) = try Self.importOne(Self.polygon(count: 3))
        let corners = try Self.polygonCorners(pen, in: result)
        let expected = [PenPoint(x: 50, y: 0), PenPoint(x: 100, y: 80), PenPoint(x: 0, y: 80)].map(Self.figmaPoint)
        #expect(corners.count == 3)
        for (corner, figma) in zip(corners, expected) {
            Self.expectClose(corner, figma)
        }
        guard case let .polygon(data) = pen.kind else { return }
        #expect(data.polygonCount == .literal(3))
        #expect(result.losses.isEmpty)
    }

    @Test("A square polygon fills its box in both tools, so its box is Figma's")
    func diamond() throws {
        let (pen, _) = try Self.importOne(Self.polygon(count: 4))
        guard case let .polygon(data) = pen.kind else {
            Issue.record("\(pen.kind)")
            return
        }
        #expect(data.width == .fixed(100) && data.height == .fixed(80))
        #expect(pen.common.x == .literal(50) && pen.common.y == .literal(60))
    }

    @Test("A polygon whose Pen box grows to fit its corners reports that a gradient over the box shifts")
    func polygonPaintBox() throws {
        let gradient = KiwiValue.message(KiwiRecord(typeName: "Paint", fields: [
            "type": .enumeration("GRADIENT_LINEAR"), "visible": .bool(true), "opacity": .float(1),
            "stops": .array([]),
        ]))
        let (_, result) = try Self.importOne(Self.polygon(count: 3, paints: [gradient]))
        #expect(result.losses.map(\.feature) == [.polygonBox])
        #expect(result.losses.first?.treatment == .approximated)
    }

    /// A five-point star, 100 × 100, with Figma's default inner ratio.
    private static func star(extra: [String: KiwiValue] = [:]) -> KiwiRecord {
        var fields: [String: KiwiValue] = [
            "count": .uint(5), "starInnerScale": .float(0.382), "fillPaints": .array([Fixtures.solid(1, 0.8, 0)]),
        ]
        fields.merge(extra) { $1 }
        return Fixtures.nodeChange("STAR", name: "star", id: 74, width: 100, height: 100, extra: fields)
    }

    /// An imported path's geometry, mapped onto its box.
    private static func pathPoints(_ pen: PenNode) throws -> [PenPoint] {
        guard case let .path(data) = pen.kind else {
            Issue.record("\(pen.kind)")
            return []
        }
        let geometry = try #require(data.geometry.flatMap { PenPath(svg: $0) })
        let box = PenRect(x: 0, y: 0, width: data.width?.fixedValue ?? 0, height: data.height?.fixedValue ?? 0)
        return geometry.mapped(onto: box, viewBox: data.viewBox).commands.compactMap { command in
            switch command {
            case let .move(to), let .line(to): to
            default: nil
            }
        }
    }

    @Test("A star with no geometry blob is a path computed from its count and inner ratio, filling its box")
    func computedStar() throws {
        let (pen, result) = try Self.importOne(Self.star())
        let points = try Self.pathPoints(pen)
        #expect(points.count == 10)
        // Worked by hand: the unit star spans x ±sin 72°, y −1 to cos 36°, stretched onto 100 × 100.
        Self.expectClose(points[0], PenPoint(x: 50, y: 0))
        Self.expectClose(points[1], PenPoint(x: 61.80, y: 38.20))
        Self.expectClose(points[2], PenPoint(x: 100, y: 38.20))
        let bottom: Double = try #require(points.map(\.y).max())
        #expect(abs(bottom - 100) < 0.01)
        #expect(result.losses.isEmpty)
    }

    @Test("A star that names a geometry blob is drawn from the blob")
    func blobStar() throws {
        let blob = FigmaBlobBytes.network(
            vertices: [(0, 50, 0), (0, 100, 100), (0, 0, 100)],
            segments: [FigmaBlobBytes.line(0, 1), FigmaBlobBytes.line(1, 2), FigmaBlobBytes.line(2, 0)],
            regions: [(1, [[0, 1, 2]])]
        )
        let node = Self.star(extra: [
            "vectorData": .message(KiwiRecord(typeName: "VectorData", fields: [
                "vectorNetworkBlob": .uint(0),
                "normalizedSize": .structure(KiwiRecord(typeName: "Vector", fields: ["x": .float(100), "y": .float(100)])),
            ])),
        ])
        let (pen, _) = try Self.importOne(node, blobs: [blob])
        let points = try Self.pathPoints(pen)
        #expect(points.count == 4)
        Self.expectClose(points[0], PenPoint(x: 50, y: 0))
        Self.expectClose(points[1], PenPoint(x: 100, y: 100))
    }

    @Test("A rounded star is drawn sharp and reported")
    func roundedStar() throws {
        let (_, result) = try Self.importOne(Self.star(extra: ["cornerRadius": .float(4)]))
        #expect(result.losses.map(\.feature) == [.shapeCornerRadius])
    }
}

/// E2b's line, taken out of its slide (which is refused) and imported on its own.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FIGMA_CASES"] != nil, "set FIGMA_CASES to a folder of raw captures"))
struct FigmaImportCaptureShapeTests {
    @Test("E2b's line maps to a Pen line of its size")
    func captureLine() throws {
        let folder = try #require(FigmaClipboardCaptureTests.folder)
        let html = try Data(contentsOf: folder.appendingPathComponent("E2b.html"))
        let message = try FigmaClipboardDecoder().decode(html: html).message
        let changes = try #require(message["nodeChanges"]?.arrayValue)
        let line = try #require(changes.first { $0["type"]?.enumName == "LINE" }?.recordValue)
        var fields = line.fields
        fields["parentIndex"] = .structure(KiwiRecord(typeName: "ParentIndex", fields: [
            "guid": FigmaImportFixtures.guid(0, 1), "position": .string("!"),
        ]))
        let result = try FigmaImporter().clip(from: FigmaImportFixtures.message([KiwiRecord(typeName: line.typeName, fields: fields)]))
        let pen = try #require(result.clip.document.children.first)
        guard case let .line(data) = pen.kind else {
            Issue.record("\(pen.kind)")
            return
        }
        #expect(data.width == .fixed(Double(line["size"]?["x"]?.floatValue ?? -1)))
        #expect(!result.losses.contains { $0.feature == .unreadField }, "\(result.losses)")
        print("E2b line losses: \(result.losses)")
    }
}
