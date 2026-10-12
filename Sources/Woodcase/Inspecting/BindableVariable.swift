//
//  BindableVariable.swift
//  Woodcase
//

import Foundation

/// A variable a property may be bound to, and the value it has where the node draws.
///
/// ``EditableDocument/bindableVariables(for:at:)`` lists them: only variables of the type
/// the property's ``PenPropertyShape/variable`` names, so every one of them plans through
/// ``EditPlanner`` as ``EditIntent/bind(property:variable:)`` without a
/// ``EditRefusal/Code/variableTypeMismatch``.
public struct BindableVariable: Friendly {
    /// Where a variable is defined.
    public enum Origin: Friendly {
        /// The document's own `variables`.
        case document

        /// A library the document imports and was read with.
        ///
        /// - Parameter alias: The import alias its name starts with — `K` in `K:accent`.
        case library(alias: String)
    }

    /// Creates an entry.
    ///
    /// - Parameters:
    ///   - name: The variable's name, without `$`.
    ///   - type: Its type.
    ///   - origin: Where it is defined.
    ///   - value: Its value under the theme the node draws with, or `nil`.
    public init(name: String, type: PenVariableType, origin: Origin, value: AnyCodable?) {
        self.name = name
        self.type = type
        self.origin = origin
        self.value = value
    }

    /// The variable's name, without `$` — `brand`, or `K:accent` for an imported one.
    public let name: String

    /// The variable's type.
    public let type: PenVariableType

    /// Where the variable is defined.
    public let origin: Origin

    /// The value it resolves to under the theme the node draws with, aliases followed,
    /// or `nil` when it resolves to nothing.
    public let value: AnyCodable?

    /// The reference a property bound to it holds — `$brand`.
    public var reference: String {
        PenDollarEscape.dollar + name
    }
}
