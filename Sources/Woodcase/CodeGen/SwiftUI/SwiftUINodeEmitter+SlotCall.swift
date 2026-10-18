//
//  SwiftUINodeEmitter+SlotCall.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// The call to `component` that fills its slots: `arguments`, then a trailing closure
    /// per slot — the first unlabeled, the rest labeled by the slot's name — holding the
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
    func slotCall(_ component: SwiftUIComponent, arguments: [String], fills: [String: [PenNode]]) -> SwiftUIPendingView<SwiftUIViewCode> {
        // Every filled slot's content, one after another; `nil` for a slot left at its default.
        let filled = component.slots.map { fills[$0.frame.id] }
        let requests = zip(component.slots, filled).flatMap { slot, fill in
            (fill ?? []).map { request(for: $0, in: slot.container) }
        }
        return views(requests).map { views in
            slotCall(component, arguments: arguments, filled: filled, views: views)
        }
    }

    /// The call of ``slotCall(_:arguments:fills:)``, from `views`: the content of each slot
    /// `filled` holds, in slot order.
    private func slotCall(
        _ component: SwiftUIComponent, arguments: [String], filled: [[PenNode]?], views: [SwiftUIViewCode?]
    ) -> SwiftUIViewCode {
        var next = 0
        let closures: [[SwiftUIViewCode]] = zip(component.slots, filled).map { slot, fill in
            guard let fill else { return [SwiftUIViewCode(head: slot.defaultCall)] }
            defer { next += fill.count }
            return views[next ..< next + fill.count].compactMap(\.self)
        }
        let head = arguments.isEmpty ? component.typeName : "\(component.typeName)(\(arguments.joined(separator: ", ")))"
        var call = SwiftUIViewCode(head: head, body: closures.first ?? [])
        call.trailingClosures = zip(component.slots.dropFirst(), closures.dropFirst()).map { slot, body in
            SwiftUIViewCode.TrailingClosure(label: slot.name, body: body)
        }
        return call
    }
}
