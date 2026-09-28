//
//  SwiftUINodeEmitter+SlotCall.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// The call to `component` that fills its slots: `arguments`, then a trailing closure
    /// per slot — the first unlabelled, the rest labelled by the slot's name — holding the
    /// instance's content for the slots in `fills`, by slot frame id, and the default
    /// content for the rest.
    ///
    /// ```swift
    /// Panel {
    ///     Text("Settings")
    /// } footer: {
    ///     PanelFooterDefault()
    /// }
    /// ```
    ///
    /// The content is drawn here, in the caller's scope, placed as the slot frame's stack
    /// places its children.
    func slotCall(_ component: SwiftUIComponent, arguments: [String], fills: [String: [PenNode]]) -> SwiftUIViewCode {
        let closures: [[SwiftUIViewCode]] = component.slots.map { slot in
            guard let fill = fills[slot.frame.id] else { return [SwiftUIViewCode(head: slot.defaultCall)] }
            return fill.compactMap { view(for: $0, in: slot.container) }
        }
        let head = arguments.isEmpty ? component.typeName : "\(component.typeName)(\(arguments.joined(separator: ", ")))"
        var call = SwiftUIViewCode(head: head, body: closures.first ?? [])
        call.trailingClosures = zip(component.slots.dropFirst(), closures.dropFirst()).map { slot, body in
            SwiftUIViewCode.TrailingClosure(label: slot.name, body: body)
        }
        return call
    }
}
