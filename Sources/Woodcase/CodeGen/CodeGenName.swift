//
//  CodeGenName.swift
//  Woodcase
//

/// The one rule that turns a frame's name into the type name code generation writes, for
/// a component and a page alike.
enum CodeGenName {
    /// The path prefix a component's name drops: the designer's `Component/` folder.
    static let componentPrefixes = ["Component/"]

    /// The path prefixes a page's name drops: the component folder, and the `Screen/`
    /// folder a page already is — so `Component/Screen/Settings` is the page `Settings`,
    /// while a reusable `Screen/Lab` stays the component `ScreenLab`.
    static let pagePrefixes = ["Component/Screen/", "Component/", "Screen/"]

    /// The type name for a frame named `rawName`.
    ///
    /// The first of `prefixes` that matches is dropped, and the rest is split into words at
    /// every character that is not a letter or a digit. A single word keeps its own casing
    /// with its first letter capitalized, so a designer's camel case survives (`FilledCard`,
    /// `filledCard` → `FilledCard`); several words are each capitalized and joined
    /// (`Tab Bar/Home Active` → `TabBarHomeActive`).
    static func typeName(_ rawName: String, droppingPrefixes prefixes: [String] = componentPrefixes) -> String {
        var name = rawName
        if let prefix = prefixes.first(where: name.hasPrefix) {
            name = String(name.dropFirst(prefix.count))
        }
        let words = name.split { !$0.isLetter && !$0.isNumber }
        if words.count == 1 {
            return words[0].prefix(1).uppercased() + words[0].dropFirst()
        }
        return words.map { word in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined()
    }

    /// `base`, or `base` followed by the first number from 2 that `isTaken` does not refuse:
    /// how a component or a page whose name another already has is told apart.
    static func numbered(_ base: String, isTaken: (String) -> Bool) -> String {
        var name = base
        var number = 2
        while isTaken(name) {
            name = "\(base)\(number)"
            number += 1
        }
        return name
    }
}
