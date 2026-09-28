//
//  DocumentLinter+Icons.swift
//  Woodcase
//

import Foundation

/// The `unknown-icon` and `unknown-icon-library` checks.
///
/// Kept apart from `DocumentLinter.swift` so adding a check here never touches the
/// checks already running there — see ``DocumentLinter/findings(in:root:theme:diagnostics:)``
/// for where ``iconFindings(_:node:)`` is called from the per-row walk.
extension DocumentLinter {
    /// An `icon` node whose library or icon name lint cannot resolve.
    ///
    /// Both checks are offline, reading only ``PenIconFontRegistry``'s bundled and
    /// registered tables — the same ones `woodcase icons` lists and the renderer
    /// resolves against. A library this registry does not know reports
    /// ``LintCheck/unknownIconLibrary`` and stops there, since there is no table to
    /// check the icon name against. A known library with no entry for the icon name
    /// reports ``LintCheck/unknownIcon``, proposing up to five names
    /// ``IconNameMatcher`` ranks nearest.
    ///
    /// - Parameters:
    ///   - row: The row the node renders at, for the finding's id and path.
    ///   - node: The node as it renders — see `Context.resolved(_:)`.
    /// - Returns: Zero or one finding; an icon with no `library`, no `icon` name, or a
    ///   name the registry resolves is clean.
    static func iconFindings(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard case let .icon(data) = node.kind,
              let library = data.library?.literalValue,
              let iconName = data.icon?.literalValue, !iconName.isEmpty
        else { return [] }

        let registry = PenIconFontRegistry.shared
        guard let names = registry.names(in: library) else {
            let libraries = registry.libraries.joined(separator: ", ")
            return [LintFinding(
                check: .unknownIconLibrary,
                nodeID: row.id,
                path: row.address,
                message: "uses icon library `\(library)`, which is not one of the bundled or "
                    + "registered families: \(libraries)."
            )]
        }

        guard registry.resolve(family: library, name: iconName) == nil else { return [] }

        let proposals = IconNameMatcher.matches(names, query: iconName, limit: 5)
        let remedy = proposals.isEmpty
            ? "No similar name was found in `\(library)`."
            : "Did you mean \(proposals.joined(separator: ", "))? "
            + "(`set kind.icon=\(proposals[0])`)"
        return [LintFinding(
            check: .unknownIcon,
            nodeID: row.id,
            path: row.address,
            message: "uses icon `\(iconName)` from library `\(library)`, which has no icon of "
                + "that name. \(remedy)"
        )]
    }
}
