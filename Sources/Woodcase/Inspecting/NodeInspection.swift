//
//  NodeInspection.swift
//  Woodcase
//

import Foundation

/// What an inspector needs to know about one node of the expanded tree before it shows
/// a control: the address that edits it, where its values come from, and which of them
/// this instance overrides.
///
/// An editor draws and selects the **expanded** document, whose ids are not addresses —
/// an instance root is `<ref id>/<component root id>`, a node inside it
/// `<ref id>/<descendants key>`. ``EditableDocument/inspect(expandedID:)`` maps such an
/// id back to the ``ResolvedNodeAddress`` ``EditPlanner/plan(_:at:in:)-(_,ResolvedNodeAddress,_)``
/// takes, so inspector → planner round-trips without the editor knowing the format's
/// override rules.
///
/// ```swift
/// let inspection = document.inspect(expandedID: "Card1/Btn02/Lbl02")!
/// inspection.address          // .instanceDescendant(refID: "Card1", descendantKey: "Btn02/Lbl02")
/// inspection.overriddenPaths  // ["kind.content"]
/// let reset = try EditPlanner.plan(.resetOverride(inspection.overriddenPaths), at: inspection.address, in: document)
/// ```
public struct NodeInspection: Friendly {
    /// Where an inspected node's stored values live.
    public enum Source: Friendly {
        /// A node with storage of its own — a plain node, or one inside a component
        /// definition. Its properties are edited in place.
        case ownStorage

        /// An instance root: a `ref`. Its own properties (`common.x`, `common.enabled`)
        /// are its own; the component root's, as this instance shows them, are root
        /// overrides.
        ///
        /// - Parameter componentID: The component root the instance expands to, or `nil`
        ///   when the document cannot say — a missing component, or an unresolved import.
        case instance(componentID: String?)

        /// A node a component defines, shown through an instance. Its properties are
        /// overrides on the instance.
        ///
        /// - Parameter definitionID: The id of the node as the component stores it.
        case componentNode(definitionID: String)

        /// Content the instance wrote into a slot itself. It takes no override: a write
        /// to it is stored in the slot's fill, where it was written.
        case slotContent
    }

    /// One override this instance stores on the inspected node.
    public struct Override: Friendly {
        /// Creates an override.
        ///
        /// - Parameters:
        ///   - key: The raw key, as the `descendants` map or the ref's root overrides spell it.
        ///   - path: The property path an inspector's field row carries, or `nil`.
        ///   - value: The value the override stores.
        public init(key: String, path: String?, value: AnyCodable) {
            self.key = key
            self.path = path
            self.value = value
        }

        /// The raw key, as the file stores it — `fill`, `content`, `children`.
        public let key: String

        /// The property path the key belongs to — `kind.fills` — matching
        /// ``PenSchemaTable/Property/path``; `nil` for a key that is not a property, such
        /// as a slot's `children` or a whole-node replacement's `type`.
        public let path: String?

        /// The value the override stores, in the .pen file's own JSON shape.
        public let value: AnyCodable
    }

    /// Creates an inspection.
    ///
    /// - Parameters:
    ///   - expandedID: The node's id in the expanded document.
    ///   - address: The address that edits it.
    ///   - source: Where its stored values live.
    ///   - sourceNode: The node as stored, before this instance's overrides.
    ///   - overrides: The overrides this instance stores on it, sorted by key.
    public init(
        expandedID: String,
        address: ResolvedNodeAddress,
        source: Source,
        sourceNode: PenNode?,
        overrides: [Override]
    ) {
        self.expandedID = expandedID
        self.address = address
        self.source = source
        self.sourceNode = sourceNode
        self.overrides = overrides
    }

    /// The node's id in the expanded document.
    public let expandedID: String

    /// The address that edits the node — what ``EditPlanner`` takes.
    public let address: ResolvedNodeAddress

    /// Where the node's stored values live.
    public let source: Source

    /// The node as stored, before this instance's overrides: the node itself for
    /// ``Source/ownStorage``, the component root for ``Source/instance(componentID:)``,
    /// the node as its component defines it for ``Source/componentNode(definitionID:)``,
    /// and the node as the instance wrote it for ``Source/slotContent``. Its `children`
    /// may be stripped.
    public let sourceNode: PenNode?

    /// The overrides this instance stores on the node, sorted by key: its root overrides
    /// for an instance root, its `descendants` entry for a node inside it, and none for
    /// a node with storage of its own or slot content.
    public let overrides: [Override]

    /// The property paths this instance overrides on the node, sorted — the
    /// ``PenSchemaTable/Property/path`` of each field to mark as overridden.
    public var overriddenPaths: [String] {
        overrides.compactMap(\.path).sorted()
    }

    /// Whether this instance overrides a property of the node.
    ///
    /// - Parameter property: A property path (`kind.fills`) or a raw key (`fill`).
    /// - Returns: `true` when an override stores it.
    public func isOverridden(_ property: String) -> Bool {
        let key = NodePropertyCodec.rawKey(for: property)
        return overrides.contains { $0.key == key }
    }
}
