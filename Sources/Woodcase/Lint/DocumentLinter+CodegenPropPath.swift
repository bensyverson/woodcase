//
//  DocumentLinter+CodegenPropPath.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/codegenPropPath`` check: a `_props` entry `generate react` cannot
/// turn into a prop.
///
/// A reusable node declares its named parameters in `common.metadata._props`, as
/// `{"<prop name>": "<path of child names>"}` — the declaration the React emitter has
/// read since it shipped. ``ComponentAnalyzer`` resolves each path to the descendant it
/// names and hands the prop that node's id; a prop whose entry it cannot resolve is
/// emitted into the component's interface with **nothing wired to it**, and every
/// instance that overrides the descendant the author meant is inlined instead of
/// written as a tag. Nothing says so: an unresolved path is not an error anywhere in
/// the emitter, it is a `nil` that quietly propagates.
///
/// Two ways an entry fails on its own, one finding each:
///
/// - the value is not a string, so the analyzer skips the entry entirely and the prop
///   never exists at all;
/// - the value is a string that resolves to no descendant, so the prop exists and reads
///   nothing.
///
/// And one way two entries fail *together*: both resolve to the same descendant and both
/// read the same field of it. An override of that descendant carries one value, and
/// nothing says which prop the author meant it for, so the emitter keeps the first by
/// prop name and the rest are declared in the interface and never receive anything. This
/// is not the same as two props merely sharing a node — a `label` reading a text node's
/// content and a `tint` reading its fill are two readings of one node and both work — so
/// the check compares the type ``ComponentAnalyzer/inferPropType(from:)`` gives each,
/// not the node alone.
///
/// The path is resolved with ``ComponentAnalyzer/resolveDescendantPath(_:from:)``
/// itself, not with a second walk that agrees today — a path this check calls good is by
/// construction a path codegen wires.
extension DocumentLinter {
    /// Every `codegen-prop-path` finding for one row.
    ///
    /// - Parameters:
    ///   - row: The row to check. A row that is not a reusable node has no `_props` to
    ///     read: the emitter only looks at a component's own root.
    ///   - node: The row's node, resolved the way every other check reads it.
    ///   - context: The walk's shared state, for the materialized component subtree the
    ///     paths resolve against.
    /// - Returns: One finding per faulty entry in prop-name order, then one per group of
    ///   entries that are only faulty together, in the order of the prop each group
    ///   keeps.
    static func codegenPropPathFindings(
        _ row: TreeRow,
        node: PenNode,
        in context: Context
    ) -> [LintFinding] {
        guard node.common.reusable == true,
              let definition = context.components[row.id],
              let metadata = node.common.metadata,
              case let .dictionary(props) = metadata["_props"]
        else { return [] }

        return unresolvedFindings(props, row, definition)
            + ambiguousFindings(props, row, definition)
    }

    // MARK: - One entry at a time

    /// A finding for every entry that is not a path, or is a path naming nothing.
    private static func unresolvedFindings(
        _ props: [String: AnyCodable],
        _ row: TreeRow,
        _ definition: PenNode
    ) -> [LintFinding] {
        let component = name(of: row)
        return props.keys.sorted().compactMap { propName in
            guard let value = props[propName] else { return nil }
            guard case let .string(path) = value else {
                return finding(
                    .codegenPropPath, row,
                    "declares the prop `\(propName)` in common.metadata._props as \(shape(of: value)), but a "
                        + "prop is declared as the \"/\"-separated path of child names the prop reads — "
                        + "`generate react` skips an entry of any other shape, so \(component) never grows the "
                        + "prop at all. Run `woodcase set <file> \(row.id) "
                        + "common.metadata._props.\(propName)=\(suggestion(in: definition))` with the path to "
                        + "the descendant it should read."
                )
            }
            guard ComponentAnalyzer.resolveDescendantPath(path, from: definition) == nil else { return nil }
            return finding(
                .codegenPropPath, row,
                "declares the prop `\(propName)` in common.metadata._props as `\(path)`, but no descendant of "
                    + "\(component) answers to that path, so `generate react` emits the prop with nothing wired "
                    + "to it and inlines every instance that overrides the descendant it meant. It contains: "
                    + "\(descendantPaths(in: definition)). Run `woodcase set <file> \(row.id) "
                    + "common.metadata._props.\(propName)=<path>` with one of them."
            )
        }
    }

    // MARK: - Two entries at once

