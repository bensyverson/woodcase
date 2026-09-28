//
//  EditableDocument+VariableReferences.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Every defined variable something in the document mentions, and what mentions it.
    ///
    /// The walk re-encodes each node to JSON and collects every string leaf of the form
    /// `$name`. That is deliberately the *same* rule ``PenValue`` decodes by — any
    /// leading-`$` string is a variable reference — so this cannot disagree with the
    /// parser about what a reference is, and it sees properties no hand-written walk
    /// would have to be taught: a ref node's root overrides, a shader uniform, anything
    /// the format adds next. ``PenVariableResolver`` has its own per-kind traversal for
    /// *substituting* values; a second copy of it here would drift from that one the
    /// first time a property was added.
    ///
    /// Only names the document actually defines are reported. That is what keeps a text
    /// node whose content is the price `"$186"` — which the parser really does read as
    /// `.variable("186")` — out of the answer.
    ///
    /// - Returns: References keyed by variable name. A variable nothing mentions is
    ///   absent; ask ``references(to:)`` for it and get an empty answer.
    /// - Complexity: O(*n*) in the encoded size of the document.
    func variableReferences() -> [String: VariableReferences] {
        let defined = Set((variables ?? [:]).keys)
        guard !defined.isEmpty else { return [:] }

        var index: [String: VariableReferences] = [:]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for nodeID in nodeIDsInDocumentOrder() {
            guard let node = nodes[nodeID],
                  let data = try? encoder.encode(node),
                  let json = try? decoder.decode(AnyCodable.self, from: data)
            else { continue }
            var mentioned: Set<String> = []
            Self.collectReferences(in: json, into: &mentioned)
            for name in mentioned.intersection(defined).sorted() {
                index[name, default: VariableReferences()].nodeIDs.append(nodeID)
            }
        }

        for (owner, variable) in (variables ?? [:]).sorted(by: { $0.key < $1.key }) {
            var mentioned: Set<String> = []
            switch variable.value {
            case let .simple(value):
                Self.collectReferences(in: value, into: &mentioned)
            case let .themed(variants):
                for variant in variants {
                    Self.collectReferences(in: variant.value, into: &mentioned)
                }
            }
            for name in mentioned.intersection(defined).subtracting([owner]).sorted() {
                index[name, default: VariableReferences()].variableNames.append(owner)
            }
        }
        return index
    }

    /// Everything that mentions one variable.
    ///
    /// - Parameter name: The variable name, without the `$`.
    /// - Returns: The nodes and variables that reference it. Empty for a name nothing
    ///   mentions, and for one the document does not define.
    func references(to name: String) -> VariableReferences {
        variableReferences()[name] ?? VariableReferences()
    }

    // MARK: - Private

    /// Collects every `$name` string leaf reachable from a JSON value.
    ///
    /// Internal rather than private because ``NameInUse`` asks the same question of an
    /// import namespace — a `$V:--primary` is one of these leaves — and a second copy of
    /// the walk would drift from this one the first time the format grew a property.
    ///
    /// - Parameters:
    ///   - value: The value to walk.
    ///   - names: The names found so far, without the `$`.
    internal static func collectReferences(in value: AnyCodable, into names: inout Set<String>) {
        switch value {
        case let .string(text):
            guard text.hasPrefix("$"), text.count > 1 else { return }
            names.insert(String(text.dropFirst()))
        case let .array(items):
            for item in items {
                collectReferences(in: item, into: &names)
            }
        case let .dictionary(entries):
            for entry in entries.values {
                collectReferences(in: entry, into: &names)
            }
        case .null, .bool, .int, .double:
            break
        }
    }
}
