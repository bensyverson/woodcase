//
//  VariableReferences.swift
//  Woodcase
//

import Foundation

/// Everything in a document that mentions one variable.
///
/// A variable is referenced from two places, and a caller deciding whether removing it
/// is safe needs both: the nodes that bind a property to `$name`, and the other
/// variables whose own value is `$name` (a chain
/// ``PenVariableResolver`` resolves before it reaches any node).
///
/// ```swift
/// let referencing = document.references(to: "brand")
/// if !referencing.isEmpty {
///     print(referencing.nodeIDs.map(document.namePath(of:)))
/// }
/// ```
public struct VariableReferences: Friendly {
    /// Creates a set of references.
    ///
    /// - Parameters:
    ///   - nodeIDs: The nodes that bind a property to the variable, in document order.
    ///   - variableNames: The variables whose own value is a reference to it, sorted.
    public init(nodeIDs: [String] = [], variableNames: [String] = []) {
        self.nodeIDs = nodeIDs
        self.variableNames = variableNames
    }

    /// The nodes that bind a property to the variable, in document order.
    public var nodeIDs: [String]

    /// The variables whose own value is a reference to it, sorted by name.
    public var variableNames: [String]

    /// Whether nothing in the document mentions the variable.
    public var isEmpty: Bool {
        nodeIDs.isEmpty && variableNames.isEmpty
    }

    /// How many distinct things mention the variable.
    public var count: Int {
        nodeIDs.count + variableNames.count
    }
}
