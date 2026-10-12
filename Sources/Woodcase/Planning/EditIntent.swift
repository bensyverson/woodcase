//
//  EditIntent.swift
//  Woodcase
//

import Foundation

/// What a caller wants to change about one node, before anything decides how it is stored.
///
/// An intent says *what*; ``EditPlanner`` decides *how*. The same "make this label red"
/// is a `setProperties` on a node with storage of its own and an `overrideDescendant`
/// on a node inside a component instance, and the caller — an inspector, an agent's
/// `woodcase set`, a script — should not have to know which before it asks.
///
/// Keys are property paths (`kind.fills`, `common.opacity`), the vocabulary every read
/// prints. Where the write lands in an instance's override map they are translated to
/// the raw .pen keys that map uses (`fill`, `opacity`), so a raw key is accepted there
/// too; ``override(_:unset:)`` takes either vocabulary everywhere it applies.
///
/// ```swift
/// let plan = try EditPlanner.plan(.set(["kind.fills": "#E5484D"]), at: address, in: document)
/// ```
public enum EditIntent: Friendly {
    /// Writes properties on the addressed node.
    ///
    /// On a node with storage of its own this sets them in place. On a node inside a
    /// component instance it plans as an override on that instance — edits inside an
    /// instance are overrides — and the plan says so with a
    /// ``WriteDivergence/Kind/storedAsOverride`` note. On an instance root it sets the
    /// `ref` node's own properties (where it sits, whether it draws); the component
    /// root's properties as the instance shows them are ``override(_:unset:)``'s.
    ///
    /// A `null` value clears a property. A deep `common.metadata.<key>` path merges
    /// one entry.
    case set([String: AnyCodable])

    /// Overrides properties inside a component instance, or on the instance's root.
    ///
    /// Addressed at a node inside an instance it writes that node's `descendants`
    /// entry; addressed at the instance itself it writes the component root's
    /// properties as this instance shows them (its root overrides). A key the component
    /// publishes as a parameter is routed to the node the parameter names.
    ///
    /// - Parameters:
    ///   - properties: The overrides to write, by property path or raw .pen key.
    ///   - unset: Keys whose override is removed, so the component's value shows again.
    case override([String: AnyCodable], unset: [String] = [])

    /// Removes overrides, so the component's own values show again.
    ///
    /// The same plan as ``override(_:unset:)`` with only keys to unset.
    case resetOverride([String])

    /// Binds a property to a variable: stores `$name` there.
    ///
    /// Refused when the document defines no such variable, or one of a type the
    /// property does not take. Planned like ``set(_:)``, so a binding inside an instance
    /// is an override.
    ///
    /// - Parameters:
    ///   - property: The property path to bind.
    ///   - variable: The variable's name, with or without its leading `$`.
    case bind(property: String, variable: String)

    /// Replaces a property's variable binding with the value it resolves to now.
    ///
    /// The value is the variable's under the theme the node inherits, so the node
    /// looks the same afterward. Refused when the property is not bound.
    ///
    /// - Parameter property: The property path to unbind.
    case unbind(property: String)
}
