//
//  DocumentLinter+PaintBlend.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/paintBlendLowest`` check.
///
/// A paint's blend mode blends only with the paints beneath it in its node's stack — fills,
/// then strokes — drawn as one isolated group (``PenPaintStack``; Ben's reading-1 ruling,
/// 2026-10-20). The lowest drawn paint has nothing beneath it, so its blend does nothing
/// here, while Pen blends it with whatever lies behind the node: Pen draws a lone blue fill
/// at multiply over red as black, Woodcase as blue. The fix moves the blend to the node,
/// whose own blend mode reaches the backdrop (``PenNode/blendMode``). For a node whose only
/// paint is the blended one, and which has no children, that is exactly Pen's look; above
/// other paints or under children, the node's blend applies to them too.
extension DocumentLinter {
    /// A finding when a node's lowest drawn paint blends.
    ///
    /// A row inside an instance is skipped: its paints are the component's, reported once on
    /// the component's own node.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders.
    /// - Returns: At most one finding.
    static func paintBlendLowest(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard !row.id.contains(NodeAddress.separator),
              let lowest = PenPaintStack(node).lowestBlend
        else { return [] }
        let paint = switch lowest.place {
        case let .fill(index): "fill \(index)"
        case let .stroke(index): "stroke paint \(index)"
        }
        let mode = lowest.mode.rawString
        let opening = "has a \(mode) blend on \(paint), its lowest paint, which blends with nothing beneath it in "
            + "the node's own paints, so Woodcase draws it as normal; Pen blends it with what lies behind the node."
        guard let fix = paintBlendFix(for: node) else {
            return [finding(
                .paintBlendLowest, row,
                opening + " The node has a blend mode of its own, so the paint's blend does nothing; remove it."
            )]
        }
        let assignments = fix.keys.sorted().map { key in "\(key)=\(commandValue(fix[key]!))" }
        return [finding(
            .paintBlendLowest, row,
            opening + " To draw it as Pen does, move the blend to the node: "
                + "`woodcase set <file> \(row.id) \(assignments.joined(separator: " "))`."
        )]
    }

    /// The writes that move a node's lowest paint's blend mode to the node: `kind.blendMode`
    /// set to the paint's mode, and the paint's list — `kind.fills` or `kind.stroke` — with
    /// that paint's blend removed.
    ///
    /// - Parameter node: The node.
    /// - Returns: The property writes, or `nil` when the lowest paint does not blend, the
    ///   node's type takes no blend mode, or the node already has a blend of its own.
    static func paintBlendFix(for node: PenNode) -> [String: AnyCodable]? {
        let stack = PenPaintStack(node)
        guard let lowest = stack.lowestBlend, node.takesBlendMode, node.blendMode?.blends != true else { return nil }
        let (path, paints, index): (String, PenFills?, Int) = switch lowest.place {
        case let .fill(index): ("kind.fills", PenRenderer.fills(for: node), index)
        case let .stroke(index): ("kind.stroke", PenRenderer.strokePaints(for: node), index)
        }
        let unblended: PenFills
        switch paints {
        case let .single(fill):
            unblended = .single(fill.withoutBlendMode)
        case var .multiple(fills):
            fills[index] = fills[index].withoutBlendMode
            unblended = .multiple(fills)
        case nil:
            return nil
        }
        guard
            let data = try? JSONEncoder().encode(unblended),
            let value = try? JSONDecoder().decode(AnyCodable.self, from: data)
        else { return nil }
        return ["kind.blendMode": .string(lowest.mode.rawString), path: value]
    }

    /// A value as a `set` command takes it: a bare string, or single-quoted compact JSON.
    private static func commandValue(_ value: AnyCodable) -> String {
        if case let .string(text) = value { return text }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else { return "…" }
        return "'\(json)'"
    }
}

private extension PenFill {
    /// The paint with no blend mode of its own.
    var withoutBlendMode: PenFill {
        switch self {
        case var .color(fill):
            fill.blendMode = nil
            return .color(fill)
        case var .gradient(fill):
            fill.blendMode = nil
            return .gradient(fill)
        case var .image(fill):
            fill.blendMode = nil
            return .image(fill)
        case var .meshGradient(fill):
            fill.blendMode = nil
            return .meshGradient(fill)
        case var .shader(fill):
            fill.blendMode = nil
            return .shader(fill)
        case .shorthand, .unknown:
            return self
        }
    }
}
