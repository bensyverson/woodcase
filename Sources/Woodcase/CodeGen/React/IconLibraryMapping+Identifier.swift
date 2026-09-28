//
//  IconLibraryMapping+Identifier.swift
//  Woodcase
//

extension IconLibraryMapping {
    /// The word an icon of `family` is suffixed with when it is imported under an alias:
    /// the Material Symbols styles by their style (`Outlined`, `Rounded`, `Sharp`), every
    /// other family by its own name (`Lucide`, `Feather`, `Phosphor`).
    static func identifierSuffix(for family: String) -> String {
        let materialPrefix = "Material Symbols "
        let word = family.hasPrefix(materialPrefix) ? String(family.dropFirst(materialPrefix.count)) : family
        return CodeGenName.typeName(word)
    }
}
