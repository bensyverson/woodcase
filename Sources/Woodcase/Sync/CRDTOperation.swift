//
//  CRDTOperation.swift
//  Woodcase
//

import Foundation

/// A single CRDT operation that can be replicated between peers.
///
/// Each operation carries:
/// - A unique ``id`` (``Timestamp``) for total ordering
/// - A ``dependencies`` vector clock for causal ordering
/// - A ``payload`` describing the mutation
///
/// Operations are the unit of replication: the consuming app stores and
/// transmits `CRDTOperation` values, and Woodcase's ``CRDTDocument``
/// processes them to maintain convergence.
public struct CRDTOperation: Friendly {
    /// The operation's unique, totally-ordered identifier.
    public var id: Timestamp

    /// The vector clock at the time this operation was created.
    public var dependencies: VectorClock

    /// The mutation this operation performs.
    public var payload: Payload

    /// Creates a CRDT operation.
    ///
    /// - Parameters:
    ///   - id: The unique timestamp for this operation.
    ///   - dependencies: The causal dependencies.
    ///   - payload: The mutation to perform.
    public init(id: Timestamp, dependencies: VectorClock, payload: Payload) {
        self.id = id
        self.dependencies = dependencies
        self.payload = payload
    }

    // MARK: - Payload

    /// The specific mutation an operation performs.
    public enum Payload: Friendly {
        /// Set a single property on a node.
        case setProperty(SetProperty)
        /// Insert an element into an ordered list.
        case listInsert(ListInsert)
        /// Delete (tombstone) an element from an ordered list.
        case listDelete(ListDelete)
        /// Move an element between or within ordered lists.
        case listMove(ListMove)
        /// Move a node in the tree hierarchy.
        case treeMove(TreeMove)
        /// Create a new node.
        case createNode(CreateNode)
        /// Delete a node (tombstone).
        case deleteNode(DeleteNode)
        /// Set a document-level variable.
        case setVariable(SetVariable)
        /// Remove a document-level variable.
        case removeVariable(RemoveVariable)
        /// Set a document-level import.
        case setImport(SetImport)
        /// Remove a document-level import.
        case removeImport(RemoveImport)
        /// Set a theme axis.
        case setThemeAxis(SetThemeAxis)
        /// Remove a theme axis.
        case removeThemeAxis(RemoveThemeAxis)
    }

    // MARK: - Payload parameter structs

    /// Parameters for setting a single property on a node.
    public struct SetProperty: Friendly {
        /// The target node ID.
        public var nodeID: String
        /// The property path (e.g. `"common.name"`, `"kind.width"`).
        public var property: String
        /// The new value, type-erased for serialization.
        public var value: AnyCodable

        public init(nodeID: String, property: String, value: AnyCodable) {
            self.nodeID = nodeID
            self.property = property
            self.value = value
        }
    }

    /// Parameters for inserting into an ordered list.
    public struct ListInsert: Friendly {
        /// The list identifier (parent node ID, or `"__root__"` for root order).
        public var listID: String
        /// The element being inserted (typically a node ID).
        public var elementID: String
        /// The predecessor position, or `nil` for the beginning.
        public var afterPositionID: PositionID?
        /// The timestamp to use as the new element's position ID.
        public var positionTimestamp: Timestamp

        public init(listID: String, elementID: String, afterPositionID: PositionID?, positionTimestamp: Timestamp) {
            self.listID = listID
            self.elementID = elementID
            self.afterPositionID = afterPositionID
            self.positionTimestamp = positionTimestamp
        }
    }

    /// Parameters for deleting from an ordered list.
    public struct ListDelete: Friendly {
        /// The list identifier.
        public var listID: String
        /// The position to tombstone.
        public var positionID: PositionID

        public init(listID: String, positionID: PositionID) {
            self.listID = listID
            self.positionID = positionID
        }
    }

    /// Parameters for moving an element between ordered lists.
    public struct ListMove: Friendly {
        /// The source list ID.
        public var sourceListID: String
        /// The target list ID.
        public var targetListID: String
        /// The position being moved.
        public var positionID: PositionID
        /// The predecessor in the target list, or `nil` for the beginning.
        public var afterPositionID: PositionID?
        /// The timestamp for the new position in the target list.
        public var newPositionTimestamp: Timestamp

        public init(sourceListID: String, targetListID: String, positionID: PositionID, afterPositionID: PositionID?, newPositionTimestamp: Timestamp) {
            self.sourceListID = sourceListID
            self.targetListID = targetListID
            self.positionID = positionID
            self.afterPositionID = afterPositionID
            self.newPositionTimestamp = newPositionTimestamp
        }
    }

    /// Parameters for a tree move operation.
    public struct TreeMove: Friendly {
        /// The node being moved.
        public var nodeID: String
        /// The new parent, or `nil` for root.
        public var newParentID: String?

        public init(nodeID: String, newParentID: String?) {
            self.nodeID = nodeID
            self.newParentID = newParentID
        }
    }

    /// Parameters for creating a new node.
    public struct CreateNode: Friendly {
        /// The node to create (with children stripped).
        public var node: PenNode
        /// The parent node ID, or `nil` for root.
        public var parentID: String?

        public init(node: PenNode, parentID: String?) {
            self.node = node
            self.parentID = parentID
        }
    }

    /// Parameters for deleting (tombstoning) a node.
    public struct DeleteNode: Friendly {
        /// The node ID to delete.
        public var nodeID: String

        public init(nodeID: String) {
            self.nodeID = nodeID
        }
    }

    /// Parameters for setting a variable.
    public struct SetVariable: Friendly {
        /// The variable name.
        public var name: String
        /// The variable definition.
        public var variable: PenVariable

        public init(name: String, variable: PenVariable) {
            self.name = name
            self.variable = variable
        }
    }

    /// Parameters for removing a variable.
    public struct RemoveVariable: Friendly {
        /// The variable name.
        public var name: String

        public init(name: String) {
            self.name = name
        }
    }

    /// Parameters for setting an import.
    public struct SetImport: Friendly {
        /// The import alias.
        public var alias: String
        /// The file path or URL.
        public var path: String

        public init(alias: String, path: String) {
            self.alias = alias
            self.path = path
        }
    }

    /// Parameters for removing an import.
    public struct RemoveImport: Friendly {
        /// The import alias.
        public var alias: String

        public init(alias: String) {
            self.alias = alias
        }
    }

    /// Parameters for setting a theme axis.
    public struct SetThemeAxis: Friendly {
        /// The theme axis name.
        public var name: String
        /// The axis options.
        public var options: [String]

        public init(name: String, options: [String]) {
            self.name = name
            self.options = options
        }
    }

    /// Parameters for removing a theme axis.
    public struct RemoveThemeAxis: Friendly {
        /// The theme axis name.
        public var name: String

        public init(name: String) {
            self.name = name
        }
    }
}
