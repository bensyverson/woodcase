//
//  EditPlanner+Variables.swift
//  Woodcase
//

import Foundation

extension EditPlanner {
    /// Plans a ``EditIntent/bind(property:variable:)``: a set of `$name`, with the
    /// variable required to exist — text content included, where a bare `$word` would
    /// otherwise be forgiven as literal text.
    ///
    /// - Parameters:
    ///   - property: The property path to bind.
    ///   - variable: The variable's name, with or without its `$`.
    ///   - target: The node.
    ///   - written: The address as written.
    ///   - document: The document.
    /// - Returns: The plan a set of the reference makes.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/undefinedVariable`` or
    ///   ``EditRefusal/Code/variableTypeMismatch``, or whatever the set refuses.
    static func planBind(
        _ property: String,
        to variable: String,
        at target: ResolvedNodeAddress,
        written: String,
        in document: EditableDocument
    ) throws -> EditPlan {
        let name = variable.hasPrefix(PenDollarEscape.dollar) ? String(variable.dropFirst()) : variable
        try checkBinding(
            property, to: name,
            expecting: NodePropertyCodec.bindableVariableType(of: property),
            address: written, in: document
        )
        return try planSet([property: .string(PenDollarEscape.dollar + name)], at: target, written: written, in: document)
    }

    /// Plans an ``EditIntent/unbind(property:)``: a set of the value the bound variable
    /// has under the theme the node draws with.
    ///
    /// - Parameters:
    ///   - property: The property path to unbind.
    ///   - target: The node.
    ///   - written: The address as written.
    ///   - document: The document.
    /// - Returns: The plan a set of that value makes.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/notBound`` when the property
    ///   holds no binding, or one to a variable that resolves to nothing.
    static func planUnbind(
        _ property: String,
        at target: ResolvedNodeAddress,
        written: String,
        in document: EditableDocument
    ) throws -> EditPlan {
        let placed: PlacedNode? = switch target {
        case let .node(id): PlacedNode(node: id, in: document)
        case let .instanceDescendant(refID, key): PlacedNode(descendant: key, ofInstance: refID, in: document)
        }
        let bound = placed.flatMap { try? NodePropertyCodec.value(at: property, of: $0.node) }
        guard case let .string(text)? = bound, text.hasPrefix(PenDollarEscape.dollar),
              !text.hasPrefix(PenDollarEscape.sequence)
        else {
            throw notBound(property, address: written)
        }
        let name = String(text.dropFirst())
        let table = document.resolvedVariables(under: placed?.theme(axes: document.themes) ?? [:])
        guard let value = table[name] else {
            throw notBound(property, address: written)
        }
        return try planSet([property: value], at: target, written: written, in: document)
    }

    /// The refusal for an unbind of a property that holds no usable binding.
    private static func notBound(_ property: String, address: String) -> EditRefusal {
        EditRefusal(
            code: .notBound,
            address: address,
            property: property,
            expected: "a $variable reference",
            message: "\(address) \(property) is not bound to a variable it can resolve, so there is "
                + "nothing to unbind — `woodcase get <file> \(address)` shows what it holds"
        )
    }
}
