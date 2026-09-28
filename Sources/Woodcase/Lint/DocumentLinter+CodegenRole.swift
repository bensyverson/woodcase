//
//  DocumentLinter+CodegenRole.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/codegenRole`` check: a `common.metadata._role` value
/// `generate react` does not know.
///
/// ``ComponentRole`` is a closed vocabulary — `button`, `link`, `toggle`, `textInput`,
/// `select`, `tabBar` — and ``ComponentAnalyzer`` reads `_role` in two places, both
/// inside a reusable node: on the component's own root, where `ComponentRole(rawValue:)`
/// answers `nil` for anything else and the component simply has no role; and on every
/// descendant, where an unknown role produces no default action and no binding. Either
/// way the declaration is read and thrown away without a word, and the component emits
/// as a plain `<div>` with no semantic element, no `wc-*` class and no state rules.
///
/// **Scope is exactly what codegen reads.** A `_role` on a page, or on any node outside
/// every reusable subtree, is not a finding: `walkDescendants` is only ever entered from
/// a component definition, so nothing there reaches the emitter and reporting it would
/// be the check firing at a key the file is free to use for its own purposes.
///
/// The finding lands on the offending node's own row, so its path and id are the ones
/// `tree` prints and a `set` accepts. A definition outside the lint's scope contributes
/// no rows and therefore no findings, the same way every scoped check behaves.
extension DocumentLinter {
    /// Every `codegen-role` finding in the document, keyed by the id of the row it is
    /// reported against.
    ///
    /// - Parameters:
    ///   - rows: The listing being linted, which is both the set of definitions in
    ///     scope and the source of each finding's address.
    ///   - context: The walk's shared state, for the materialized component subtrees.
    /// - Returns: Row id → its findings. A row with none is absent.
    static func codegenRoleFindings(rows: [TreeRow], in context: Context) -> [String: [LintFinding]] {
        var rowByID: [String: TreeRow] = [:]
        for row in rows where rowByID[row.id] == nil {
            rowByID[row.id] = row
        }

        var found: [String: [LintFinding]] = [:]
        for row in rows {
            guard let definition = context.components[row.id] else { continue }
            for (nodeID, role) in unknownRoles(in: definition) {
                guard let target = rowByID[nodeID] else { continue }
                let consequence = nodeID == definition.id
                    ? "the component emits a plain <div>, with no semantic element, no interactive states "
                    + "and no state rules"
                    : "no action and no binding are generated for it"
                found[nodeID, default: []].append(finding(
                    .codegenRole, target,
                    "declares common.metadata._role=\"\(role)\", which is not a role `generate react` knows, "
                        + "so the declaration is read and dropped: \(consequence). The roles are "
                        + "\(PenPropertyShape.list(ComponentRole.allCases.map(\.rawValue))). Run `woodcase set "
                        + "<file> \(target.id) common.metadata._role=<role>` with one of them, or drop the key."
                ))
            }
        }
        return found
    }

    /// Every `_role` in a definition's subtree — its own root included — that
    /// ``ComponentRole`` does not spell, in document order.
    ///
    /// Walked with ``ComponentAnalyzer/childNodes(of:)``, the step the analyzer's own
    /// `walkDescendants` takes, so this reaches exactly the nodes whose `_role` codegen
    /// reads and no others.
    private static func unknownRoles(in definition: PenNode) -> [(id: String, role: String)] {
        var found: [(id: String, role: String)] = []
        func walk(_ node: PenNode) {
            if let metadata = node.common.metadata,
               case let .string(role) = metadata["_role"],
               ComponentRole(rawValue: role) == nil
            {
                found.append((node.id, role))
            }
            for child in ComponentAnalyzer.childNodes(of: node) {
                walk(child)
            }
        }
        walk(definition)
        return found
    }
}
