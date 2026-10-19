//
//  EditPlanner+Holder.swift
//  Woodcase
//

import Foundation

extension EditPlanner {
    /// What holds a node's values, as far as where a write is stored goes — the one fact
    /// ``routeWrites(_:at:in:)``, ``plan(_:routedAt:in:)`` and
    /// ``NodeInspection/storage(of:)`` each decide a write's storage from, so the three
    /// cannot disagree.
    enum Holder: Friendly {
        /// A node with storage of its own: every property is stored on it.
        case ownNode

        /// An instance root, a `ref` node: its `common.` properties are its own, and the
        /// component root's, as this instance shows them, are root overrides.
        case instanceRoot

        /// A node inside an instance — a node its component defines, or content the
        /// instance wrote into a slot: every property is an override on the outermost
        /// instance, which the planner writes into the slot's fill for slot content.
        case insideInstance

        /// What holds the values of the node an address names.
        ///
        /// - Parameters:
        ///   - target: The node.
        ///   - document: The document, to tell an instance root from a node.
        init(_ target: ResolvedNodeAddress, in document: EditableDocument) {
            switch target {
            case let .node(id):
                if case .ref? = document.node(id: id)?.kind {
                    self = .instanceRoot
                } else {
                    self = .ownNode
                }
            case .instanceDescendant:
                self = .insideInstance
            }
        }

        /// What holds the values of an inspected node.
        ///
        /// - Parameter source: Where the inspection found its values.
        init(_ source: NodeInspection.Source) {
            switch source {
            case .ownStorage: self = .ownNode
            case .instance: self = .instanceRoot
            case .componentNode, .slotContent: self = .insideInstance
            }
        }

        /// Where a write of one property is stored.
        ///
        /// - Parameter path: A property path (`common.x`, `kind.fills`).
        /// - Returns: ``EditPlan/Storage/node`` for the node's own storage — the `ref` node's,
        ///   for an instance root's `common.` properties — and
        ///   ``EditPlan/Storage/instanceOverride`` otherwise.
        func storage(of path: String) -> EditPlan.Storage {
            switch self {
            case .ownNode: .node
            case .instanceRoot: path.hasPrefix(NodePropertyCodec.commonPrefix) ? .node : .instanceOverride
            case .insideInstance: .instanceOverride
            }
        }

        /// Splits writes by where each is stored.
        ///
        /// - Parameter properties: The writes, by property path.
        /// - Returns: The writes stored on the node itself, and those stored as overrides.
        func split(_ properties: [String: AnyCodable]) -> (own: [String: AnyCodable], overridden: [String: AnyCodable]) {
            (
                properties.filter { storage(of: $0.key) == .node },
                properties.filter { storage(of: $0.key) == .instanceOverride }
            )
        }
    }
}
