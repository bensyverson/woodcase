//
//  FigmaImportSession+Shapes.swift
//  Woodcase
//

import Foundation

extension FigmaImportSession {
    /// The node's `size`, in points.
    func size(of record: KiwiRecord) -> (width: Double, height: Double) {
        (record["size"]?["x"]?.doubleValue ?? 0, record["size"]?["y"]?.doubleValue ?? 0)
    }

    /// A frame, section or component as a Pen frame that lays nothing out, so each child
    /// keeps the position Figma gave it — auto layout's included (reported).
    mutating func frame(_ record: KiwiRecord, guid: FigmaGUID, common: inout PenNodeCommon) throws(FigmaImportError) -> PenNode.Kind {
        let size = size(of: record)
        let graphics = graphics(of: record, common: &common)
        if let mode = record["stackMode"]?.enumName, mode != "NONE" {
            report(.autoLayout, .flattened, on: record, detail: mode)
        }
        if !(record["layoutGrids"]?.arrayValue ?? []).isEmpty {
            report(.layoutGrid, .dropped, on: record)
        }
        let children = try children(of: guid)
        return .frame(PenNode.FrameData(
            width: .fixed(size.width), height: .fixed(size.height),
            cornerRadius: cornerRadius(of: record),
            clip: record["frameMaskDisabled"]?.boolValue == true ? nil : .literal(true),
            fills: graphics.fills, stroke: graphics.stroke, strokeWidth: graphics.strokeWidth,
            strokeLinecap: graphics.strokeLinecap, strokeLinejoin: graphics.strokeLinejoin,
            strokeAlignment: graphics.strokeAlignment, effects: graphics.effects,
            layout: PenLayoutDirection.none, children: children
        ))
    }

    /// A frame Figma resizes to fit its children — Figma's group — as a Pen group.
    mutating func group(_ record: KiwiRecord, guid: FigmaGUID, common: inout PenNodeCommon) throws(FigmaImportError) -> PenNode.Kind {
        let graphics = graphics(of: record, common: &common)
        if graphics.fills != nil || graphics.stroke != nil {
            report(.unsupportedPaint, .dropped, on: record, detail: "a group's own paint")
        }
        return try .group(PenNode.GroupData(effects: graphics.effects, children: children(of: guid)))
    }

    /// A rectangle.
    mutating func rectangle(_ record: KiwiRecord, common: inout PenNodeCommon) -> PenNode.Kind {
        let size = size(of: record)
        let graphics = graphics(of: record, common: &common)
        return .rectangle(PenNode.RectangleData(
            width: .fixed(size.width), height: .fixed(size.height), cornerRadius: cornerRadius(of: record),
            fills: graphics.fills, stroke: graphics.stroke, strokeWidth: graphics.strokeWidth,
            strokeLinecap: graphics.strokeLinecap, strokeLinejoin: graphics.strokeLinejoin,
            strokeAlignment: graphics.strokeAlignment, effects: graphics.effects
        ))
    }

    /// An ellipse, with its arc and ring.
    ///
    /// Figma's `arcData` angles are radians clockwise on screen from +x; Pen's are degrees
    /// counter-clockwise, so both flip sign. A whole turn is Pen's default and is left out.
    mutating func ellipse(_ record: KiwiRecord, common: inout PenNodeCommon) -> PenNode.Kind {
        let size = size(of: record)
        let graphics = graphics(of: record, common: &common)
        var data = PenNode.EllipseData(
            width: .fixed(size.width), height: .fixed(size.height),
            fills: graphics.fills, stroke: graphics.stroke, strokeWidth: graphics.strokeWidth,
            strokeLinecap: graphics.strokeLinecap, strokeLinejoin: graphics.strokeLinejoin,
            strokeAlignment: graphics.strokeAlignment, effects: graphics.effects
        )
        if let arc = record["arcData"] {
            let start = arc["startingAngle"]?.doubleValue ?? 0
            let end = arc["endingAngle"]?.doubleValue ?? 2 * .pi
            let inner = arc["innerRadius"]?.doubleValue ?? 0
            if abs(abs(end - start) - 2 * .pi) > 1e-5 {
                data.startAngle = start == 0 ? nil : .literal(-start * 180 / .pi)
                data.sweepAngle = .literal(-(end - start) * 180 / .pi)
            }
            if inner > 0 { data.innerRadius = .literal(inner) }
        }
        return .ellipse(data)
    }

    /// A rectangle's or frame's corner radius: uniform unless Figma made the corners
    /// independent and they differ; `nil` for square corners.
    func cornerRadius(of record: KiwiRecord) -> PenCornerRadius? {
        let uniform = record["cornerRadius"]?.doubleValue
        func corner(_ key: String) -> Double {
            record[key]?.doubleValue ?? uniform ?? 0
        }
        let corners = [
            corner("rectangleTopLeftCornerRadius"), corner("rectangleTopRightCornerRadius"),
            corner("rectangleBottomRightCornerRadius"), corner("rectangleBottomLeftCornerRadius"),
        ]
        if record["rectangleCornerRadiiIndependent"]?.boolValue == true, Set(corners).count > 1 {
            return .perCorner(
                topLeft: .literal(corners[0]), topRight: .literal(corners[1]),
                bottomRight: .literal(corners[2]), bottomLeft: .literal(corners[3])
            )
        }
        let radius = uniform ?? corners[0]
        return radius > 0 ? .uniform(.literal(radius)) : nil
    }
}
