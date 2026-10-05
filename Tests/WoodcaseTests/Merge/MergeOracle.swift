//
//  MergeOracle.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Checks a merged document against the three-way rules key by key, independently of
/// how ``DocumentMerge`` reached it.
///
/// Every key — a node's own JSON key (a `ref`'s descendant overrides one per descendant
/// and key), its parent, a variable, an import alias, a theme axis, a root property —
/// is resolved the same way: changed on one side only takes that side; changed on both
/// to one value takes it; changed on both differently keeps ours, and a
/// ``MergeConflict`` must say so. Existence follows the same idea: ours' adds and
/// deletes stand, theirs' stand unless a conflict explains why not. Where a rule
/// leans on the merge's structural judgement — a node kept for a local edit, a parent
/// that did not survive — the oracle accepts the outcome only when a conflict names it.
@MainActor
struct MergeOracle {
    let base: EditableDocument
    let ours: EditableDocument
    let theirs: EditableDocument
    let merged: EditableDocument
    let result: MergeResult

    /// Every rule the merged document breaks, one line each.
    func violations() -> [String] {
        existence() + nodeKeys() + placement() + childOrder() + documentKeys()
    }

    // MARK: - The rule

    /// The value a key takes: theirs where only theirs changed it, else ours; contested
    /// when both changed it to different values.
    static func pick<Value: Equatable>(_ base: Value?, _ ours: Value?, _ theirs: Value?) -> (value: Value?, contested: Bool) {
        if ours == base { return (theirs, false) }
        if theirs == base || theirs == ours { return (ours, false) }
        return (ours, true)
    }

    /// Whether a conflict of one of `kinds` (any, when empty) has `subject`.
    func reported(_ subject: MergeConflict.Subject, _ kinds: Set<MergeConflict.Kind> = []) -> Bool {
        result.conflicts.contains { $0.subject == subject && (kinds.isEmpty || kinds.contains($0.kind)) }
    }

    /// Whether any conflict is about node `id` — a property, override, type, parent or
    /// its existence.
    func reportedAny(nodeID id: String) -> Bool {
        result.conflicts.contains { $0.subject.nodeID == id }
    }

    // MARK: - Existence

    private func existence() -> [String] {
        var out: [String] = []
        let ids = Set(base.nodes.keys).union(ours.nodes.keys).union(theirs.nodes.keys)
        for id in ids.sorted() {
            let (inBase, inOurs, inTheirs, inMerged) = (base.nodes[id] != nil, ours.nodes[id] != nil, theirs.nodes[id] != nil, merged.nodes[id] != nil)
            switch (inBase, inOurs, inTheirs) {
            case (_, true, true), (false, true, false):
                if !inMerged { out.append("\(id): ours holds it, the merge dropped it") }
            case (true, false, _):
                if inMerged { out.append("\(id): ours deleted it, the merge kept it") }
            case (false, false, true):
                let orphaned = ancestors(of: id, in: theirs).contains { reported(.existence(nodeID: $0), [.orphanedExternalInsert]) }
                if !inMerged, !orphaned { out.append("\(id): theirs added it, the merge dropped it unreported") }
            case (true, true, false):
                let kept: Set<MergeConflict.Kind> = [.editedLocallyDeletedExternally, .componentKeptForLocalInstance]
                // Kept for a local edit at or below it, or inside a component kept whole.
                let explained = merged.descendantIDs(of: id).contains { reported(.existence(nodeID: $0), kept) }
                    || ancestors(of: id, in: merged).contains { reported(.existence(nodeID: $0), [.componentKeptForLocalInstance]) }
                if inMerged, !explained { out.append("\(id): theirs deleted it, the merge kept it unreported") }
            case (false, false, false):
                break
            }
        }
        return out
    }

    /// `id` and every ancestor of it in `document`, nearest first.
    private func ancestors(of id: String, in document: EditableDocument) -> [String] {
        var chain = [id]
        while let parent = document.parents[chain.last!] {
            chain.append(parent)
        }
        return chain
    }

    // MARK: - Document keys

    private func documentKeys() -> [String] {
        var out: [String] = []
        func check(_ name: String, _ subject: MergeConflict.Subject, _ value: (EditableDocument) -> (some Equatable)?) {
            let (expected, contested) = Self.pick(value(base), value(ours), value(theirs))
            if value(merged) != expected { out.append("document \(name): expected \(String(describing: expected)), got \(String(describing: value(merged)))") }
            if contested, !reported(subject, [.bothChanged]) { out.append("document \(name): both changed it, unreported") }
        }
        for name in keys(\.variables) {
            check("variable \(name)", .variable(name)) { $0.variables?[name] }
        }
        for alias in keys(\.imports) {
            check("import \(alias)", .importAlias(alias)) { $0.imports?[alias] }
        }
        for axis in keys(\.themes) {
            check("theme axis \(axis)", .themeAxis(axis)) { $0.themes?[axis] }
        }
        for key in Set(base.extras.values.keys).union(ours.extras.values.keys).union(theirs.extras.values.keys) {
            check("extras.\(key)", .document(key: "extras.\(key)")) { $0.extras.values[key] }
        }
        check("fonts", .document(key: "fonts")) { $0.fonts }
        check("version", .document(key: "version")) { $0.version }
        check("fileToken", .document(key: "fileToken")) { $0.fileToken }
        // A table holding entries is declared whatever the sides said; only an empty one
        // shows the declaration.
        if merged.variables?.isEmpty ?? true { check("variables declared", .document(key: "variables")) { $0.variables != nil } }
        if merged.imports?.isEmpty ?? true { check("imports declared", .document(key: "imports")) { $0.imports != nil } }
        if merged.themes?.isEmpty ?? true { check("themes declared", .document(key: "themes")) { $0.themes != nil } }
        return out
    }

    /// Every key of one document table, across the three inputs.
    private func keys(_ table: KeyPath<EditableDocument, [String: some Any]?>) -> [String] {
        [base, ours, theirs].reduce(into: Set<String>()) { $0.formUnion(($1[keyPath: table] ?? [:]).keys) }.sorted()
    }
}

extension MergeConflict.Subject {
    /// The node the subject is about, if it is about one.
    var nodeID: String? {
        switch self {
        case let .property(id, _), let .descendantOverride(id, _, _), let .rootOverride(id, _),
             let .existence(id), let .parent(id), let .nodeType(id):
            id
        case .childOrder, .variable, .importAlias, .themeAxis, .document:
            nil
        }
    }
}
