//
//  DefinitionSelection.swift
//  Woodcase
//

/// The definitions ``CodeGeneration`` was asked for, resolved against a document: each a
/// component of the document or a view drawn from one of its roots, in the order asked.
struct DefinitionSelection: Friendly {
    /// One definition asked for.
    enum Entry: Friendly {
        /// The component with this id.
        case component(ComponentDefinition)

        /// The view drawn from the root with this id.
        case view(PageDefinition)
    }

    /// Every component of the document, which a definition's instances call by name.
    var components: [ComponentDefinition]

    /// The definitions asked for, in order.
    var entries: [Entry]
}
