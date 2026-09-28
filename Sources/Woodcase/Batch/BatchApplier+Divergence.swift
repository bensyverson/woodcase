//
//  BatchApplier+Divergence.swift
//  Woodcase
//

import Foundation

/// Where a write's requested form is compared with the form it will take.
///
/// Planning is the one place both halves exist at once: the operation as it was
/// written, and the document it is about to change. Every divergence a write can
/// report is decided here, so a single verb and a batch line say the same thing about
/// the same edit — ``BatchApplier/applyOne(_:to:recorder:)`` and
/// ``BatchApplier/apply(_:to:atomic:identity:recorder:)`` share one planner.
///
/// This file holds the divergences a write's own properties and overrides imply;
/// `BatchApplier+Divergence+Structural.swift` holds the ones the rest of the document
/// implies — a variable table it grew, a placement it chose, an instance it detached.
extension BatchApplier {
    // MARK: - Properties written to a node

    /// The divergences a `set`'s property map implies.
    ///
    /// - Parameters:
    ///   - properties: The properties as the caller wrote them, keyed by property path.
    ///   - node: The node they will be written to, as it stands.
    ///   - document: The document, for its variable table.
    /// - Returns: One divergence per property that will not be stored as written,
    ///   ordered by property path.
    static func propertyDivergences(
        _ properties: [String: AnyCodable],
        on node: PenNode,
        in document: EditableDocument
    ) -> [WriteDivergence] {
        properties.keys.sorted().compactMap { path in
            let value = properties[path] ?? .null
            let written = NodePropertyCodec.coercing(value, at: path, on: node.kind)
            if written != value {
                return coercion(at: path, requested: value, applied: written)
            }
            guard let field = NodePropertyCodec.fieldName(of: path),
                  NodePropertyCodec.stringFields.contains(field)
            else { return nil }
            return variableReference(at: path, value: written, in: document)
        }
    }

    /// The divergence a value that resolves as a variable implies, if any.
    ///
    /// `kind.content` accepts `string | $string`, so the literal `$v-muted` and a
    /// reference to the variable `v-muted` are typed identically on a command line —
    /// only the resolver's output tells them apart, and by then the difference is a
    /// wrong caption nobody flagged. A name no variable defines resolves to nothing, so
    /// there is no second reading to warn about and this stays quiet.
    ///
    /// - Parameters:
    ///   - target: The property path or raw key the value was written to.
    ///   - value: The value as it will be stored.
    ///   - document: The document, for its variable table.
    /// - Returns: The divergence, or `nil` when the value is not an unescaped `$name`
    ///   the document defines.
    static func variableReference(
        at target: String,
        value: AnyCodable,
        in document: EditableDocument
    ) -> WriteDivergence? {
        guard case let .string(raw) = value, raw.hasPrefix("$"), !raw.hasPrefix("\\$") else {
            return nil
        }
        let name = String(raw.dropFirst())
        guard let variable = document.variables?[name] else { return nil }
        let type = variable.type.rawValue
        return WriteDivergence(
            kind: .variableReference,
            target: target,
            requested: raw,
            applied: "the \(type) variable \(name)",
            note: "\(target) resolved \(raw) as a reference to the \(type) variable "
                + "\(name) — write \\$\(name) for the literal"
        )
    }

    /// The divergence a coerced value implies.
    ///
    /// - Parameters:
    ///   - path: The property path, or the raw override key, the value was written to.
    ///   - requested: The value as the caller wrote it.
    ///   - applied: The value as it will be stored.
    /// - Returns: The divergence.
    private static func coercion(
        at path: String,
        requested: AnyCodable,
        applied: AnyCodable
    ) -> WriteDivergence {
        let asked = spelling(of: requested)
        let stored = spelling(of: applied)
        return WriteDivergence(
            kind: .coercion,
            target: path,
            requested: asked,
            applied: stored,
            note: "\(path) stored the number \(asked) as the text \(stored) — "
                + "the property takes text, not a number"
        )
    }

    // MARK: - Overrides written to an instance

    /// The divergences an `override`'s property map implies.
    ///
    /// - Parameters:
    ///   - properties: The overrides as they will be stored, keyed as the `descendants`
    ///     map keys them.
    ///   - requested: The same keys carrying the values as the caller wrote them, before
    ///     coercion. The keys are already translated: a caller writing `kind.content`
    ///     asked for exactly what `content` stores, so the translation is not a
    ///     divergence and there is nothing to compare.
    ///   - descendantKey: The key inside the instance they are written under, or `nil`
    ///     for the instance's own root overrides — the component root's properties as
    ///     this instance shows them, which are judged against that root the same way.
    ///   - refID: The instance's `ref` node id.
    ///   - document: The document the override lands in.
    /// - Returns: One divergence per override that means something other than "replace
    ///   this value", ordered by key.
    static func overrideDivergences(
        _ properties: [String: AnyCodable],
        requested: [String: AnyCodable],
        descendantKey: String?,
        on refID: String,
        in document: EditableDocument
    ) -> [WriteDivergence] {
        let path = descendantKey.map { document.namePath(ofDescendant: $0, in: refID) }
            ?? document.namePath(of: refID)
        let target = descendantKey.map {
            document.patchedDefinitionNode(ofInstance: refID, descendantKey: $0)
        } ?? document.componentRoot(ofInstance: refID)
        guard let definition = target else {
            return []
        }
        let replacement = properties[PenDescendantOverride.typeKey] != nil
        return properties.keys.sorted().compactMap { key in
            if key == PenDescendantOverride.typeKey {
                return WriteDivergence(
                    kind: .overrideReplacesNode,
                    target: key,
                    requested: "an override of \(key)",
                    applied: "a replacement of the whole node",
                    note: "\(path) carries a type key, so the override replaces the whole "
                        + "node rather than patching it — every property the replacement "
                        + "omits is dropped"
                )
            }
            // A replacement is judged whole, not key by key: the keys it omits are the
            // point of it, so "the definition does not set this" says nothing useful.
            guard !replacement else { return nil }
            let applied = properties[key] ?? .null
            let asked = requested[key] ?? applied
            if applied != asked {
                return coercion(at: key, requested: asked, applied: applied)
            }
            if let resolved = variableReference(at: key, value: applied, in: document) {
                return resolved
            }
            if applied == .null {
                return nullOverride(key, at: path, definition: definition, in: document)
            }
            return unsetOverride(key, at: path, definition: definition, in: document)
        }
    }

