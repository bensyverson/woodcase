//
//  SwiftUIEmitter+TypeNames.swift
//  Woodcase
//

extension SwiftUIEmitter {
    /// The view struct name for each component, by component id: its analyzed name made a
    /// legal identifier, suffixed `View` where it would shadow a SwiftUI type the module
    /// uses (`Toggle` is `ToggleView`), and numbered where two components share one.
    static func componentTypeNames(_ components: [ComponentDefinition]) -> [String: String] {
        var names: [String: String] = [:]
        var taken: Set<String> = []
        for component in components {
            var base = identifier(component.name, fallback: "Component")
            if shadowedNames.contains(base) {
                base += "View"
            }
            var name = base
            var suffix = 2
            while taken.contains(name) {
                name = "\(base)\(suffix)"
                suffix += 1
            }
            taken.insert(name)
            names[component.id] = name
        }
        return names
    }

    /// The Swift type name for a page: its analyzed name made a legal identifier,
    /// suffixed `Page` where it would shadow a SwiftUI type the emitted code uses or a
    /// component in `taken`.
    static func typeName(for page: PageDefinition, taken: Set<String> = []) -> String {
        var name = identifier(page.name, fallback: "Page")
        if shadowedNames.contains(name) || taken.contains(name) {
            name += "Page"
        }
        return name
    }

    /// `name`, or `fallback` when it is empty, prefixed with `fallback` when it starts
    /// with a digit.
    private static func identifier(_ name: String, fallback: String) -> String {
        guard !name.isEmpty else { return fallback }
        return name.first?.isNumber == true ? fallback + name : name
    }

    /// The names a page or component may not take, since it would shadow the type inside
    /// the module: SwiftUI and Foundation names the emitted views and support files refer
    /// to or that a module of views commonly does, every type the support files declare
    /// (``supportTypeNames``) and the catalog's views (``SwiftUICatalog/typeNames``).
    private static let shadowedNames: Set<String> = .init([
        "AnyView", "Button", "Canvas", "Color", "EdgeInsets", "Ellipse", "EmptyView", "Font", "Form", "Gradient",
        "Group", "HStack", "Image", "Label", "Link", "List", "Menu", "Path", "PenGradient", "PenTheme", "PenThemeReader",
        "Picker", "Rectangle",
        "Section", "Shape", "Slider", "Spacer", "TabView", "Text", "TextField", "Toggle", "UnitPoint", "View",
        "VStack", "ZStack",
    ]).union(supportTypeNames).union(SwiftUICatalog.typeNames)

    /// Every type the support templates declare at the top level — a `struct`, `enum`,
    /// `class`, `actor`, `protocol` or `typealias` — read from the templates, so a new
    /// support type is shadow-proof without a list to keep. A nested type is left out: a
    /// page of its name cannot shadow it.
    static let supportTypeNames: Set<String> = {
        let declaration = /^(?:(?:public|internal|fileprivate|private|final)\s+)*(?:struct|enum|class|actor|protocol|typealias)\s+([A-Z][A-Za-z0-9_]*)/
        var names: Set<String> = []
        for template in supportTemplates.values {
            for line in template.split(separator: "\n") {
                if let match = line.prefixMatch(of: declaration) {
                    names.insert(String(match.1))
                }
            }
        }
        return names
    }()
}
