//
//  DocumentLinter+StrokeDash.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/strokeDashIgnored`` check.
///
/// A node's `metadata.woodcase.strokeDash` is drawn only where every target can draw it
/// (``PenNode/strokeDash``): on one outline, which per-side bands are not, and as at most
/// sixteen non-negative lengths, not all zero. An edit refuses anything else; a file can
/// still hold it, written by hand or by another tool, and then the stroke draws solid on
/// every target. The finding says which, and how to make it draw.
extension DocumentLinter {
    /// A finding when a node's dash is drawn solid.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders.
    /// - Returns: At most one finding.
    static func strokeDashIgnored(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard let value = node.common.metadata?[woodcase: .strokeDash], value != .null,
              PenLayoutEngine.strokable(node)?.stroke != nil
        else { return [] }
        let key = PenMetadata.WoodcaseKey.strokeDash.propertyPath
        if let problem = PenStrokeDash.problem(in: value) {
            return [finding(
                .strokeDashIgnored, row,
                "has a \(key) that \(problem.reason), so its stroke draws solid. Write "
                    + "\(PenStrokeDash.writtenForm)."
            )]
        }
        guard node.hasPerSideStroke, PenStrokeDash.lengths(in: value)?.isEmpty == false else { return [] }
        return [finding(
            .strokeDashIgnored, row,
            "has a dash on a per-side strokeWidth, so its stroke draws solid: dashes flow round the whole "
                + "outline, which per-side bands are not. Write one strokeWidth, or remove \(key)."
        )]
    }
}