    /// The divergence a null override implies.
    ///
    /// `key=null` stores a null; it does not remove the override. The two read the same
    /// back — a key that is there — and mean opposite things when the instance expands,
    /// so the write says which one happened, and only where it matters: where the
    /// definition *sets* the key the null takes that value away, which is destructive;
    /// where it sets nothing the null patches nothing, and a sentence about a no-op is
    /// noise. This is the inverse of ``unsetOverride(_:at:definition:in:)``, which is
    /// why the null case is decided before it.
    ///
    /// - Parameters:
    ///   - key: The raw .pen key being overridden.
    ///   - path: The overridden node's full name path, for the sentence.
    ///   - definition: The node inside the component the key patches.
    ///   - document: The document, for the component's name.
    /// - Returns: The divergence, or `nil` when the definition sets nothing there.
    private static func nullOverride(
        _ key: String,
        at path: String,
        definition: PenNode,
        in document: EditableDocument
    ) -> WriteDivergence? {
        guard let stored = NodePropertyCodec.storedKeys(of: definition), stored.contains(key)
        else { return nil }
        let component = document.componentName(holding: definition.id) ?? "the component"
        return WriteDivergence(
            kind: .nullOverride,
            target: key,
            requested: "an override of \(key) with null",
            applied: "\(key) cleared wherever this instance draws",
            note: "\(path) sets \(key) in \(component) — the null override clears it rather "
                + "than removing the override; unset \(key) instead to show the component's "
                + "value again"
        )
    }

    /// What an override of a key the definition does not already carry has to say.
    ///
    /// Three answers, in the order the key is judged. A key the node's type has no room
    /// for is a **divergence**: it is stored, and nothing will ever read it. A
    /// *structural* key — `children`, which fills a component's slot frame — says
    /// nothing at all, because "the definition does not set children" is true of every
    /// slot and is the point of one. Anything else is a **note**: the override adds a
    /// property rather than replacing a value, which is how an instance varies from its
    /// component, so it must not read as a warning.
    ///
    /// The type's room is ``NodePropertyCodec/rawKeys(acceptedBy:)``, which reads
    /// ``PenNodePatcher/structuralKeys(of:)`` for the second half of the answer — the
    /// check and the patcher cannot disagree about a key without one of them changing.
    ///
    /// - Parameters:
    ///   - key: The raw .pen key being overridden.
    ///   - path: The descendant's full name path, for the sentence.
    ///   - definition: The node inside the component the key patches.
    ///   - document: The document, for the component's name.
    /// - Returns: The divergence or note, or `nil` when there is nothing to say — the
    ///   definition sets the key already, or the key is structure.
    ///
    /// A node whose property surface Woodcase does not know is left alone: an
    /// ``PenNode/Kind/unknown(typeName:properties:)`` node has no schema to judge a key
    /// against, and a `ref`'s every non-reserved key is a root override that does apply.
    private static func unsetOverride(
        _ key: String,
        at path: String,
        definition: PenNode,
        in document: EditableDocument
    ) -> WriteDivergence? {
        switch definition.kind {
        case .unknown, .ref: return nil
        default: break
        }
        guard let stored = NodePropertyCodec.storedKeys(of: definition), !stored.contains(key)
        else { return nil }

        guard NodePropertyCodec.rawKeys(acceptedBy: definition).contains(key) else {
            return WriteDivergence(
                kind: .unsetOverrideProperty,
                target: key,
                requested: "an override of \(key)",
                applied: "a key nothing reads",
                note: "\(path) is a \(definition.kind.typeName) node and has no \(key) — "
                    + "the override is stored but nothing will read it"
            )
        }
        guard !PenNodePatcher.structuralKeys(of: definition).contains(key) else { return nil }

        let component = document.componentName(holding: definition.id) ?? "the component"
        return WriteDivergence(
            kind: .unsetOverrideProperty,
            severity: .note,
            target: key,
            requested: "an override of \(key)",
            applied: "a value added to \(path)",
            note: "\(path) adds \(key) rather than replacing it — \(component) does not "
                + "set \(key), which is how an instance varies from its component"
        )
    }

    // MARK: - Spelling

    /// How a JSON value reads in a sentence: a string in quotes, anything else bare.
    ///
    /// Shared with the document- and structure-level divergences in
    /// `BatchApplier+Divergence+Structural.swift`, which is why this cannot be
    /// `private` the way the rest of this file's helpers are.
    static func spelling(of value: AnyCodable) -> String {
        switch value {
        case let .string(text): "\"\(text)\""
        case let .int(number): String(number)
        case let .double(number): number.rounded() == number && abs(number) < 1e15
            ? String(Int64(number))
            : String(number)
        case let .bool(flag): String(flag)
        case .null: "null"
        default: "the value"
        }
    }
}
