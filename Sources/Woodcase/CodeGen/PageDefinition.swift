//
//  PageDefinition.swift
//  Woodcase
//

/// A page/screen extracted from a .pen document for code generation.
///
/// Pages are top-level frames that are not reusable components. They represent
/// screens in the application and import/instantiate child components.
public struct PageDefinition: Friendly {
    public init(
        id: String,
        name: String,
        sourceNode: PenNode
    ) {
        self.id = id
        self.name = name
        self.sourceNode = sourceNode
    }

    /// The source node ID.
    public var id: String

    /// The page's type name (e.g., "Settings"): its frame's name by the rule a component's
    /// takes, made unique against the components and the other pages by
    /// ``PageAnalyzer/analyze(_:)``.
    public var name: String

    /// The page's root node.
    public var sourceNode: PenNode
}
