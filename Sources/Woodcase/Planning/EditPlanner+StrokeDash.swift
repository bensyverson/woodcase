//
//  EditPlanner+StrokeDash.swift
//  Woodcase
//

import Foundation

/// Holding a write to a stroke's dash to what every target can draw.
///
/// A dash is at most ``PenStrokeDash/maximumLengths`` non-negative lengths, not all zero,
/// and an offset is a number (``PenStrokeDash``). A dash never sits on a stroke of
/// per-side widths: dashes flow round the whole outline, and per-side bands are not one
/// outline (Ben's ruling, 2026-10-14). That is refused whichever half of the write brings
/// the two together — a dash on a per-side stroke, or per-side widths on a dashed one —
/// with the removal of the dash as the way out. An empty dash is solid, and allowed
/// anywhere. Only what the write changes is judged, as everywhere else: a file that
/// already holds one is told by lint (`stroke-dash-ignored`), not refused.
extension EditPlanner {
    /// Refuses a write that leaves a node with a dash no target can draw.
    ///
    /// - Parameters:
    ///   - props: The write, deep metadata keys already folded onto `common.metadata`.
    ///   - node: The node written, for the values it holds now.
    ///   - address: The address as written, for the refusal.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/invalidForm``,
    ///   ``EditRefusal/Code/outOfRange`` or ``EditRefusal/Code/dashOnPerSideStroke``.
    static func checkStrokeDash(_ props: [String: AnyCodable], on node: PenNode, address: String) throws {
        let current = node.common.metadata
        // A write that empties the metadata folds to `null`: the node then holds none.
        let written: PenMetadata? = switch props[NodePropertyCodec.metadataPath] {
        case let .dictionary(object)?: PenMetadata(object: object)
        case .null?: PenMetadata(object: [:])
        default: nil
        }
        let dashPath = PenMetadata.WoodcaseKey.strokeDash.propertyPath
        let offsetPath = PenMetadata.WoodcaseKey.strokeDashOffset.propertyPath

        if let offset = changed(.strokeDashOffset, in: written, from: current) {
            switch offset {
            case .int, .double: break
            default:
                throw EditRefusal(
                    code: .invalidForm, address: address, property: offsetPath, expected: "a number",
                    suggestion: "\(offsetPath)=2",
                    message: "\(address)'s \(offsetPath) must be a number of points, not \(PenPostIt.json(offset))."
                )
            }
        }

        let newDash = changed(.strokeDash, in: written, from: current)
        if let newDash, let problem = PenStrokeDash.problem(in: newDash) {
            throw EditRefusal(
                code: problem == .notNumbers ? .invalidForm : .outOfRange,
                address: address, property: dashPath, expected: PenStrokeDash.writtenForm,
                suggestion: "\(dashPath)=[8, 4]",
                message: "\(address)'s \(dashPath) \(PenPostIt.json(newDash)) \(problem.reason)."
            )
        }

        let widthWrite = props[strokeWidthPath]
        let perSide: Bool = if let widthWrite {
            if case .dictionary = widthWrite { true } else { false }
        } else {
            node.hasPerSideStroke
        }
        let dash = (written ?? current)?[woodcase: .strokeDash]
        guard perSide, newDash != nil || widthWrite != nil,
              let dash, let lengths = PenStrokeDash.lengths(in: dash), !lengths.isEmpty
        else { return }
        throw EditRefusal(
            code: .dashOnPerSideStroke,
            address: address,
            property: newDash != nil ? dashPath : strokeWidthPath,
            expected: "a uniform strokeWidth under a dash",
            suggestion: "\(dashPath)=null",
            message: "\(address) would have a dash on a stroke of per-side widths; dashes flow round the whole "
                + "outline, which per-side bands are not. Write one strokeWidth, or remove the dash."
        )
    }

    /// The codec path of a stroke's width.
    private static let strokeWidthPath = "kind.strokeWidth"

    /// The value the write gives `key`, when it writes one that differs from what the node
    /// holds; `nil` when it leaves the key as it was or removes it.
    private static func changed(
        _ key: PenMetadata.WoodcaseKey, in written: PenMetadata?, from current: PenMetadata?
    ) -> AnyCodable? {
        guard let written, let value = written[woodcase: key], value != .null, value != current?[woodcase: key]
        else { return nil }
        return value
    }
}
