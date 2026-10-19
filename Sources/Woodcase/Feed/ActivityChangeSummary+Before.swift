//
//  ActivityChangeSummary+Before.swift
//  Woodcase
//

import Foundation

extension ActivityChangeSummary {
    /// Something a row can change that has one value at a time: a property, an override
    /// key, a variable, an import, a theme axis or a document property.
    enum Slot: Hashable {
        /// A node property, by node id and `common.*` / `kind.*` path.
        case property(node: String, key: String)
        /// An override key on an instance; a `nil` descendant is a root override.
        case override(ref: String, descendant: String?, key: String)
        /// A variable, by name.
        case variable(String)
        /// An import, by alias.
        case importAlias(String)
        /// A theme axis, by name.
        case themeAxis(String)
        /// A document-root property, by key.
        case document(String)
    }

    /// A value a slot held, where `nil` is *absent* rather than JSON `null`.
    ///
    /// A wrapper rather than a doubly optional dictionary value, because `AnyCodable` is
    /// `ExpressibleByNilLiteral`: a bare `nil` written into `[Slot: AnyCodable?]` can be
    /// inferred as ``AnyCodable/null`` and say "set to null" where "absent" was meant.
    struct Held: Hashable {
        /// The value, or `nil` for absent.
        var value: AnyCodable?

        /// Nothing held.
        static let absent = Held(value: AnyCodable?.none)
    }

    /// Where a node was in the tree before a row moved or removed it.
    struct Place: Hashable {
        /// The parent's id, or `nil` for the document root.
        var parent: String?
        /// The index among the parent's children.
        var index: Int?
    }

    /// Everything a row's inverse says about the state before the row.
    ///
    /// The inverse runs in order, so a later write to the same slot is the earlier
    /// state: the last write per slot wins, which is the value before the whole row.
    struct Before {
        /// Reads the inverse of a row.
        ///
        /// - Parameter inverse: The row's ``ActivityEvent/inverse``.
        init(_ inverse: [EditOperation]) {
            for operation in inverse {
                record(operation)
            }
        }

        /// The value each slot held before the row.
        var values: [Slot: Held] = [:]

        /// Whole common structs a pre-granular inverse restores, by node.
        var commons: [String: PenNodeCommon] = [:]

        /// Whole kinds a pre-granular inverse restores, by node.
        var kinds: [String: PenNode.Kind] = [:]

        /// Where moved nodes were, by node.
        var origins: [String: Place] = [:]

        /// Removed nodes, as the inverse re-inserts them, by node.
        var removed: [String: (node: PenNode, place: Place)] = [:]

        /// Replaced subtrees, as the inverse puts them back, by node.
        var replaced: [String: PenNode] = [:]

        /// The value a slot held before the row, or `nil` when the inverse does not say.
        ///
        /// A deep metadata key — `common.metadata.woodcase.spans` — is read out of the
        /// whole `common.metadata` object, because that is how an inverse restores it.
        func held(_ slot: Slot) -> Held? {
            if let held = values[slot] { return held }
            guard case let .property(node, key) = slot,
                  key.hasPrefix(Self.metadataPrefix),
                  let whole = values[.property(node: node, key: NodePropertyCodec.metadataPath)]
            else { return nil }
            let keyPath = key.dropFirst(Self.metadataPrefix.count).split(separator: ".").map(String.init)
            return Held(value: Self.dig(whole.value, keyPath))
        }

        // MARK: - Private

        private static let metadataPrefix = NodePropertyCodec.metadataPath + "."

        private mutating func record(_ operation: EditOperation) {
            switch operation {
            case let .setProperties(op):
                for (key, value) in op.properties {
                    values[.property(node: op.nodeID, key: key)] = Held(value: value)
                }
            case let .updateCommon(op):
                commons[op.nodeID] = op.common
            case let .updateKind(op):
                kinds[op.nodeID] = op.kind
            case let .overrideDescendant(op):
                recordOverride(ref: op.refNodeID, descendant: op.descendantID, op.properties, unset: op.unset)
            case let .overrideRoot(op):
                recordOverride(ref: op.refNodeID, descendant: nil, op.properties, unset: op.unset)
            case let .addVariable(op):
                values[.variable(op.name)] = Held(value: Self.encoded(op.variable.value))
            case let .updateVariable(op):
                values[.variable(op.name)] = Held(value: Self.encoded(op.variable.value))
            case let .removeVariable(op):
                values[.variable(op.name)] = Held.absent
            case let .addImport(op):
                values[.importAlias(op.alias)] = Held(value: .string(op.path))
            case let .updateImport(op):
                values[.importAlias(op.alias)] = Held(value: .string(op.path))
            case let .removeImport(op):
                values[.importAlias(op.alias)] = Held.absent
            case let .addThemeAxis(op):
                values[.themeAxis(op.name)] = Held(value: .array(op.options.map(AnyCodable.string)))
            case let .updateThemeAxis(op):
                values[.themeAxis(op.name)] = Held(value: .array(op.options.map(AnyCodable.string)))
            case let .removeThemeAxis(op):
                values[.themeAxis(op.name)] = Held.absent
            case let .setDocumentProperties(op):
                for (key, value) in op.properties {
                    values[.document(key)] = Held(value: value)
                }
            case let .moveNode(op):
                origins[op.nodeID] = Place(parent: op.newParentID, index: op.index)
            case let .insertNode(op):
                removed[op.node.id] = (op.node, Place(parent: op.parentID, index: op.index))
            case let .replaceSubtree(op):
                replaced[op.node.id] = op.node
            case .deleteNode, .detachRef:
                break
            }
        }

        private mutating func recordOverride(
            ref: String, descendant: String?, _ properties: [String: AnyCodable], unset: [String]
        ) {
            for (key, value) in properties {
                values[.override(ref: ref, descendant: descendant, key: key)] = Held(value: value)
            }
            for key in unset {
                values[.override(ref: ref, descendant: descendant, key: key)] = Held.absent
            }
        }

        /// A value as JSON, or `nil` when it cannot be encoded.
        static func encoded(_ value: some Encodable) -> AnyCodable? {
            try? NodePropertyCodec.encode(value)
        }

        /// The value at a key path inside an object, or `nil` when the path leads nowhere.
        private static func dig(_ value: AnyCodable?, _ keyPath: [String]) -> AnyCodable? {
            guard let first = keyPath.first else { return value }
            guard case let .dictionary(object) = value else { return nil }
            return dig(object[first], Array(keyPath.dropFirst()))
        }
    }
}
