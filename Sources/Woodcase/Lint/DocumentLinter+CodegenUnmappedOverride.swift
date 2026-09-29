//
//  DocumentLinter+CodegenUnmappedOverride.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/codegenUnmappedOverride`` check: an instance whose overrides no
/// declared prop reads.
///
/// `ReactEmitter` writes `<Card title="…" />` for an instance whose every `descendants`
/// key matches a prop's target node — that is what ``PropMapper`` is for. One key it
/// cannot match changes the whole strategy: the emitter *inlines* the component, cloning
/// the definition, patching the overrides onto the clone and emitting the expanded tree
/// in place of the tag, with a `codeGen` diagnostic (an error under `--strict`). The
/// pixels are right; the code is not. The component's reuse is gone at that call site,
/// and a design with a dozen such instances generates a dozen copies of one component.
///
/// **A definition that declares no `_props` is never a finding.** Nothing was declared,
/// so nothing failed to map, and a component nobody has parameterized yet is a normal
/// stage of a design rather than a fault — reporting it would fire the check at every
/// instance of every plain component in the file.
///
/// **A key naming no descendant at all is not this finding either.** That is
/// ``LintCheck/overrideTargetNotFound``, which says the more specific thing and proposes
/// the more useful fix; reporting both would be one fault twice.
///
/// What is left divides in two, and the message says which one it is holding:
///
/// - a **named** descendant the definition never declared, which one `_props` entry
///   fixes — so the message hands that entry over, prop name and path and all;
/// - an **unnamed** one, which no `_props` entry can reach at all, because a path is a
///   run of child *names* (see ``ComponentAnalyzer/resolveDescendantPath(_:from:)``).
///   That instance inlines until the descendant is given a name, so the message asks for
///   the name first and the declaration second. It is the common case in a file drawn in
///   an editor rather than written by hand, where a wrapper frame is left unnamed.
///
/// Both remedies use the deep metadata key — `common.metadata._props.<name>=<path>` —
/// which merges one key rather than overwriting the object and dropping `_role` or
/// `_scroll` with it.
///
/// The check reads the ref's own `descendants` map, like the three override checks and
/// `unresolved-variable`, rather than expanding the instance.
extension DocumentLinter {
    /// The `codegen-unmapped-override` finding for one row, if it has one.
    ///
    /// - Parameters:
    ///   - row: The row to check. Only a `ref` has overrides to be unmapped.
    ///   - node: The row's node, resolved the way every other check reads it.
    ///   - context: The walk's shared state, for the definition the ref names.
    /// - Returns: One finding naming every unmapped key, or none.
    static func codegenUnmappedOverrideFindings(
        _ row: TreeRow,
        node: PenNode,
        in context: Context
    ) -> [LintFinding] {
        guard case let .ref(refData) = node.kind,
              let descendants = refData.descendants, !descendants.isEmpty,
              let definition = context.components[refData.ref],
              let metadata = definition.common.metadata,
              case let .dictionary(props) = metadata["_props"], !props.isEmpty
        else { return [] }

        let declared = Set(props.values.compactMap { value -> String? in
            guard case let .string(path) = value else { return nil }
            return ComponentAnalyzer.resolveDescendantPath(path, from: definition)?.id
        })
        let inside = descendantsByID(of: definition)
        let unmapped = descendants.keys.sorted().compactMap { key -> (key: String, node: Descendant)? in
            guard !declared.contains(key), let found = inside[key] else { return nil }
            return (key, found)
        }
        guard !unmapped.isEmpty else { return [] }

        return [finding(.codegenUnmappedOverride, row, message(for: unmapped, of: definition))]
    }

    // MARK: - The sentence

    /// What the finding says: which keys forced the inline, and the edit that would
    /// stop it for each.
    private static func message(
        for unmapped: [(key: String, node: Descendant)],
        of definition: PenNode
    ) -> String {
        let component = definition.common.name ?? NodeAddress.marker(forID: definition.id)
        let named = unmapped.map { entry in
            entry.node.path.map { "`\(entry.key)` (\($0))" } ?? "`\(entry.key)`"
        }
        let reads: String = unmapped.count == 1 ? "reads that descendant" : "read those descendants"
        var sentence = "overrides \(PenPropertyShape.list(named)) on \(component), which declares props in "
            + "common.metadata._props but none that \(reads), so `generate react` inlines a whole copy of "
            + "\(component) here instead of emitting a `<\(component) />` tag."

        let declarable: [String] = unmapped.compactMap { entry in
            guard let path = entry.node.path else { return nil }
            let prop: String = propName(for: entry.node.name ?? entry.key)
            return "common.metadata._props.\(prop)=\(path)"
        }
        if !declarable.isEmpty {
            sentence += " Declare \(declarable.count == 1 ? "it" : "them"): run `woodcase set <file> "
                + "\(definition.id) \(declarable.joined(separator: " "))`."
        }

        let anonymous = unmapped.filter { $0.node.path == nil }
        if !anonymous.isEmpty {
            let one: Bool = anonymous.count == 1
            let keys: [String] = anonymous.map { "`\($0.key)`" }
            let commands: [String] = anonymous.map { "`woodcase set <file> \($0.key) common.name=<name>`" }
            let subject: String = PenPropertyShape.list(keys)
            let runs: String = PenPropertyShape.list(commands)
            sentence += " \(subject) \(one ? "has" : "have") no name, and a _props path is a run of child "
                + "names, so no entry can reach \(one ? "it" : "them") until \(one ? "it is" : "they are") "
                + "named: run \(runs), then declare the prop the same way."
        }
        return sentence
    }

    // MARK: - Reading the definition

    /// One descendant of a definition: the name it carries, and the `_props` path that
    /// reaches it — `nil` when it, or an ancestor inside the component, has no name.
    struct Descendant: Friendly {
        /// The node's own name, or `nil` when it has none.
        let name: String?

        /// The `/`-separated path a `_props` entry would spell, or `nil` when no path
        /// can name it.
        let path: String?
    }

    /// Every descendant of a definition by id, with the `_props` path it answers to.
    ///
    /// Walked with ``ComponentAnalyzer/childNodes(of:)`` so the paths here are the ones
    /// ``ComponentAnalyzer/resolveDescendantPath(_:from:)`` resolves: a remedy this
    /// check prints is a path the emitter reads back. A node with no name — or under
    /// one with no name — is present with a `nil` path rather than absent, because it is
    /// still a real descendant an instance can override and the emitter still inlines
    /// for it; it is the *remedy* that differs, not whether there is a finding.
    private static func descendantsByID(of definition: PenNode) -> [String: Descendant] {
        var found: [String: Descendant] = [:]
        func walk(_ node: PenNode, prefix: String?) {
            for child in ComponentAnalyzer.childNodes(of: node) {
                let name = child.common.name
                let path: String? = if let prefix, let name {
                    prefix.isEmpty ? name : "\(prefix)/\(name)"
                } else {
                    nil
                }
                found[child.id] = Descendant(name: name, path: path)
                walk(child, prefix: path)
            }
        }
        walk(definition, prefix: "")
        return found
    }

    /// A prop name proposed from a descendant's name: `"Icon Label"` → `"iconLabel"`.
    ///
    /// A suggestion, not a rule — the author renames it freely. It is camelCase because
    /// the emitted prop becomes a TSX attribute, and a name with a space in it is not
    /// one a caller could type.
    private static func propName(for nodeName: String) -> String {
        let words = nodeName.split { !$0.isLetter && !$0.isNumber }
        guard let first = words.first else { return "prop" }
        let rest = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return first.prefix(1).lowercased() + first.dropFirst() + rest.joined()
    }
}
