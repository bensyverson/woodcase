//
//  EditOperation.swift
//  Woodcase
//

import Foundation

/// A typed editing operation that can be applied to an ``EditableDocument``.
///
/// Each case carries a small struct with the operation's parameters.
/// Operations are value types conforming to ``Friendly``, so they can be
/// serialized, compared, and stored for undo/redo or sync purposes.
public enum EditOperation: Friendly {
    // MARK: - Node structural

    /// Insert a new node into the document.
    case insertNode(InsertNode)
    /// Delete a node (and all descendants) from the document.
    case deleteNode(DeleteNode)
    /// Move a node to a new parent or position.
    case moveNode(MoveNode)
    /// Swap everything a node is and holds for a new subtree, keeping its place.
    case replaceSubtree(ReplaceSubtree)

    // MARK: - Node properties

    /// Replace a node's common properties.
    case updateCommon(UpdateCommon)
    /// Replace a node's kind-specific data.
    case updateKind(UpdateKind)
    /// Set individual node properties addressed by path, leaving the rest alone.
    case setProperties(SetProperties)

    // MARK: - Component operations

    /// Create or update a descendant override on a ref node.
    case overrideDescendant(OverrideDescendant)
    /// Create or update the root overrides a ref node shows the component through.
    case overrideRoot(OverrideRoot)
    /// Detach a ref node, replacing it with expanded independent nodes.
    case detachRef(DetachRef)

    // MARK: - Variables

    /// Add a new variable to the document.
    case addVariable(AddVariable)
    /// Update an existing variable.
    case updateVariable(UpdateVariable)
    /// Remove a variable from the document.
    case removeVariable(RemoveVariable)

    // MARK: - Imports

    /// Add a new import alias.
    case addImport(AddImport)
    /// Update an existing import's path.
    case updateImport(UpdateImport)
    /// Remove an import alias.
    case removeImport(RemoveImport)

    // MARK: - Themes

    /// Add a new theme axis.
    case addThemeAxis(AddThemeAxis)
    /// Update an existing theme axis's options.
    case updateThemeAxis(UpdateThemeAxis)
    /// Remove a theme axis.
    case removeThemeAxis(RemoveThemeAxis)

    // MARK: - Parameter Structs

    /// Parameters for inserting a node.
    ///
    /// - If `parentID` is `nil`, the node is inserted at root level.
    /// - If `index` is `nil`, the node is appended.
    public struct InsertNode: Friendly {
        public init(node: PenNode, parentID: String? = nil, index: Int? = nil) {
            self.node = node
            self.parentID = parentID
            self.index = index
        }

        /// The node to insert (may include inline children for subtree insertion).
        public var node: PenNode
        /// The parent to insert into, or `nil` for root level.
        public var parentID: String?
        /// The position within the parent's children, or `nil` to append.
        public var index: Int?
    }

    /// Parameters for deleting a node and all its descendants.
    ///
    /// Deleting a reusable component strands every `ref` that points at it: the
    /// instances stop expanding and quietly become empty. ``instances`` decides what
    /// happens then — refuse and name them, or detach them into independent nodes
    /// first. A delete that strands nothing ignores it entirely.
    public struct DeleteNode: Friendly {
        /// What a delete does about component instances it would strand.
        ///
        /// An instance is stranded when the deleted subtree contains the component it
        /// points at and the instance itself survives the delete. Instances *inside*
        /// the deleted subtree go away with it and are not stranded.
        public enum Instances: String, Friendly {
            /// Refuse the delete, naming every instance that would be stranded.
            case refuse
            /// Detach every stranded instance into independent nodes, then delete.
            case detach
        }

        /// Creates a delete for one node and its descendants.
        ///
        /// - Parameters:
        ///   - nodeID: The ID of the node to delete.
        ///   - instances: What to do about stranded component instances.
        ///     Defaults to ``Instances/refuse``.
        public init(nodeID: String, instances: Instances = .refuse) {
            self.nodeID = nodeID
            self.instances = instances
        }

        /// The ID of the node to delete.
        public var nodeID: String

        /// What to do about component instances this delete would strand.
        public var instances: Instances
    }

    /// Parameters for moving a node to a new parent or position.
    ///
    /// - If `newParentID` is `nil`, the node is moved to root level.
    /// - If `index` is `nil`, the node is appended.
    public struct MoveNode: Friendly {
        public init(nodeID: String, newParentID: String? = nil, index: Int? = nil) {
            self.nodeID = nodeID
            self.newParentID = newParentID
            self.index = index
        }

