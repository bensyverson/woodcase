//
//  EditingError.swift
//  Woodcase
//

import Foundation

/// Errors thrown by ``EditableDocument`` when an editing operation fails validation.
///
/// Each case identifies a specific constraint violation, carrying the relevant
/// identifiers so callers can present precise diagnostics.
public enum EditingError: Error, Equatable, Sendable {
    /// The node with the given ID does not exist in the document.
    case nodeNotFound(id: String)

    /// A node with this ID already exists in the document, or twice in one subtree.
    case duplicateNodeID(id: String)

    /// A supplied node id is not one the .pen format allows.
    ///
    /// See ``PenID/isValid(_:)`` for the rule: a non-empty string with no `/` in it.
    case invalidNodeID(id: String)

    /// The specified parent node does not exist in the document.
    case parentNotFound(id: String)

    /// The target parent node cannot have children (not a frame or group).
    case cannotHaveChildren(parentID: String)

    /// The insertion index is out of bounds for the target children array.
    case invalidIndex(index: Int, count: Int)

    /// Moving the node to the target parent would create a cycle in the tree.
    case wouldCreateCycle(nodeID: String, targetParentID: String)

    /// No variable with this name exists in the document.
    case variableNotFound(name: String)

    /// A variable with this name already exists in the document.
    case variableAlreadyExists(name: String)

    /// No import with this alias exists in the document.
    case importNotFound(alias: String)

    /// An import with this alias already exists in the document.
    case importAlreadyExists(alias: String)

    /// No theme axis with this name exists in the document.
    case themeAxisNotFound(name: String)

    /// A theme axis with this name already exists in the document.
    case themeAxisAlreadyExists(name: String)

    /// The specified node is not a `ref` node.
    case notARefNode(id: String)

    // MARK: - Property patches

    /// A property path is not a property of this node.
    ///
    /// `key` is the path as written (`"kind.fontSize"`); `nodeType` is the node's
    /// type name (`"rectangle"`) so a message can say why the key does not apply.
    case unknownProperty(nodeID: String, key: String, nodeType: String)

    /// A property path is known but the supplied value has the wrong shape.
    ///
    /// `expected` and `actual` are short human descriptions (`"number or $variable"`,
    /// `"string"`), used verbatim in the message.
    case propertyTypeMismatch(nodeID: String, key: String, expected: String, actual: String)

    // MARK: - Addressing

    /// An address matched more than one node. Every candidate is listed with its
    /// full name path so the caller can pick one by id.
    case ambiguousAddress(address: String, candidates: [NodeAddressCandidate])

    /// An address matched no node. `nearMisses` lists nodes whose leaf name
    /// matches the address's last segment, each with its full name path.
    case addressNotFound(address: String, nearMisses: [NodeAddressCandidate])

    // MARK: - Consequence guards

    /// Deleting this reusable component would silently turn its instances into
    /// plain frames. Refused unless the caller asks to detach them first.
    case componentHasInstances(componentID: String, instanceIDs: [String])

    /// Replacing this reusable component with a subtree of a different type would
    /// change what every instance of it draws, and would not converge between peers.
    /// Refused: rebuild the definition's contents, or change its type only once
    /// nothing points at it.
    case componentTypeChange(componentID: String, from: String, to: String, instanceIDs: [String])

    /// An override was addressed to a descendant that does not exist in the
    /// instance's component. `candidates` lists what the component does contain,
    /// each as an id-path plus full name path, so the caller can pick one.
    case overrideTargetNotFound(refID: String, descendantKey: String, candidates: [NodeAddressCandidate])

    /// A raw ``EditOperation/OverrideDescendant`` would store a key naming a node the
    /// instance wrote into a slot itself.
    ///
    /// The node is the instance's own slot content: Pen does not let the instance's
    /// keys reach it, drops such a key from the file and draws the node as written, and
    /// the expansion does the same. The node is edited where it is written — the
    /// `children` of the slot at `slotPath` — which is what an `override` *addressed* to
    /// it does (``BatchApplier`` plans it through `EditableDocument.slotFillRewrite(of:)`),
    /// so only a caller building the raw operation itself meets this.
    case overrideOnOwnSlotContent(refID: String, descendantKey: String, slotPath: String)

    /// An override's value is not one the node it patches can take.
    ///
    /// An override is merged onto the component's node as raw JSON when the instance
    /// expands, and a value of the wrong shape makes that merge fail — leaving the
    /// unpatched node, an override that reads back forever and never draws. Refused
    /// instead, at the write, where the caller can still correct it.
    ///
    /// `key` is the raw .pen key as it will be stored; `expected` and `actual` are the
    /// same short descriptions
    /// ``propertyTypeMismatch(nodeID:key:expected:actual:)`` carries.
    case overrideValueRejected(
        refID: String,
        descendantKey: String,
        key: String,
        expected: String,
        actual: String
    )

    /// A root override named a key the `ref` node reserves for itself.
    ///
    /// Root overrides are the ref node's own non-reserved top-level keys, so a reserved
    /// one would come back meaning the instance rather than the component root it was
    /// aimed at. `reason` says which family reserved it, and so which command writes it.
    case rootOverrideKeyReserved(refID: String, key: String, reason: RootOverrideRefusal)

    /// A root override's value is not one the component's root node can take.
    ///
    /// The root's half of ``overrideValueRejected(refID:descendantKey:key:expected:actual:)``,
    /// refused for the same reason: the patcher's answer to a merge that will not decode
    /// is the unpatched node, so the override would read back forever and never draw.
    case rootOverrideValueRejected(refID: String, key: String, expected: String, actual: String)

    // MARK: - Revisions

    /// A node's current revision differs from the one the caller expected.
    case revisionConflict(nodeID: String, expected: String, actual: String)
}
