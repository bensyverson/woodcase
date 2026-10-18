//
//  DefinitionCode.swift
//  Woodcase
//

/// The code generated for one definition: a component, or a view drawn from any other
/// root of a document (``CodeGeneration``).
///
/// It is the file `woodcase generate` writes for that definition, path and all: a
/// component's file is the same text whether it is asked for alone or generated with the
/// whole document. The components it uses are referenced by name, not included.
public struct DefinitionCode: Friendly {
    /// What a definition is.
    public enum Role: String, Friendly {
        /// A reusable component: a view or component that takes props.
        case component

        /// A view drawn from a root that is not a component — a board, a frame, a text, a
        /// shape, an instance — as `generate` draws a page.
        case view
    }

    /// Creates the code for one definition.
    ///
    /// - Parameters:
    ///   - id: The definition's node id.
    ///   - role: Whether it is a component or a view.
    ///   - typeName: The type the file declares.
    ///   - file: The file.
    public init(id: String, role: Role, typeName: String, file: GeneratedFile) {
        self.id = id
        self.role = role
        self.typeName = typeName
        self.file = file
    }

    /// The node id of the definition: the component's, or the root's a view is drawn from.
    public var id: String

    /// Whether it is a component or a view.
    public var role: Role

    /// The type the file declares: the React export (`Card`) or the SwiftUI view struct
    /// (`ToggleView`, `SettingsPage`).
    public var typeName: String

    /// The file, at the path `generate` writes it to (`components/Card.tsx`,
    /// `Sources/PenUI/Pages/Settings.swift`).
    public var file: GeneratedFile
}
