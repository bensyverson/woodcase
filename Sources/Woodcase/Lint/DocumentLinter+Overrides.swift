//
//  DocumentLinter+Overrides.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/overrideValueRejected``, ``LintCheck/overrideTargetNotFound`` and
/// ``LintCheck/overrideKeyUnread`` checks.
///
/// Since d893dd0 the *write* path refuses an override a `ref`'s `descendants` map would
/// otherwise carry silently to its death: ``EditableDocument/validateOverrideValues(_:)``
/// judges a patch's value with ``PenNodePatcher/patched(_:with:)`` before it is stored,
/// and ``EditableDocument/validateOverrideTarget(_:)`` checks the key it is stored under
/// names a real descendant. Neither guard runs on a file that reaches Woodcase already
/// carrying the fault — an import, or a file Pen.app itself wrote — because there was no
/// write for it to refuse. ``PenNodePatcher/patchNode(_:with:)`` stays tolerant on
/// purpose at expansion time (see its doc comment): it answers a merge that will not
/// decode with the *unpatched* node, silently, rather than refusing to render the file.
/// These three checks are the read side of the same two guards, plus a third fault
/// neither guard catches: a property stored under a dotted path (`"kind.content"`)
/// instead of the raw .pen key (`"content"`) the merge reads, which decodes as a
/// harmless unknown key and is dropped with no error at all — a pre-d893dd0 `override`
/// wrote the path verbatim rather than rekeying it.
///
/// Like ``DocumentLinter/unresolvedVariables(_:node:)``, this reads a ref's own
/// `descendants` map rather than expanding the instance: a component is linted once,
/// where it is defined, and each of its refs — the ones at the document's own roots and
/// the ones nested inside another component's definition — is a row of its own, since
/// ``TreeView/rows(of:root:depth:expandInstances:theme:properties:)`` does not descend
/// past a `ref` unless asked to. That is also why `refID` here is always the row's own
/// id: a compound, prefixed id only appears when a caller asks the tree view to expand
/// instances, which ``DocumentLinter`` never does.
extension DocumentLinter {
    /// All three ref-override findings for one row.
    ///
    /// - Parameters:
    ///   - row: The row to check.
    ///   - node: The row's node, resolved the way ``unresolvedVariables(_:node:)`` reads
    ///     it — variables substituted, the `ref` itself left standing.
    ///   - context: The walk's shared state, for the document the override addresses.
    /// - Returns: The findings, one per faulty key across every `descendants` entry, in
    ///   key order.
    static func overrideFindings(_ row: TreeRow, node: PenNode, in context: Context) -> [LintFinding] {
        guard case let .ref(refData) = node.kind, let descendants = refData.descendants else { return [] }

        var found: [LintFinding] = []
        for descendantKey in descendants.keys.sorted() {
            guard let override = descendants[descendantKey] else { continue }
            found += unreadableKeyFindings(row, refID: row.id, descendantKey: descendantKey, override: override, in: context)
            found += targetFindings(row, refID: row.id, descendantKey: descendantKey, override: override, in: context)
            found += valueFindings(row, refID: row.id, descendantKey: descendantKey, override: override, in: context)
        }
        return found
    }

    // MARK: - override-value-rejected

    /// A patch value ``PenNodePatcher/patched(_:with:)`` cannot merge onto the
    /// descendant it targets.
    ///
    /// Exempt: an object replacement (a `type` key means there is no merge to fail),
    /// and a ref whose component is not in ``EditableDocument/componentRegistry`` — an
    /// unresolved import names no node this document can judge the value against, and
    /// is reported instead by ``brokenRef(_:node:in:)``. Each property key is judged on
    /// its own, so one bad key among several good ones does not hide the rest.
    private static func valueFindings(
        _ row: TreeRow,
        refID: String,
        descendantKey: String,
        override: PenDescendantOverride,
        in context: Context
    ) -> [LintFinding] {
        guard !override.isObjectReplacement,
              let definition = context.document.patchedDefinitionNode(
                  ofInstance: refID, descendantKey: descendantKey
              )
        else { return [] }

        var found: [LintFinding] = []
        for key in override.properties.keys.sorted() {
            let value = override.properties[key] ?? .null
            do {
                _ = try PenNodePatcher.patched(definition, with: [key: value])
            } catch {
                let field = NodePropertyCodec.fieldName(forRawKey: key)
                let expected = NodePropertyCodec.expectedShape(of: field)
                let actual = NodePropertyCodec.actualShape(of: value, field: field, failure: error)
                found.append(LintFinding(
                    check: .overrideValueRejected,
                    nodeID: row.id,
                    path: row.address,
                    message: "stores `\(key)` on \(context.document.namePath(ofDescendant: descendantKey, in: refID)) "
                        + "as an override, but it takes \(expected) and the stored value is \(actual). An override "
                        + "a node cannot take is dropped silently when the instance expands, so it never draws. "
                        + "Run `woodcase override <file> \(refID)\(NodeAddress.separator)\(descendantKey) "
                        + "\(key)=<value>` with one it can take."
                ))
            }
        }
        return found
    }

