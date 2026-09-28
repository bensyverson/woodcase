//
//  SwiftUINodeEmitter+Icon.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// An icon: its glyph's outline as a shape (`PenIconShape`), read from the library's
    /// font, which the package bundles as a resource and registers with its other fonts
    /// (`PenFonts`), and painted with the node's fills like any shape.
    ///
    /// The glyph is as large as the box's shorter side and placed by the font's metrics,
    /// by the renderer's rule (`PenIconFontRenderer.glyphOrigin`), as Pen places it. A name the library does not know draws
    /// the library's own question mark, as Pen does; a library with no bundled font, or one
    /// named by a variable, is a placeholder with a warning.
    func icon(_ node: PenNode, data: PenNode.IconData, in container: Container) -> SwiftUIViewCode {
        guard let shape = iconOutline(data) else {
            let library = data.library.map { value in
                value.literalValue.map { "the icon library \(SwiftUILiteral.string($0))" } ?? "icon library variables"
            } ?? "an icon with no library"
            var view = SwiftUIViewCode(head: "Color.clear")
            view.modifiers += frameModifiers(
                width: dimension(declaredSizing(node, axis: .width), in: container, empty: true),
                height: dimension(declaredSizing(node, axis: .height), in: container, empty: true),
                alignment: .center
            )
            warnUnemitted(node, [library])
            return view
        }
        return filledShape(node, shape: shape, fills: data.fills, stroke: nil, effects: data.effects, in: container, unemitted: [])
    }

    /// An icon's glyph as a shape, or `nil` when its library has no bundled font or its
    /// library or name is a variable.
    func iconOutline(_ data: PenNode.IconData) -> Outline? {
        guard let library = data.library?.literalValue, let name = data.icon?.literalValue,
              let file = SwiftUIEmitter.iconFontFiles(for: library).first?.lastPathComponent
        else { return nil }
        let registry = PenIconFontRegistry.shared
        guard let glyph = (registry.resolve(family: library, name: name) ?? registry.placeholder(family: library))?.codepoint else {
            return nil
        }
        var arguments = ["file: \(SwiftUILiteral.string(file))", "glyph: 0x\(String(glyph, radix: 16, uppercase: true))"]
        if library.hasPrefix(Self.variableWeightPrefix) {
            let weight = data.weight?.literalValue ?? Self.defaultIconWeight
            arguments.append("weight: \(SwiftUILiteral.number(weight))")
        }
        let view = "PenIconShape(\(arguments.joined(separator: ", ")))"
        return Outline(view: view, argument: view)
    }

    /// The libraries whose font has a weight axis the node's `weight` sets.
    private static let variableWeightPrefix = "Material Symbols"

    /// The weight Pen draws a Material Symbols icon at when the node sets none.
    private static let defaultIconWeight = 200.0
}
