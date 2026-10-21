//
//  FigmaImportSession+Vector.swift
//  Woodcase
//

import Foundation

extension FigmaImportSession {
    /// A vector network as a Pen path.
    ///
    /// The geometry is every filled region's loops, under the first region's winding rule —
    /// the outline a fill covers and a stroke traces. A network with no region is stroked
    /// segment by segment. The path draws in `vectorData.normalizedSize` space, which the
    /// viewBox stretches onto the node's size, as Figma does.
    mutating func vector(_ record: KiwiRecord, common: inout PenNodeCommon) throws(FigmaImportError) -> PenNode.Kind {
        let size = size(of: record)
        let vectorData = record["vectorData"]
        let network: FigmaVectorNetwork
        if let index = vectorData?["vectorNetworkBlob"]?.uintValue {
            do { network = try blobs.vectorNetwork(at: index) } catch { throw .blob(error) }
        } else {
            network = FigmaVectorNetwork()
        }
        let graphics = graphics(of: record, common: &common)
        var commands: [FigmaPathCommand] = []
        var rule = FigmaWindingRule.nonzero
        if network.regions.isEmpty {
            commands = network.segmentPath().commands
        } else {
            for index in network.regions.indices {
                do { try commands += network.path(ofRegion: index).commands } catch { throw .blob(error) }
            }
            rule = network.regions[0].windingRule
            if Set(network.regions.map(\.windingRule)).count > 1 {
                report(.windingRules, .approximated, on: record)
            }
            let looped = Set(network.regions.flatMap { $0.loops.joined() })
            if graphics.stroke != nil, looped.count < network.segments.count {
                report(.openStrokeSegments, .dropped, on: record)
            }
        }
        reportStyleOverrides(of: record, network: network)
        let normalized = (
            width: vectorData?["normalizedSize"]?["x"]?.doubleValue ?? size.width,
            height: vectorData?["normalizedSize"]?["y"]?.doubleValue ?? size.height
        )
        return .path(PenNode.PathData(
            width: .fixed(size.width), height: .fixed(size.height),
            geometry: Self.svgPathData(commands),
            viewBox: PenViewBox(x: 0, y: 0, width: normalized.width, height: normalized.height),
            fillRule: rule == .evenOdd ? .evenodd : nil,
            fills: graphics.fills, stroke: graphics.stroke, strokeWidth: graphics.strokeWidth,
            strokeLinecap: graphics.strokeLinecap, strokeLinejoin: graphics.strokeLinejoin,
            strokeAlignment: graphics.strokeAlignment, effects: graphics.effects
        ))
    }

    /// Reports the network's per-vertex, per-segment or per-region styles that differ from
    /// the node's own: Pen strokes and rounds a path one way throughout.
    private mutating func reportStyleOverrides(of record: KiwiRecord, network: FigmaVectorNetwork) {
        let used = Set(network.vertices.map(\.styleID) + network.segments.map(\.styleID) + network.regions.map(\.styleID))
        let table = record["vectorData"]?["styleOverrideTable"]?.arrayValue ?? []
        let nodeCap = record["strokeCap"]?.enumName ?? "NONE"
        let nodeJoin = record["strokeJoin"]?.enumName ?? "MITER"
        for entry in table {
            guard let id = entry["styleID"]?.uintValue, used.contains(id) else { continue }
            var differing: [String] = []
            if let cap = entry["strokeCap"]?.enumName, cap != nodeCap { differing.append("strokeCap") }
            if let join = entry["strokeJoin"]?.enumName, join != nodeJoin { differing.append("strokeJoin") }
            if let radius = entry["cornerRadius"]?.doubleValue, radius != 0 { differing.append("cornerRadius") }
            if entry["fillPaints"] != nil { differing.append("fillPaints") }
            for field in differing {
                report(.vectorStyleOverride, .dropped, on: record, detail: field)
            }
        }
    }

    /// `commands` as SVG path data, coordinates to four places.
    static func svgPathData(_ commands: [FigmaPathCommand]) -> String {
        func point(_ point: FigmaPoint) -> PenPoint {
            PenPoint(x: point.x, y: point.y)
        }
        let elements: [PenShapeOutline.Element] = commands.map { command in
            switch command {
            case let .move(to): .command(.move(to: point(to)))
            case let .line(to): .command(.line(to: point(to)))
            case let .quadratic(control, to): .command(.quadCurve(to: point(to), control: point(control)))
            case let .cubic(control1, control2, to):
                .command(.cubicCurve(to: point(to), control1: point(control1), control2: point(control2)))
            case .close: .command(.close)
            }
        }
        return PenShapeOutline(elements: elements).svgPathData(number: \.svgNumber)
    }
}
