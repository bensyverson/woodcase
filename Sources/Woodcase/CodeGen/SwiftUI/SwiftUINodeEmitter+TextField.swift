//
//  SwiftUINodeEmitter+TextField.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// A text input's text as its `TextField`: the text node drawn as ``text(_:data:in:)``
    /// draws it, the copy become the prompt in the text's colour, bound to the component's
    /// `text` and focused by its `isFocused`.
    ///
    /// The field fills the room its row gives it, where the text sized to its copy.
    func textField(_ node: PenNode, data: PenNode.TextData, in container: Container) -> SwiftUIViewCode {
        var view = text(node, data: data, in: container)
        let style = view.modifiers.first { $0.call.hasPrefix(".foregroundStyle(") && $0.content == nil }?.call ?? ""
        view.head = "TextField(\"\", text: $text, prompt: \(view.head)\(style))"
        view.modifiers.removeAll { $0.call == ".fixedSize()" }
        view.modifiers.insert(contentsOf: [
            SwiftUIViewCode.Modifier(".textFieldStyle(.plain)"),
            SwiftUIViewCode.Modifier(".focused($isFocused)"),
        ], at: 0)
        return view
    }
}
