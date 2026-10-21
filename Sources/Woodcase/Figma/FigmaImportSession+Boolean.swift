//
//  FigmaImportSession+Boolean.swift
//  Woodcase
//

import CoreGraphics
import Foundation

extension FigmaImportSession {
    /// A boolean operation as the one Pen path it draws, reported as flattened.
    ///
    /// The clipboard carries no geometry for a boolean, only its operands, so the result is
    /// computed here with Core Graphics' set operations: each operand's outline, placed by
    /// its transform in the boolean's coordinates, combined bottom operand first — union,
    /// the bottom one less the rest, intersection, or exclusion. A result fills the same
    /// under either rule. An operand with no outline (text, a frame) is left out, reported.
    mutating func boolean(_ record: KiwiRecord, guid: FigmaGUID, common: inout PenNodeCommon) throws(FigmaImportError) -> PenNode.Kind {
        let size = size(of: record)
        let graphics = graphics(of: record, common: &common)
        let operation = record["booleanOperation"]?.enumName ?? "UNION"
        report(.booleanOperation, .flattened, on: record, detail: operation)
        var outlines: [CGPath] = []
        for operand in tree.children[guid] ?? [] {
            guard let path = try outline(of: operand) else {
                if let operandRecord = tree.records[operand] {
                    report(.booleanOperand, .dropped, on: record, detail: operandRecord["name"]?.stringValue ?? operand.penID)
                }
                continue
            }
            outlines.append(path)
        }
        let result = Self.combine(outlines, operation: operation)
        return .path(PenNode.PathData(
            width: .fixed(size.width), height: .fixed(size.height),
            geometry: Self.svgPathData(Self.commands(of: result)),
            viewBox: PenViewBox(x: 0, y: 0, width: size.width, height: size.height),
            fills: graphics.fills, stroke: graphics.stroke, strokeWidth: graphics.strokeWidth,
            strokeLinecap: graphics.strokeLinecap, strokeLinejoin: graphics.strokeLinejoin,
            strokeAlignment: graphics.strokeAlignment, effects: graphics.effects
        ))
    }

    /// An operand's outline in its parent's coordinates, normalized to its own fill rule,
    /// or `nil` for a node with no outline. Its own losses are not the clip's: it does not
    /// survive as a node.
    private func outline(of operand: FigmaGUID) throws(FigmaImportError) -> CGPath? {
        guard let record = tree.records[operand] else { return nil }
        var scratch = self
        let node = try scratch.node(operand)
        let size = size(of: record)
        guard let shape = PenShapeGeometry.outline(for: node, rect: PenRect(x: 0, y: 0, width: size.width, height: size.height))
        else { return nil }
        let transform = FigmaTransform(record["transform"]) ?? .identity
        var placement = CGAffineTransform(
            a: transform.m00, b: transform.m10, c: transform.m01, d: transform.m11, tx: transform.m02, ty: transform.m12
        )
        let rule: CGPathFillRule = PenShapeGeometry.fillRule(for: node) == .evenodd ? .evenOdd : .winding
        guard let placed = shape.cgPath.copy(using: &placement) else { return nil }
        return placed.normalized(using: rule)
    }

    /// The operands combined by Figma's `BooleanOperation` case `operation`.
    static func combine(_ outlines: [CGPath], operation: String) -> CGPath {
        guard var result = outlines.first else { return CGMutablePath() }
        let rest = outlines.dropFirst()
        switch operation {
        case "SUBTRACT":
            for other in rest {
                result = result.subtracting(other)
            }
        case "INTERSECT":
            for other in rest {
                result = result.intersection(other)
            }
        case "XOR":
            for other in rest {
                result = result.symmetricDifference(other)
            }
        default:
            for other in rest {
                result = result.union(other)
            }
        }
        return result
    }

    /// A Core Graphics path's elements as path commands.
    static func commands(of path: CGPath) -> [FigmaPathCommand] {
        var commands: [FigmaPathCommand] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            func point(_ index: Int) -> FigmaPoint {
                FigmaPoint(x: Double(element.points[index].x), y: Double(element.points[index].y))
            }
            switch element.type {
            case .moveToPoint: commands.append(.move(to: point(0)))
            case .addLineToPoint: commands.append(.line(to: point(0)))
            case .addQuadCurveToPoint: commands.append(.quadratic(control: point(0), to: point(1)))
            case .addCurveToPoint: commands.append(.cubic(control1: point(0), control2: point(1), to: point(2)))
            case .closeSubpath: commands.append(.close)
            @unknown default: break
            }
        }
        return commands
    }
}
