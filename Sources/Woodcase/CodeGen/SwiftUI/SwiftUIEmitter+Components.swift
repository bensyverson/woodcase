//
//  SwiftUIEmitter+Components.swift
//  Woodcase
//

extension SwiftUIEmitter {
    /// The source of one component: a public view struct with a `public let` per prop,
    /// a public memberwise init whose defaults are what the component draws, and a body
    /// that reads the props where the component's text and paints do.
    ///
    /// ```swift
    /// public struct Card: View {
    ///     public let label: String
    ///
    ///     public init(label: String = "Total") {
    ///         self.label = label
    ///     }
    ///
    ///     public var body: some View { … Text(label) … }
    /// }
    /// ```
    ///
    /// A slot frame is a generic `@ViewBuilder` parameter, with its default content after the
    /// struct (``slotLines(_:parameters:emitter:scope:)``).
    ///
    /// The body sizes its root as an instance is placed (``SwiftUINodeEmitter/Container/component``).
    /// A prop the body cannot read is left out with a warning. A component with a role or
    /// states is written by ``emitControl(_:control:scope:diagnostics:)`` instead.
    static func emitComponent(
        _ component: SwiftUIComponent, scope: SwiftUIComponentScope, diagnostics: PenDiagnosticCollector?
    ) -> String {
        let definition = component.definition
        let type = component.typeName
        warn(component, diagnostics: diagnostics)
        if let control = SwiftUIControl(definition) {
            return emitControl(component, control: control, scope: scope, diagnostics: diagnostics)
        }
        var emitter = SwiftUINodeEmitter(diagnostics: diagnostics)
        emitter.scope = scope.drawing(component)
        let body = emitter.view(for: definition.sourceNode, in: .component)
            ?? SwiftUIViewCode(head: "EmptyView()")
        let label = definition.sourceNode.common.name ?? definition.id
        var lines = header(type, source: "the \(SwiftUILiteral.string(label)) component")
        lines.append("public struct \(type)\(genericClause(component.slots)): View {")
        lines += declarations(component.props, slots: component.slots)
        lines.append("")
        let slots = slotLines(component, parameters: component.props.map(\.parameter), emitter: emitter, scope: scope)
        lines += bodyLines(body, emitter: emitter, specimens: specimens(of: component), trailer: slots)
        return lines.joined(separator: "\n") + "\n"
    }

    /// The props' and the slots' declarations, and the init that sets them.
    private static func declarations(_ props: [SwiftUIProp], slots: [SwiftUISlot]) -> [String] {
        guard !props.isEmpty || !slots.isEmpty else { return ["    public init() {}"] }
        var lines = props.map { "    public let \($0.name): \($0.swiftType)" } + slots.map(\.declaration)
        let parameters = props.map(\.parameter) + slots.map(\.parameter)
        lines.append("")
        lines.append("    public init(\(parameters.joined(separator: ", "))) {")
        lines += props.map(\.assignment) + slots.map(\.assignment)
        lines.append("    }")
        return lines
    }

    /// The component's warnings: props left out, defaults drawn clear, slots drawn as frames.
    private static func warn(_ component: SwiftUIComponent, diagnostics: PenDiagnosticCollector?) {
        let id = component.definition.id
        for prop in component.unbound {
            let target = prop.targetNodeID == nil ? "names no node" : "reads nothing SwiftUI can bind"
            diagnostics?.warn(
                "The prop \"\(prop.name)\" of \(component.typeName) \(target) (\(prop.path)); it is left out",
                stage: .codeGen, nodeID: id
            )
        }
        for prop in component.slotted {
            diagnostics?.warn(
                "The prop \"\(prop.name)\" of \(component.typeName) is read in a slot's default content, "
                    + "which a caller's content replaces (\(prop.path)); it is left out",
                stage: .codeGen, nodeID: id
            )
        }
        for refusal in component.refusedSlots {
            diagnostics?.warn(
                "SwiftUI draws the slot \(SwiftUILiteral.string(refusal.label)) of \(component.typeName) as a frame: "
                    + "\(refusal.reason); an instance that fills it is inlined",
                stage: .codeGen, nodeID: id
            )
        }
        if !component.unemitted.isEmpty {
            diagnostics?.warn(
                "SwiftUI does not emit \(component.unemitted.joined(separator: ", ")) yet",
                stage: .codeGen, nodeID: id
            )
        }
    }
}
