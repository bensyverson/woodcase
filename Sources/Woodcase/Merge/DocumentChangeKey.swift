//
//  DocumentChangeKey.swift
//  Woodcase
//

import Foundation

/// One document-level member that differs between two documents.
///
/// Each key is the unit a three-way merge resolves on, so the keyed tables are keyed
/// per entry — two sides that edit different variables never conflict — while
/// ``fonts`` is one key because the declaration list has no identity per entry.
/// The values themselves are read from the documents: ``EditableDocument/variables``,
/// ``EditableDocument/imports``, ``EditableDocument/themes`` and so on.
public enum DocumentChangeKey: Friendly {
    /// A variable was added, removed or redefined, named by its variable name.
    case variable(String)

    /// An import alias was added, removed or repointed, named by its alias.
    case importAlias(String)

    /// A theme axis was added, removed or given different options, named by its axis.
    case themeAxis(String)

    /// The declared font list differs, compared whole.
    case fonts

    /// The format version string differs.
    case version

    /// The per-save file token differs.
    case fileToken

    /// A root key the model does not claim was added, removed or changed, named by its key.
    case extra(String)

    /// The ordered list of top-level nodes differs.
    case rootOrder

    /// A table is declared on one side only — written `{}` against left out. Its
    /// entries are compared per key, where an absent table holds none, so this is the
    /// one difference those keys cannot carry.
    case declaredTable(Table)

    /// The document tables that are written per entry.
    public enum Table: String, Friendly {
        /// ``EditableDocument/variables``.
        case variables
        /// ``EditableDocument/imports``.
        case imports
        /// ``EditableDocument/themes``.
        case themes
    }
}
