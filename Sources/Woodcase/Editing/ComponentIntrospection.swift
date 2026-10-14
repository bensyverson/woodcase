//
//  ComponentIntrospection.swift
//  Woodcase
//

import Foundation

/// Information about a slot frame within a component.
///
/// A slot is a frame in a component whose children an instance replaces. Its `slot`
/// list names the reusable components a designer suggested for it — Pen offers them
/// as one-click inserts — and refuses nothing: any node may fill a slot. See
/// `project/2026-10-14-slot-semantics.md`.
public struct ComponentSlotInfo: Friendly {
    /// The ID of the frame that defines this slot.
    public var frameID: String
    /// The display name of the slot frame.
    public var frameName: String?
    /// The ids of the reusable components suggested to fill this slot, as the frame's
    /// `slot` list writes them (`["round-button", "icon-button"]`); empty for a slot
    /// that suggests none. A suggestion, never a restriction.
    public var suggestedComponentIDs: [String]

    /// Creates the description of one slot.
    ///
    /// - Parameters:
    ///   - frameID: The ID of the frame that defines this slot.
    ///   - frameName: The display name of the slot frame.
    ///   - suggestedComponentIDs: The ids of the reusable components suggested for it.
    public init(frameID: String, frameName: String? = nil, suggestedComponentIDs: [String] = []) {
        self.frameID = frameID
        self.frameName = frameName
        self.suggestedComponentIDs = suggestedComponentIDs
    }
}

/// A node within a component that can have its properties overridden.
public struct OverridableNode: Friendly {
    /// The node's ID within the component.
    public var nodeID: String
    /// The node's display name.
    public var nodeName: String?
    /// The node type (e.g. `"frame"`, `"text"`, `"rectangle"`).
    public var nodeType: String
    /// The set of overridable property paths (e.g. `"kind.fills"`, `"common.opacity"`).
    public var properties: Set<String>

    public init(nodeID: String, nodeName: String? = nil, nodeType: String, properties: Set<String>) {
        self.nodeID = nodeID
        self.nodeName = nodeName
        self.nodeType = nodeType
        self.properties = properties
    }
}

/// Complete introspection surface for a reusable component.
///
/// Describes the component's slots (frames annotated with `slot`) and
/// all nodes whose properties can be overridden by ref instances.
public struct ComponentSurface: Friendly {
    /// The component's node ID.
    public var componentID: String
    /// The component's display name.
    public var componentName: String?
    /// Slot frames within the component.
    public var slots: [ComponentSlotInfo]
    /// All nodes in the component that can have properties overridden.
    public var overridableNodes: [OverridableNode]

    public init(
        componentID: String,
        componentName: String? = nil,
        slots: [ComponentSlotInfo] = [],
        overridableNodes: [OverridableNode] = []
    ) {
        self.componentID = componentID
        self.componentName = componentName
        self.slots = slots
        self.overridableNodes = overridableNodes
    }
}

// MARK: - EditableDocument Extension

public extension EditableDocument {
    /// Inspects a reusable component, returning its slots and overridable property surface.
    ///
    /// - Parameter componentID: The ID of the reusable component.
    /// - Returns: The component's introspection surface, or `nil` if the ID
    ///   doesn't exist in the ``componentRegistry``.
    func inspectComponent(_ componentID: String) -> ComponentSurface? {
        guard let component = reusableComponent(componentID) else { return nil }

        var slots: [ComponentSlotInfo] = []
        var overridableNodes: [OverridableNode] = []

        // Walk the component subtree
        walkComponentSubtree(nodeID: componentID, slots: &slots, overridableNodes: &overridableNodes)

        return ComponentSurface(
            componentID: componentID,
            componentName: component.common.name,
            slots: slots,
            overridableNodes: overridableNodes
        )
    }
}

extension EditableDocument {
    /// Walks the component subtree collecting slot info and overridable nodes.
    private func walkComponentSubtree(
        nodeID: String,
        slots: inout [ComponentSlotInfo],
        overridableNodes: inout [OverridableNode]
    ) {
        guard let node = componentNode(nodeID) else { return }

        // Collect overridable properties for this node
        let nodeType = kindTypeName(node.kind)
        let kindKeys = PropertyDiff.allKindKeys(node.kind)
        // Common properties are always overridable
        let commonKeys: Set = [
            "common.name", "common.x", "common.y", "common.rotation",
            "common.opacity", "common.enabled", "common.flipX", "common.flipY",
        ]
        let allProps = kindKeys.union(commonKeys)

        overridableNodes.append(OverridableNode(
            nodeID: nodeID,
            nodeName: node.common.name,
            nodeType: nodeType,
            properties: allProps
        ))

        // Check for slot
        if case let .frame(data) = node.kind, let slot = data.slot {
            slots.append(ComponentSlotInfo(
                frameID: nodeID,
                frameName: node.common.name,
                suggestedComponentIDs: slot
            ))
        }

        // Recurse into children
        for childID in componentChildIDs(of: nodeID) {
            walkComponentSubtree(nodeID: childID, slots: &slots, overridableNodes: &overridableNodes)
        }
    }

    /// Returns the type name string for a node kind.
    private func kindTypeName(_ kind: PenNode.Kind) -> String {
        kind.typeName
    }
}
