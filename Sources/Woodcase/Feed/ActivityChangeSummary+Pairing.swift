//
//  ActivityChangeSummary+Pairing.swift
//  Woodcase
//

import Foundation

extension ActivityChangeSummary {
    /// Walks a row's forward operations against what its inverse says came before, and
    /// produces the row's changes in the order the writer made them.
    struct Pairing {
        /// Pairs one row.
        ///
        /// - Parameter event: The activity row.
        init(_ event: ActivityEvent) {
            self.event = event
            before = Before(event.inverse)
            for (node, path) in zip(event.nodes, event.paths) where paths[node] == nil {
                paths[node] = path
            }
        }

        /// The row's changes; never empty, so every row has at least one line.
        mutating func changes() -> [Change] {
            for operation in event.forward {
                pair(operation)
            }
            let changes = entries.compactMap(change(for:))
            return changes.isEmpty ? [fallback] : changes
        }

        // MARK: - Private

        /// One change in order: a slot whose final value is read at the end, or a
        /// structural change that is complete as it is.
        private enum Entry {
            case slot(Slot)
            case made(Change)
        }

        private let event: ActivityEvent
        private let before: Before
        private var paths: [String: String] = [:]
        private var entries: [Entry] = []
        private var after: [Slot: Held] = [:]
        private var kinds: [Slot: ActivityEvent.Kind] = [:]

        private mutating func pair(_ operation: EditOperation) {
            let kind = ActivityEvent.Kind(operation)
            switch operation {
            case let .setProperties(op):
                for key in op.properties.keys.sorted() {
                    write(.property(node: op.nodeID, key: key), op.properties[key], kind: kind)
                }
            case let .updateCommon(op):
                for key in commonKeys(of: op) {
                    let value = try? NodePropertyCodec.commonValue(
                        at: key, of: op.common, nodeID: op.nodeID, nodeType: ""
                    )
                    write(.property(node: op.nodeID, key: key), value, kind: kind)
                }
            case let .updateKind(op):
                pairKind(op, kind: kind)
            case let .overrideDescendant(op):
                writeOverride(op.refNodeID, op.descendantID, op.properties, unset: op.unset, kind: kind)
            case let .overrideRoot(op):
                writeOverride(op.refNodeID, nil, op.properties, unset: op.unset, kind: kind)
            case let .addVariable(op):
                write(.variable(op.name), Before.encoded(op.variable.value), kind: kind)
            case let .updateVariable(op):
                write(.variable(op.name), Before.encoded(op.variable.value), kind: kind)
            case let .removeVariable(op):
                write(.variable(op.name), nil, kind: kind)
            case let .addImport(op):
                write(.importAlias(op.alias), .string(op.path), kind: kind)
            case let .updateImport(op):
                write(.importAlias(op.alias), .string(op.path), kind: kind)
            case let .removeImport(op):
                write(.importAlias(op.alias), nil, kind: kind)
            case let .addThemeAxis(op):
                write(.themeAxis(op.name), .array(op.options.map(AnyCodable.string)), kind: kind)
            case let .updateThemeAxis(op):
                write(.themeAxis(op.name), .array(op.options.map(AnyCodable.string)), kind: kind)
            case let .removeThemeAxis(op):
                write(.themeAxis(op.name), nil, kind: kind)
            case let .setDocumentProperties(op):
                for key in op.properties.keys.sorted() {
                    write(.document(key), op.properties[key], kind: kind)
                }
            default:
                pairStructure(operation, kind: kind)
            }
        }

        private mutating func pairStructure(_ operation: EditOperation, kind: ActivityEvent.Kind) {
            switch operation {
            case let .insertNode(op):
                entries.append(.made(Change(
                    kind: kind, node: op.node.id, path: paths[op.node.id],
                    new: Before.encoded(op.node), parent: name(of: op.parentID), index: op.index
                )))
            case let .deleteNode(op):
                let removed = before.removed[op.nodeID]
                entries.append(.made(Change(
                    kind: kind, node: op.nodeID, path: paths[op.nodeID],
                    old: removed.flatMap { Before.encoded($0.node) },
                    parent: name(of: removed?.place.parent), index: removed?.place.index
                )))
            case let .moveNode(op):
                let origin = before.origins[op.nodeID]
                entries.append(.made(Change(
                    kind: kind, node: op.nodeID, path: paths[op.nodeID],
                    old: origin.map { placeValue(parent: $0.parent, index: $0.index) },
                    new: placeValue(parent: op.newParentID, index: op.index),
                    parent: name(of: op.newParentID), index: op.index
                )))
            case let .replaceSubtree(op):
                entries.append(.made(Change(
                    kind: kind, node: op.node.id, path: paths[op.node.id],
                    old: before.replaced[op.node.id].flatMap { Before.encoded($0) },
                    new: Before.encoded(op.node)
                )))
            case let .detachRef(op):
                entries.append(.made(Change(kind: kind, node: op.refNodeID, path: paths[op.refNodeID])))
            default:
                break
            }
        }

