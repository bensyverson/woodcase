//
//  FigmaImportGeometryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The importer's geometry against two oracles: Figma's own transforms, composed up to the
/// canvas, and Figma's SVG export. Pen's side is Woodcase's layout of the imported clip, so
/// the test holds the mapping to where Pen would draw each node, not to the mapper's own
/// arithmetic.
struct FigmaImportGeometryTests {
    private typealias Fixtures = FigmaImportFixtures

    /// Lays out an imported case and returns, for every Pen node, the map from its own
    /// coordinates to the canvas.
    private static func penTransforms(_ result: FigmaImport) -> [String: PenLayoutEngine.PlaneTransform] {
        let document = result.clip.document
        let rects = PenLayoutEngine.layout(document)
        var maps: [String: PenLayoutEngine.PlaneTransform] = [:]
        for node in Fixtures.allNodes(document) {
            maps[node.id] = PenLayoutEngine.canvasTransform(of: node.id, in: document, layoutRects: rects)
        }
        return maps
    }

    @Test("Every node of V1, T1 and G1 lands where Figma drew it, within 0.01 pt", arguments: ["V1", "T1", "G1"])
    func everyNodeLandsInPlace(caseID: String) throws {
        let result = try Fixtures.imported(caseID)
        let maps = Self.penTransforms(result)
        let nodes = Fixtures.allNodes(result.clip.document)
        #expect(nodes.count > 5)
        for node in nodes {
            let name = try #require(node.common.name)
            let figma = try FigmaBlobTableTests.node(name, in: caseID)
            let size = Fixtures.size(of: figma)
            let pen = try #require(maps[node.id], "\(name) was laid out")
            let distance = try Fixtures.cornerDistance(
                pen, Fixtures.figmaCanvasTransform(name, in: caseID), width: size.width, height: size.height
            )
            #expect(distance <= 0.01, "\(caseID) \(name): \(distance) pt off")
        }
    }

    @Test("A frame, rectangle, ellipse or path keeps its Figma size", arguments: ["V1", "G1"])
    func sizesSurvive(caseID: String) throws {
        let result = try Fixtures.imported(caseID)
        for node in Fixtures.allNodes(result.clip.document) {
            let name = try #require(node.common.name)
            let size = try Fixtures.size(of: FigmaBlobTableTests.node(name, in: caseID))
            let declared: (PenSizing?, PenSizing?)? = switch node.kind {
            case let .frame(data): (data.width, data.height)
            case let .rectangle(data): (data.width, data.height)
            case let .ellipse(data): (data.width, data.height)
            case let .path(data): (data.width, data.height)
            default: nil
            }
            guard let declared else { continue }
            #expect(declared.0?.fixedValue == size.width && declared.1?.fixedValue == size.height, "\(name)")
        }
    }

    /// A path node's geometry as Pen draws it, on the canvas.
    private static func canvasPath(_ node: PenNode, map: PenLayoutEngine.PlaneTransform) throws -> PenPath {
        guard case let .path(data) = node.kind else {
            Issue.record("\(node.common.name ?? node.id) is not a path")
            return PenPath(commands: [])
        }
        let geometry = try #require(data.geometry.flatMap { PenPath(svg: $0) })
        let box = PenRect(x: 0, y: 0, width: data.width?.fixedValue ?? 0, height: data.height?.fixedValue ?? 0)
        let mapped = geometry.mapped(onto: box, viewBox: data.viewBox)
        return PenPath(commands: mapped.commands.map { $0.mappingPoints { map.apply(to: $0) } })
    }

    /// Pen path commands as the SVG oracle's commands.
    private static func figmaCommands(_ path: PenPath) -> [FigmaPathCommand] {
        func point(_ point: PenPoint) -> FigmaPoint {
            FigmaPoint(x: point.x, y: point.y)
        }
        return path.commands.map { command in
            switch command {
            case let .move(to): .move(to: point(to))
            case let .line(to): .line(to: point(to))
            case let .quadCurve(to, control): .quadratic(control: point(control), to: point(to))
            case let .cubicCurve(to, control1, control2): .cubic(control1: point(control1), control2: point(control2), to: point(to))
            case .close: .close
            }
        }
    }

    @Test("Every V1 vector's path, drawn where Pen draws it, is the exported path within 0.01 pt", arguments: [
        "V1a closed filled triangle", "V1c flattened donut", "V1d star nonzero", "V1d star evenodd",
        "V1f compound", "V1g open curves", "V1h line",
    ])
    func vectorPaths(name: String) throws {
        let result = try Fixtures.imported("V1")
        let node = try Fixtures.node(name, in: result.clip.document)
        let map = try #require(Self.penTransforms(result)[node.id])
        let commands = try Self.figmaCommands(Self.canvasPath(node, map: map))
        let reference = try FigmaSVGOracle.paths("V1").first { FigmaSVGOracle.matches(commands, $0.commands) }
        let element = try #require(reference, "\(name): \(commands)")
        guard case let .path(data) = node.kind else { return }
        if data.fills != nil {
            #expect((element.attributes["fill-rule"] == "evenodd") == (data.fillRule == .evenodd), "\(name)")
        }
    }

    @Test("Each V1 boolean becomes one path whose outline has the exported path's bounds", arguments: [
        "V1b donut", "V1e union", "V1e subtract", "V1e intersect", "V1e exclude",
    ])
    func booleanPaths(name: String) throws {
        let result = try Fixtures.imported("V1")
        let node = try Fixtures.node(name, in: result.clip.document)
        let map = try #require(Self.penTransforms(result)[node.id])
        let bounds = try #require(Self.canvasPath(node, map: map).tightBounds)
        let references = try FigmaSVGOracle.paths("V1").compactMap { element -> PenRect? in
            PenPath(commands: element.commands.map(Self.penCommand)).tightBounds
        }
        let match = references.first {
            abs($0.x - bounds.x) <= 0.01 && abs($0.y - bounds.y) <= 0.01
                && abs($0.width - bounds.width) <= 0.01 && abs($0.height - bounds.height) <= 0.01
        }
        #expect(match != nil, "\(name): \(bounds)")
        #expect(Fixtures.losses(name, in: result).contains { $0.feature == .booleanOperation })
    }

    @Test("A subtracted donut keeps its hole")
    func donutHole() throws {
        let result = try Fixtures.imported("V1")
        let node = try Fixtures.node("V1b donut", in: result.clip.document)
        guard case let .path(data) = node.kind else {
            Issue.record("not a path")
            return
        }
        let geometry = try #require(data.geometry.flatMap { PenPath(svg: $0) })
        let subpaths = geometry.commands.filter { if case .move = $0 { true } else { false } }
        #expect(subpaths.count == 2)
    }

    private static func penCommand(_ command: FigmaPathCommand) -> PenPathCommand {
        func point(_ point: FigmaPoint) -> PenPoint {
            PenPoint(x: point.x, y: point.y)
        }
        return switch command {
        case let .move(to): .move(to: point(to))
        case let .line(to): .line(to: point(to))
        case let .quadratic(control, to): .quadCurve(to: point(to), control: point(control))
        case let .cubic(control1, control2, to): .cubicCurve(to: point(to), control1: point(control1), control2: point(control2))
        case .close: .close
        }
    }
}