        /// The ID of the node to move.
        public var nodeID: String
        /// The new parent, or `nil` for root level.
        public var newParentID: String?
        /// The position within the new parent's children, or `nil` to append.
        public var index: Int?
    }

    /// Parameters for replacing a node's whole subtree in place.
    ///
    /// The node keeps its id, its parent and its index among its siblings; everything
    /// else about it — its common properties, its kind payload and every descendant —
    /// is whatever ``node`` says it is. That is what makes "rebuild this" one
    /// operation rather than a delete and an insert: a delete would take the node's
    /// place with it, and every reference to its id.
    ///
    /// ``node``'s own `id` names the node being replaced, so the operation carries no
    /// second identifier that could disagree with it.
    ///
    /// Descendant ids are the caller's to choose: an id the subtree supplies is kept,
    /// as long as it is valid, not repeated, and not held by a node outside the
    /// subtree being replaced — the ids that subtree holds today are freed by the
    /// replacement and may be reused.
    ///
    /// ```swift
    /// try document.apply(.replaceSubtree(EditOperation.ReplaceSubtree(node: rebuilt)))
    /// ```
    public struct ReplaceSubtree: Friendly {
        /// Creates a replacement.
        ///
        /// - Parameter node: The subtree that takes the node's place. Its `id` is the
        ///   id of the node being replaced.
        public init(node: PenNode) {
            self.node = node
        }

        /// The subtree that takes the node's place, carrying the id it keeps.
        public var node: PenNode
    }

    /// Parameters for replacing a node's common properties.
    public struct UpdateCommon: Friendly {
        public init(nodeID: String, common: PenNodeCommon) {
            self.nodeID = nodeID
            self.common = common
        }

        /// The ID of the node to update.
        public var nodeID: String
        /// The new common properties.
        public var common: PenNodeCommon
    }

    /// Parameters for replacing a node's kind-specific data.
    public struct UpdateKind: Friendly {
        public init(nodeID: String, kind: PenNode.Kind) {
            self.nodeID = nodeID
            self.kind = kind
        }

        /// The ID of the node to update.
        public var nodeID: String
        /// The new kind-specific data. Children will be stripped to preserve the flat store invariant.
        public var kind: PenNode.Kind
    }

    /// Parameters for setting individual node properties by path.
    ///
    /// Where ``UpdateKind`` replaces a node's whole kind payload, this patches
    /// only the paths it names. Keys come from ``NodePropertyCodec/paths(for:)``
    /// — the same `"common.name"` / `"kind.width"` vocabulary ``PropertyDiff``
    /// emits — and values are in the .pen file's own JSON shape. A value of
    /// ``AnyCodable/null`` clears the property.
    ///
    /// The operation is atomic: every key and value is validated before anything
    /// is written, so a map with one bad entry leaves the document untouched.
    ///
    /// ```swift
    /// try document.apply(.setProperties(EditOperation.SetProperties(
    ///     nodeID: "r1",
    ///     properties: ["kind.fills": .string("blue"), "kind.width": .int(240)]
    /// )))
    /// ```
    public struct SetProperties: Friendly {
        /// Creates a patch naming the node and the properties to set.
        ///
        /// - Parameters:
        ///   - nodeID: The ID of the node to patch.
        ///   - properties: The properties to set, keyed by property path.
        public init(nodeID: String, properties: [String: AnyCodable]) {
            self.nodeID = nodeID
            self.properties = properties
        }

        /// The ID of the node to patch.
        public var nodeID: String
        /// The properties to set, keyed by property path.
        public var properties: [String: AnyCodable]
    }

    /// Parameters for adding a variable.
    public struct AddVariable: Friendly {
        public init(name: String, variable: PenVariable) {
            self.name = name
            self.variable = variable
        }

        /// The variable name.
        public var name: String
        /// The variable definition.
        public var variable: PenVariable
    }

    /// Parameters for updating a variable.
    public struct UpdateVariable: Friendly {
        public init(name: String, variable: PenVariable) {
            self.name = name
            self.variable = variable
        }

        /// The variable name.
        public var name: String
        /// The updated variable definition.
        public var variable: PenVariable
    }