        /// The `common.*` keys a whole-struct update changed: diffed against a whole
        /// inverse when the row has one, else the keys its granular inverse restores.
        private func commonKeys(of op: EditOperation.UpdateCommon) -> [String] {
            if let old = before.commons[op.nodeID] {
                return PropertyDiff.diffCommon(old: old, new: op.common).sorted()
            }
            return restoredKeys(of: op.nodeID, prefix: "common.")
        }

        private mutating func pairKind(_ op: EditOperation.UpdateKind, kind: ActivityEvent.Kind) {
            let keys: [String]
            if let old = before.kinds[op.nodeID] {
                guard old.typeName == op.kind.typeName else {
                    entries.append(.made(Change(
                        kind: kind, node: op.nodeID, path: paths[op.nodeID], key: Self.typeKey,
                        old: .string(old.typeName), new: .string(op.kind.typeName)
                    )))
                    return
                }
                keys = PropertyDiff.diffKind(old: old, new: op.kind).sorted()
            } else {
                keys = restoredKeys(of: op.nodeID, prefix: "kind.")
            }
            for key in keys {
                let value = try? NodePropertyCodec.kindValue(at: key, of: op.kind, nodeID: op.nodeID)
                write(.property(node: op.nodeID, key: key), value, kind: kind)
            }
        }

        /// The path a change of node type is reported under.
        private static let typeKey = "kind.type"

        private func restoredKeys(of node: String, prefix: String) -> [String] {
            before.values.keys.compactMap { slot -> String? in
                guard case let .property(id, key) = slot, id == node, key.hasPrefix(prefix) else { return nil }
                return key
            }.sorted()
        }

        private mutating func writeOverride(
            _ ref: String, _ descendant: String?, _ properties: [String: AnyCodable], unset: [String],
            kind: ActivityEvent.Kind
        ) {
            for key in properties.keys.sorted() {
                write(.override(ref: ref, descendant: descendant, key: key), properties[key], kind: kind)
            }
            for key in unset.sorted() {
                write(.override(ref: ref, descendant: descendant, key: key), nil, kind: kind)
            }
        }

        private mutating func write(_ slot: Slot, _ value: AnyCodable?, kind: ActivityEvent.Kind) {
            if after[slot] == nil {
                entries.append(.slot(slot))
            }
            after[slot] = Held(value: value)
            kinds[slot] = kind
        }

        /// The change for a slot, or `nil` when the row left it as it found it.
        private func change(for entry: Entry) -> Change? {
            switch entry {
            case let .made(change):
                return change
            case let .slot(slot):
                let new = after[slot]?.value
                let old = before.held(slot) ?? wholeBefore(slot)
                if let old, old.value == new { return nil }
                return Self.change(slot, kind: kinds[slot] ?? event.op, old: old?.value, new: new, paths: paths)
            }
        }

        /// A property's value read out of a whole-struct inverse, `common` or `kind`.
        private func wholeBefore(_ slot: Slot) -> Held? {
            guard case let .property(node, key) = slot else { return nil }
            if let common = before.commons[node], key.hasPrefix("common."),
               let value = try? NodePropertyCodec.commonValue(at: key, of: common, nodeID: node, nodeType: "")
            {
                return Held(value: value)
            }
            if let kind = before.kinds[node], key.hasPrefix("kind."),
               let value = try? NodePropertyCodec.kindValue(at: key, of: kind, nodeID: node)
            {
                return Held(value: value)
            }
            return nil
        }

        private static func change(
            _ slot: Slot, kind: ActivityEvent.Kind, old: AnyCodable?, new: AnyCodable?, paths: [String: String]
        ) -> Change {
            switch slot {
            case let .property(node, key):
                Change(kind: kind, node: node, path: paths[node], key: key, old: old, new: new)
            case let .override(ref, descendant, key):
                Change(kind: kind, node: ref, path: paths[ref], key: key, old: old, new: new, descendant: descendant)
            case let .variable(name), let .importAlias(name), let .themeAxis(name), let .document(name):
                Change(kind: kind, key: name, old: old, new: new)
            }
        }

        /// The one change a row with nothing to pair still has.
        private var fallback: Change {
            Change(kind: event.op, node: event.nodes.first, path: event.paths.first)
        }

        /// A node as a line names it: its name path when the row recorded one, else its id.
        private func name(of node: String?) -> String? {
            node.map { paths[$0] ?? $0 }
        }

        private func placeValue(parent: String?, index: Int?) -> AnyCodable {
            .dictionary([
                "parent": name(of: parent).map(AnyCodable.string) ?? .null,
                "index": index.map(AnyCodable.int) ?? .null,
            ])
        }
    }
}
