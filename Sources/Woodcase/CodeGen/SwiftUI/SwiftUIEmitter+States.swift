//
//  SwiftUIEmitter+States.swift
//  Woodcase
//

extension SwiftUIEmitter {
    /// The source of a component with a role or states (``SwiftUIControl``): the view
    /// struct wraps its drawing in the control its role becomes, draws each state the
    /// designer drew as a private `…Face` property, spells each smart default as modifiers,
    /// and previews every state.
    ///
    /// ```swift
    /// public struct Continue: View {
    ///     public let action: () -> Void
    ///     …
    ///     public var body: some View {
    ///         Button(action: action) { face }
    ///             .buttonStyle(Style(view: self))
    ///     }
    ///
    ///     private var face: some View { … }
    ///     private var pressedFace: some View { … }
    ///
    ///     private struct Style: ButtonStyle {
    ///         let view: Continue
    ///         func makeBody(configuration: Configuration) -> some View {
    ///             PenStateReader(isPressed: configuration.isPressed) { state in
    ///                 Group { if state.contains(.pressed) { view.pressedFace } else { configuration.label } }
    ///                     .penFocusRing(state.contains(.focused), width: 2, offset: 2, cornerRadius: 10)
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    static func emitControl(
        _ component: SwiftUIComponent, control: SwiftUIControl, scope: SwiftUIComponentScope,
        diagnostics: PenDiagnosticCollector?
    ) -> String {
        let definition = component.definition
        let type = component.typeName
        warn(control, of: component, diagnostics: diagnostics)
        var emitter = SwiftUINodeEmitter(diagnostics: diagnostics)
        func draw(_ tree: PenNode, in treeScope: SwiftUIComponentScope) -> SwiftUIViewCode {
            emitter.scope = control.kind == .textField ? treeScope.typing(in: tree) : treeScope
            return emitter.view(for: tree, in: .component) ?? SwiftUIViewCode(head: "EmptyView()")
        }
        let face = draw(definition.sourceNode, in: scope.drawing(component))
        let faces = control.faces.map { ($0, draw($0.node, in: scope.drawing(component, face: $0.node))) }

        let label = definition.sourceNode.common.name ?? definition.id
        var lines = header(type, source: "the \(SwiftUILiteral.string(label)) component")
        lines.append("public struct \(type)\(genericClause(component.slots)): View {")
        if !control.enumLines.isEmpty {
            lines += control.enumLines + [""]
        }
        lines += memberLines(component.props, control: control, slots: component.slots)
        lines.append("")
        // The faces are properties of the struct, so a theme any face reads is the struct's.
        if emitter.themeReads.count > 0 {
            lines += ["    @Environment(\\.penTheme) private var theme", ""]
        }
        lines.append("    public var body: some View {")
        lines += controlBody(control, cornerRadius: cornerRadius(of: definition.sourceNode))
        lines.append("    }")
        lines += faceLines("face", doc: "The default state.", view: face)
        for (entry, view) in faces {
            let frame = SwiftUILiteral.string(entry.node.common.name ?? entry.node.id)
            let doc = "The \(SwiftUILiteral.string(entry.state.name)) state, as the \(frame) frame draws it."
            lines += faceLines(entry.property, doc: doc, view: view)
        }
        if control.kind.isStyled {
            lines.append("")
            lines += styleLines(control, type: type, cornerRadius: cornerRadius(of: definition.sourceNode))
        }
        lines += ["}", ""]
        let parameters = component.props.map(\.parameter) + control.members.compactMap(\.parameter)
        lines += slotLines(component, parameters: parameters, emitter: emitter, scope: scope)
        for declaration in emitter.shapes.declarations {
            lines.append(contentsOf: declaration.lines + [""])
        }
        lines += previewLines(specimens(control, type: type), theme: scope.theme)
        return lines.joined(separator: "\n") + "\n"
    }

    /// The props', the control's and the slots' declarations, and the init that sets them.
    private static func memberLines(_ props: [SwiftUIProp], control: SwiftUIControl, slots: [SwiftUISlot]) -> [String] {
        let members = control.members
        var lines = props.map { "    public let \($0.name): \($0.kind.swiftType)" }
        lines += members.map { "    \($0.declaration)" } + slots.map(\.declaration)
        let parameters = props.map(\.parameter) + members.compactMap(\.parameter) + slots.map(\.parameter)
        let assignments = props.map(\.assignment) + members.compactMap(\.assignment).map { "        \($0)" }
            + slots.map(\.assignment)
        lines.append("")
        guard !parameters.isEmpty else { return lines + ["    public init() {}"] }
        lines.append("    public init(\(parameters.joined(separator: ", "))) {")
        lines += assignments
        lines.append("    }")
        return lines
    }