    // MARK: - override-target-not-found

    /// A `descendants` key naming no descendant the ref's component defines.
    ///
    /// Reuses ``EditableDocument/validateOverrideTarget(_:)`` itself — the exact
    /// judgment a write refuses on — rather than re-deriving which keys are valid.
    private static func targetFindings(
        _ row: TreeRow,
        refID: String,
        descendantKey: String,
        override: PenDescendantOverride,
        in context: Context
    ) -> [LintFinding] {
        let op = EditOperation.OverrideDescendant(
            refNodeID: refID, descendantID: descendantKey, properties: override.properties
        )
        do {
            try context.document.validateOverrideTarget(op)
            return []
        } catch let EditingError.overrideTargetNotFound(_, _, candidates) {
            return [LintFinding(
                check: .overrideTargetNotFound,
                nodeID: row.id,
                path: row.address,
                message: "stores an override keyed `\(descendantKey)`, but \(descendantKey) is not in the "
                    + "component \(name(of: row)) instantiates; the override is stored and never applies. It "
                    + "contains: \(BatchErrorMessage.list(candidates)). Run `woodcase override <file> "
                    + "\(refID)\(NodeAddress.separator)<name> key=value` to address one of them."
            )]
        } catch let EditingError.overrideOnOwnSlotContent(_, _, slotPath) {
            // The remedy is the address form, which Woodcase rewrites into the fill.
            let assignments = override.properties.keys.sorted().map { "\($0)=<value>" }.joined(separator: " ")
            return [LintFinding(
                check: .overrideTargetNotFound,
                nodeID: row.id,
                path: row.address,
                message: "stores an override keyed `\(descendantKey)`, but \(descendantKey) is a child this "
                    + "instance wrote into the slot \(slotPath) itself; Pen ignores such a key, draws the "
                    + "child as written and drops the key when it saves. Run `woodcase override <file> "
                    + "\(refID)\(NodeAddress.separator)\(descendantKey) \(assignments)`, which writes the change "
                    + "onto the child in the slot's children, where Pen reads it."
            )]
        } catch {
            return []
        }
    }

    // MARK: - override-key-unread

    /// A property keyed by a dotted path (`"kind.content"`) instead of the raw .pen
    /// name (`"content"`) the merge reads.
    ///
    /// This one decodes without error — an unrecognised JSON key is simply not part of
    /// any field the decoder reads back — so it is not something
    /// ``PenNodePatcher/patched(_:with:)`` can be asked to judge; catching it takes a
    /// direct look at the key itself. A .pen wire key is never a dotted path, only
    /// ``NodePropertyCodec``'s own `"common."`/`"kind."` path vocabulary is, so a key
    /// beginning with either prefix reached the file without going through
    /// ``NodePropertyCodec/rawKeyed(_:)``, which every write since d893dd0 does.
    private static func unreadableKeyFindings(
        _ row: TreeRow,
        refID: String,
        descendantKey: String,
        override: PenDescendantOverride,
        in context: Context
    ) -> [LintFinding] {
        override.properties.keys.sorted().compactMap { key in
            guard key.hasPrefix(NodePropertyCodec.commonPrefix) || key.hasPrefix(NodePropertyCodec.kindPrefix)
            else { return nil }
            let raw = NodePropertyCodec.rawKey(for: key)
            return LintFinding(
                check: .overrideKeyUnread,
                nodeID: row.id,
                path: row.address,
                message: "stores `\(key)` on \(context.document.namePath(ofDescendant: descendantKey, in: refID)) "
                    + "as an override, but a `descendants` map is keyed by the raw .pen name, not a property "
                    + "path — the merge does not read `\(key)` and silently drops it. Run `woodcase override "
                    + "<file> \(refID)\(NodeAddress.separator)\(descendantKey) \(raw)=<value>` to store it under "
                    + "the name the merge reads."
            )
        }
    }
}
