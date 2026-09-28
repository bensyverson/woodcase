//
//  SwiftUIEmitter+Slots.swift
//  Woodcase
//

extension SwiftUIEmitter {
    /// The struct's generic clause for `slots` — `<HeaderContent: View, FooterContent: View>`
    /// — or nothing for a component without any.
    static func genericClause(_ slots: [SwiftUISlot]) -> String {
        slots.isEmpty ? "" : "<" + slots.map { "\($0.genericName): View" }.joined(separator: ", ") + ">"
    }

    /// What a component with slots declares after its struct: the constrained init that
    /// passes every slot its default, and the view that draws each slot's own children.
    ///
    /// ```swift
    /// extension Card where Content == CardContentDefault {
    ///     public init(title: String = "Card title") {
    ///         self.init(title: title, content: { CardContentDefault() })
    ///     }
    /// }
    ///
    /// public struct CardContentDefault: View { … }
    /// ```
    ///
    /// `parameters` are the init's others — the props' and the control's — which the
    /// constrained init takes as they are and forwards. The defaults are drawn by
    /// `emitter`, whose shapes the file declares; their reads of the theme are their own.
    static func slotLines(
        _ component: SwiftUIComponent, parameters: [String], emitter: SwiftUINodeEmitter, scope: SwiftUIComponentScope
    ) -> [String] {
        let slots = component.slots
        guard !slots.isEmpty else { return [] }
        let type = component.typeName
        let constraints = slots.map { "\($0.genericName) == \($0.defaultType)" }.joined(separator: ", ")
        let forwarded = parameters.map { parameter in
            let label = parameter.prefix { $0 != ":" }
            return "\(label): \(label)"
        } + slots.map { "\($0.name): { \($0.defaultCall) }" }
        var lines = [
            "extension \(type) where \(constraints) {",
            "    /// A `\(type)` with \(slots.count == 1 ? "its slot's" : "each slot's") default content, as the component draws it.",
            "    public init(\(parameters.joined(separator: ", "))) {",
            "        self.init(\(forwarded.joined(separator: ", ")))",
            "    }",
            "}",
            "",
        ]
        var emitter = emitter
        emitter.scope = scope.drawing(component)
        for slot in slots {
            guard let name = slot.defaultTypeName else { continue }
            let mark = emitter.themeReads.count
            let views = slot.defaultContent.compactMap { emitter.view(for: $0, in: slot.container) }
            let readsTheme = emitter.themeReads.count > mark
            // The default is its own struct: its reads are not the component's.
            emitter.themeReads.rollBack(to: mark)
            let label = SwiftUILiteral.string(slot.frame.common.name ?? slot.frame.id)
            lines += [
                "/// The default content of the \(label) slot of `\(type)`: what it draws until a caller fills it.",
                "public struct \(name): View {",
            ]
            if readsTheme {
                lines += ["    @Environment(\\.penTheme) private var theme", ""]
            }
            lines += ["    public init() {}", "", "    public var body: some View {"]
            lines += views.isEmpty ? ["        EmptyView()"] : views.flatMap { $0.lines(indent: 2) }
            lines += ["    }", "}", ""]
        }
        return lines
    }
}