    /// Parameters for removing a variable.
    public struct RemoveVariable: Friendly {
        public init(name: String) {
            self.name = name
        }

        /// The variable name to remove.
        public var name: String
    }

    /// Parameters for adding an import alias.
    public struct AddImport: Friendly {
        public init(alias: String, path: String) {
            self.alias = alias
            self.path = path
        }

        /// The import alias.
        public var alias: String
        /// The file path or URL.
        public var path: String
    }

    /// Parameters for updating an import's path.
    public struct UpdateImport: Friendly {
        public init(alias: String, path: String) {
            self.alias = alias
            self.path = path
        }

        /// The import alias to update.
        public var alias: String
        /// The new file path or URL.
        public var path: String
    }

    /// Parameters for removing an import alias.
    public struct RemoveImport: Friendly {
        public init(alias: String) {
            self.alias = alias
        }

        /// The import alias to remove.
        public var alias: String
    }

    /// Parameters for adding a theme axis.
    public struct AddThemeAxis: Friendly {
        public init(name: String, options: [String]) {
            self.name = name
            self.options = options
        }

        /// The theme axis name.
        public var name: String
        /// The axis options (e.g. `["light", "dark"]`).
        public var options: [String]
    }

    /// Parameters for updating a theme axis's options.
    public struct UpdateThemeAxis: Friendly {
        public init(name: String, options: [String]) {
            self.name = name
            self.options = options
        }

        /// The theme axis name.
        public var name: String
        /// The updated options.
        public var options: [String]
    }

    /// Parameters for removing a theme axis.
    public struct RemoveThemeAxis: Friendly {
        public init(name: String) {
            self.name = name
        }

        /// The theme axis name to remove.
        public var name: String
    }

    // MARK: - Component Parameter Structs

    /// Parameters for creating or updating a descendant override on a ref node.
    public struct OverrideDescendant: Friendly {
        /// Creates the parameters.
        ///
        /// - Parameters:
        ///   - refNodeID: The instance whose `descendants` map is written.
        ///   - descendantID: The key inside that map.
        ///   - properties: Raw .pen keys to merge into the entry.
        ///   - unset: Raw .pen keys to remove from the entry, applied after the merge.
        public init(
            refNodeID: String,
            descendantID: String,
            properties: [String: AnyCodable],
            unset: [String] = []
        ) {
            self.refNodeID = refNodeID
            self.descendantID = descendantID
            self.properties = properties
            self.unset = unset
        }

        /// The ID of the ref node to apply the override to.
        public var refNodeID: String
        /// The descendant ID within the component to override.
        public var descendantID: String
        /// The properties to merge into the override.
        public var properties: [String: AnyCodable]
        /// The keys to remove from the override, applied after ``properties`` merges.
        ///
        /// Removing a key is not the same as overriding it with null: a null is stored
        /// and clears the definition's value when the instance expands, while a removed
        /// key leaves the definition showing through. An entry left with no keys at all
        /// goes away, so a removal reads back as the absence it is.
        public var unset: [String] = []
    }

    /// Parameters for creating or updating the root overrides on a ref node.
    ///
    /// A `ref` shows the component's *root* through its own non-reserved top-level
    /// keys — the format has no `rootOverrides` object, whatever the property path
    /// suggests. These are the component root's own kind properties as this one
    /// instance sees them; the ref node's `common` properties are its own and are set
    /// on the ref directly.
    public struct OverrideRoot: Friendly {
        /// Creates the parameters.
        ///
        /// - Parameters:
        ///   - refNodeID: The instance whose root overrides are written.
        ///   - properties: Raw .pen keys to merge into them.
        ///   - unset: Raw .pen keys to remove, applied after the merge.
        public init(
            refNodeID: String,
            properties: [String: AnyCodable],
            unset: [String] = []
        ) {
            self.refNodeID = refNodeID
            self.properties = properties
            self.unset = unset
        }

        /// The ID of the ref node whose root overrides are written.
        public var refNodeID: String
        /// The properties to merge into the root overrides.
        public var properties: [String: AnyCodable]
        /// The keys to remove from the root overrides, applied after the merge.
        public var unset: [String] = []
    }

    /// Parameters for detaching a ref node (replacing it with expanded nodes).
    public struct DetachRef: Friendly {
        public init(refNodeID: String) {
            self.refNodeID = refNodeID
        }

        /// The ID of the ref node to detach.
        public var refNodeID: String
    }
}
