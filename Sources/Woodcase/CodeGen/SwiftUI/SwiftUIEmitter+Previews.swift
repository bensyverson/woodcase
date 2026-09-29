//
//  SwiftUIEmitter+Previews.swift
//  Woodcase
//

extension SwiftUIEmitter {
    /// One state a view can be drawn in, and the call that draws it pinned there.
    ///
    /// The `#Preview`s at the end of a view's file and the catalog's specimens are both
    /// written from these.
    struct Specimen: Friendly {
        /// The state's name — `pressed` — or `nil` for the view as it is called bare.
        var name: String?

        /// The call, a line each, modifiers indented one level: `["Continue()",
        /// "    .penControlState(.pressed)"]`.
        var call: [String]
    }

    /// The specimens of `component`: the bare call, and for a control every state a caller
    /// can pin, each framed to the component's own fixed size — its body only prefers that
    /// size (``SwiftUINodeEmitter/Dimension/ideal(_:)``), and a preview offers it a screen.
    static func specimens(of component: SwiftUIComponent) -> [Specimen] {
        let bare = SwiftUIControl(component.definition).map { specimens($0, type: component.typeName) }
            ?? [Specimen(name: nil, call: ["\(component.typeName)()"])]
        guard let frame = ownFrame(of: component.definition.sourceNode) else { return bare }
        return bare.map { specimen in
            var specimen = specimen
            specimen.call.insert("    \(frame)", at: 1)
            return specimen
        }
    }

    /// The `.frame` that sizes a component whose root is `root` as the document draws it:
    /// its fixed width and height; `nil` when it fixes neither.
    static func ownFrame(of root: PenNode) -> String? {
        let sizes: [(String, PenSizing)] = [("width", PenLayoutEngine.widthSizing(of: root)), ("height", PenLayoutEngine.heightSizing(of: root))]
        let arguments = sizes.compactMap { label, sizing -> String? in
            guard case let .fixed(value) = sizing else { return nil }
            return "\(label): \(SwiftUILiteral.number(value))"
        }
        return arguments.isEmpty ? nil : ".frame(\(arguments.joined(separator: ", ")))"
    }

    /// The bare call, and one per state of `control` that pins it.
    static func specimens(_ control: SwiftUIControl, type: String) -> [Specimen] {
        var specimens = [Specimen(name: nil, call: ["\(type)()"])]
        var seen: Set<String> = []
        for state in control.faces.map(\.state) + control.effects where seen.insert(state.name).inserted {
            guard let call = pinnedCall(state, control: control, type: type) else { continue }
            specimens.append(Specimen(name: state.name, call: call))
        }
        return specimens
    }

    /// A `#Preview` per specimen under the default theme, then again under each of the
    /// theme's other ``SwiftUITheme/variants``: `#Preview("pressed, mode: dark")`.
    static func previewLines(_ specimens: [Specimen], theme: SwiftUITheme?) -> [String] {
        var lines: [String] = []
        for variant in theme?.variants ?? [SwiftUITheme.Variant(name: nil, modifier: nil)] {
            for specimen in specimens {
                let name = [specimen.name, variant.name].compactMap(\.self).joined(separator: ", ")
                let call = specimen.call + (variant.modifier.map { ["    \($0)"] } ?? [])
                if !lines.isEmpty {
                    lines.append("")
                }
                lines.append(name.isEmpty ? "#Preview {" : "#Preview(\(SwiftUILiteral.string(name))) {")
                lines += call.map { "    \($0)" }
                lines.append("}")
            }
        }
        return lines
    }

    /// The call that draws `type` pinned in `state`, a line each, or `nil` when the bare call
    /// draws it.
    static func pinnedCall(_ state: StateDefinition, control: SwiftUIControl, type: String) -> [String]? {
        let identifier = SwiftUIProp.identifier(state.name)
        switch state.trigger {
        case .hover: return ["\(type)()", "    .penControlState(.hovered)"]
        case .pressed: return ["\(type)()", "    .penControlState(.pressed)"]
        case .focused: return ["\(type)()", "    .penControlState(.focused)"]
        case .disabled: return ["\(type)()", "    .disabled(true)"]
        case .attribute:
            if control.kind == .toggle, state.name == "off" { return ["\(type)(isOn: .constant(false))"] }
            guard control.cases.contains(identifier) else { return nil }
            return ["\(type)(\(control.enumProperty): .\(identifier))"]
        }
    }
}