    /// The body: the control around the default face, or, for a control without one, the
    /// states drawn in place.
    private static func controlBody(_ control: SwiftUIControl, cornerRadius: Double) -> [String] {
        switch control.kind {
        case .button:
            [
                "        Button(action: action) {",
                "            face",
                "        }",
                "        .buttonStyle(Style(view: self))",
            ]
        case .toggle:
            [
                "        Toggle(isOn: $isOn) {",
                "            EmptyView()",
                "        }",
                "        .toggleStyle(Style(view: self))",
            ]
        case .picker:
            [
                "        Menu {",
                "            Picker(selection: $selection) {",
                "                ForEach(options, id: \\.self) { option in",
                "                    Text(option)",
                "                        .tag(option)",
                "                }",
                "            } label: {",
                "                EmptyView()",
                "            }",
                "            .pickerStyle(.inline)",
                "        } label: {",
                "            face",
                "        }",
                "        .menuStyle(.button)",
                "        .menuIndicator(.hidden)",
                "        .buttonStyle(Style(view: self))",
            ]
        case .textField:
            stateLines(control, indent: 2, reader: "PenStateReader(isFocused: isFocused)", fallback: "face",
                       cornerRadius: cornerRadius) { $0 }
        case .tabBar:
            stateLines(control, indent: 2, reader: "PenStateReader", fallback: "face", cornerRadius: cornerRadius) { $0 }
                + ["        .accessibilityElement(children: .contain)", "        .accessibilityAddTraits(.isTabBar)"]
        case .plain:
            stateLines(control, indent: 2, reader: "PenStateReader", fallback: "face", cornerRadius: cornerRadius) { $0 }
        }
    }

    /// The nested style that draws a button's, a toggle's or a picker's states.
    private static func styleLines(_ control: SwiftUIControl, type: String, cornerRadius: Double) -> [String] {
        let (protocolName, what, reader, fallback) = switch control.kind {
        case .toggle: ("ToggleStyle", "toggle", "PenStateReader", "view.face")
        case .picker: ("ButtonStyle", "picker's label", "PenStateReader(isPressed: configuration.isPressed)", "configuration.label")
        default: ("ButtonStyle", "button", "PenStateReader(isPressed: configuration.isPressed)", "configuration.label")
        }
        var lines = [
            "    /// Draws the \(what) in each state: the designer's frame where there is one, the",
            "    /// smart default's effects for the rest.",
            "    private struct Style: \(protocolName) {",
            "        let view: \(type)",
            "",
            "        func makeBody(configuration: Configuration) -> some View {",
        ]
        lines += stateLines(control, indent: 3, reader: reader, fallback: fallback, cornerRadius: cornerRadius) { "view.\($0)" }
        if control.kind == .toggle {
            lines += ["            .onTapGesture {", "                configuration.isOn.toggle()", "            }"]
        }
        lines += ["        }", "    }"]
        return lines
    }

    /// The states drawn at `indent`: the face whose state holds — `fallback` when none
    /// does — with every smart default's modifiers, inside a reader when any of them
    /// depends on an interaction.
    private static func stateLines(
        _ control: SwiftUIControl, indent: Int, reader: String, fallback: String, cornerRadius: Double,
        member: (String) -> String
    ) -> [String] {
        let reads = control.readsState
        let level = reads ? indent + 1 : indent
        let pad = String(repeating: "    ", count: level)
        var lines: [String] = reads ? ["\(String(repeating: "    ", count: indent))\(reader) { state in"] : []
        if control.faces.isEmpty {
            lines.append("\(pad)\(fallback)")
        } else {
            lines.append("\(pad)Group {")
            for (index, face) in control.faces.enumerated() {
                let keyword = index == 0 ? "if" : "} else if"
                lines.append("\(pad)    \(keyword) \(control.condition(for: face.state, member: member)) {")
                lines.append("\(pad)        \(member(face.property))")
            }
            lines += ["\(pad)    } else {", "\(pad)        \(fallback)", "\(pad)    }", "\(pad)}"]
        }
        let modifierPad = control.faces.isEmpty ? pad + "    " : pad
        for state in control.effects {
            let condition = control.condition(for: state, member: member)
            for effect in state.effects {
                lines.append(modifierPad + effect.swiftUIModifier(when: condition, cornerRadius: cornerRadius))
            }
        }
        if reads {
            lines.append("\(String(repeating: "    ", count: indent))}")
        }
        return lines
    }

    /// A private face property drawing `view`.
    private static func faceLines(_ name: String, doc: String, view: SwiftUIViewCode) -> [String] {
        ["", "    /// \(doc)", "    private var \(name): some View {"] + view.lines(indent: 2) + ["    }"]
    }

    /// The uniform corner radius a focus ring follows, or 0.
    private static func cornerRadius(of node: PenNode) -> Double {
        let radius: PenCornerRadius? = switch node.kind {
        case let .frame(data): data.cornerRadius
        case let .rectangle(data): data.cornerRadius
        default: nil
        }
        guard case let .uniform(value)? = radius else { return 0 }
        return value.literalValue ?? 0
    }

    /// The control's warnings: designer states drawn as a smart default, and props whose
    /// names a control member takes.
    private static func warn(_ control: SwiftUIControl, of component: SwiftUIComponent, diagnostics: PenDiagnosticCollector?) {
        let id = component.definition.id
        for state in control.skipped {
            diagnostics?.warn(
                "SwiftUI draws the \"\(state.name)\" state of \(component.typeName) as its smart default: "
                    + "drawing its frame would make a new TextField, which drops the focus",
                stage: .codeGen, nodeID: id
            )
        }
        for prop in component.props where control.memberNames.contains(prop.name) {
            diagnostics?.warn(
                "The prop \"\(prop.name)\" of \(component.typeName) takes a name its \(control.kind.rawValue) needs; "
                    + "rename it in _props",
                stage: .codeGen, nodeID: id
            )
        }
    }
}