    /// A finding for every group of entries that resolve to one descendant *and* read
    /// the same field of it.
    ///
    /// Grouped by the descendant's id and the type the analyzer infers for it, because
    /// that pair is exactly what ``PropMapper`` reads: props sharing both share one value
    /// and only the first by name survives. A group of one is no finding — a lone prop on
    /// a node is the ordinary case.
    private static func ambiguousFindings(
        _ props: [String: AnyCodable],
        _ row: TreeRow,
        _ definition: PenNode
    ) -> [LintFinding] {
        var groups: [Ambiguity: [String]] = [:]
        for propName in props.keys.sorted() {
            guard case let .string(path) = props[propName],
                  let target = ComponentAnalyzer.resolveDescendantPath(path, from: definition)
            else { continue }
            let type = ComponentAnalyzer.inferPropType(from: target).type
            let key = Ambiguity(
                nodeID: target.id,
                nodeName: target.common.name ?? NodeAddress.marker(forID: target.id),
                type: type
            )
            groups[key, default: []].append(propName)
        }

        return groups
            .filter { $0.value.count > 1 }
            .sorted { ($0.value.first ?? "") < ($1.value.first ?? "") }
            .map { group, names in
                finding(.codegenPropPath, row, message(for: names, sharing: group, row, definition))
            }
    }

    /// The descendant-and-field a group of props all read: what makes them ambiguous.
    private struct Ambiguity: Hashable {
        /// The id of the descendant every prop in the group resolves to.
        let nodeID: String

        /// That descendant's name, for a sentence the reader can find in `tree`.
        let nodeName: String

        /// The type the analyzer infers for it, which is the field each prop reads.
        let type: PropType
    }

    /// What the finding says: which props collide, on what, and how to separate them.
    private static func message(
        for names: [String],
        sharing group: Ambiguity,
        _ row: TreeRow,
        _ definition: PenNode
    ) -> String {
        let kept = names[0]
        let dropped = Array(names.dropFirst())
        let one: Bool = dropped.count == 1
        let remedies = dropped.map { "common.metadata._props.\($0)=<path>" }
        return "declares the props \(and(names.map { "`\($0)`" })) in common.metadata._props as paths that "
            + "resolve to \(group.nodeName) (\(group.nodeID)), and each reads the same \(group.type.rawValue) "
            + "value from it, so `generate react` cannot tell them apart: it keeps `\(kept)` — the first by "
            + "name — and \(and(dropped.map { "`\($0)`" })) \(one ? "is" : "are") declared with "
            + "nothing wired to \(one ? "it" : "them"). Point \(one ? "it" : "them") at "
            + "\(one ? "another descendant" : "other descendants"): run `woodcase set <file> "
            + "\(row.id) \(remedies.joined(separator: " "))`. \(name(of: row)) contains: "
            + "\(descendantPaths(in: definition))."
    }

    /// A conjunctive list — "a", "a and b", "a, b and c".
    ///
    /// ``PenPropertyShape/list(_:)`` is the disjunctive one, for a message offering a
    /// reader a choice; these props are not alternatives, they all collided.
    private static func and(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + " and \(items[items.count - 1])"
        }
    }

    // MARK: - Naming the descendants

    /// The paths every descendant of a definition answers to, as a `_props` entry would
    /// spell them, with each node's id so the reader can find it in `tree`.
    ///
    /// Capped, because a component with forty descendants would otherwise print all
    /// forty into one sentence; the cap says how many it did not list rather than
    /// trailing off.
    private static func descendantPaths(in definition: PenNode) -> String {
        let paths = descendants(of: definition)
        guard !paths.isEmpty else { return "nothing — it has no children" }
        let listed = paths.prefix(descendantListLimit).map { "\($0.path) (\($0.id))" }
        let rest = paths.count - listed.count
        return listed.joined(separator: ", ") + (rest > 0 ? ", and \(rest) more" : "")
    }

    /// The path a remedy proposes when the entry named nothing usable at all: the first
    /// descendant, or a placeholder for a component that has none.
    private static func suggestion(in definition: PenNode) -> String {
        descendants(of: definition).first?.path ?? "<path>"
    }

    /// How many descendants a message lists before it counts the rest.
    private static let descendantListLimit = 8

    /// Every descendant of a definition, in document order, with the `_props` path it
    /// answers to.
    ///
    /// Walked with ``ComponentAnalyzer/childNodes(of:)``, the same step the path
    /// resolution takes, so this lists exactly the nodes a path can reach — a node
    /// with no name among them is skipped, because no path spells it.
    private static func descendants(of definition: PenNode) -> [(path: String, id: String)] {
        var found: [(path: String, id: String)] = []
        func walk(_ node: PenNode, prefix: String) {
            for child in ComponentAnalyzer.childNodes(of: node) {
                guard let name = child.common.name else { continue }
                let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
                found.append((path, child.id))
                walk(child, prefix: path)
            }
        }
        walk(definition, prefix: "")
        return found
    }

    /// What a non-string `_props` value is, for a sentence that says why it was skipped.
    private static func shape(of value: AnyCodable) -> String {
        switch value {
        case .int, .double: "a number"
        case .bool: "a boolean"
        case .array: "an array"
        case .dictionary: "an object"
        case .null: "null"
        case .string: "a string"
        }
    }
}
