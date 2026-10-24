//
//  InstanceSlot.swift
//  Woodcase
//

import Foundation

/// A slot as one instance shows it: the slot frame, what fills it, and what its
/// component suggests filling it with.
///
/// A **slot** is a frame inside a component with `slot` set; an instance fills it by
/// storing the slot's whole content as one `children` override of the slot frame (its
/// **fill**). This is the read Layers, the inspector's Slot section and the slot menus
/// share (Penumbra spec §13.5): ``EditableDocument/slots(ofInstance:)``,
/// ``EditableDocument/slot(_:)`` and ``EditableDocument/slot(containing:)`` answer it.
///
/// ```swift
/// let list = document.slots(ofInstance: "Filled").first
/// list?.name                  // "List"
/// list?.state                 // .filled
/// list?.contentIDs            // ["Filled/Row1", "Filled/Row2", "Filled/Row3"]
/// list?.suggestedComponents   // Item/A, Item/B
/// ```
public struct InstanceSlot: Friendly {
    /// What a slot shows.
    public enum State: String, Friendly, CaseIterable {
        /// No fill: the slot shows its component's own content and follows the component.
        /// That content may itself be empty — ``InstanceSlot/layerCount`` says.
        case `default`

        /// A fill with at least one node.
        case filled

        /// A fill with nothing in it — not the same as the default, which may hold nodes.
        case empty
    }

    /// One entry of a slot's suggested components.
    public struct SuggestedComponent: Friendly {
        /// Creates an entry.
        ///
        /// - Parameters:
        ///   - id: The component id the slot's list names.
        ///   - name: The component's name, or `nil` when the document defines no such
        ///     component.
        public init(id: String, name: String?) {
            self.id = id
            self.name = name
        }

        /// The component id the slot's list names.
        public var id: String

        /// The component's name, or `nil` when the document defines no such component.
        public var name: String?

        /// Whether the document defines no component of this id ("Missing component").
        public var isMissing: Bool {
            name == nil
        }
    }

    /// Creates a slot read.
    ///
    /// - Parameters:
    ///   - id: The slot frame's expanded id.
    ///   - instanceID: The expanded id of the instance root that shows the slot.
    ///   - refID: The stored `ref` node whose overrides hold the fill.
    ///   - name: The slot frame's name, as its component names it.
    ///   - componentID: The component that defines the slot frame.
    ///   - componentSlotID: The slot frame's id in that component.
    ///   - state: What the slot shows.
    ///   - contentIDs: The expanded ids of the slot's top-level content, in order.
    ///   - suggestedComponents: The slot's suggested components, in order.
    public init(
        id: String,
        instanceID: String,
        refID: String,
        name: String,
        componentID: String,
        componentSlotID: String,
        state: State,
        contentIDs: [String],
        suggestedComponents: [SuggestedComponent]
    ) {
        self.id = id
        self.instanceID = instanceID
        self.refID = refID
        self.name = name
        self.componentID = componentID
        self.componentSlotID = componentSlotID
        self.state = state
        self.contentIDs = contentIDs
        self.suggestedComponents = suggestedComponents
    }

    /// The slot frame's expanded id — the id the layout, the renderer and a selection
    /// hold (`Filled/List`; `Panel1/Screen1/List` for a nested instance's slot).
    public var id: String

    /// The expanded id of the root of the instance whose component defines the slot:
    /// what "Screen › ▥ List" names first.
    public var instanceID: String

    /// The stored `ref` node whose `descendants` map holds the fill: the outermost
    /// instance, even for a slot of an instance nested in it or placed in one of its
    /// slots. It is the node an edit of this slot writes, and a revision guard pins.
    public var refID: String

    /// The slot frame's name, as its component names it (its id when it has none).
    public var name: String

    /// The component that defines the slot frame.
    public var componentID: String

    /// The slot frame's id in its component.
    public var componentSlotID: String

    /// What the slot shows.
    public var state: State

    /// The expanded ids of the slot's top-level content, in order: the fill's nodes, or
    /// the component's default content while the slot has none.
    public var contentIDs: [String]

    /// The slot's suggested components, in the order every slot menu lists them.
    public var suggestedComponents: [SuggestedComponent]

    /// How many layers the slot shows at its top level ("List, slot, 3 layers").
    public var layerCount: Int {
        contentIDs.count
    }
}
