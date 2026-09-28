//
//  StateEffect+SwiftUI.swift
//  Woodcase
//

extension StateEffect {
    /// The effect as one SwiftUI modifier that takes effect while `condition` holds and is
    /// the identity otherwise, so every state's modifiers can sit in one chain.
    ///
    /// A dim is `colorMultiply`, the colour multiply CSS's `brightness` is; a scale is
    /// `scaleEffect` about the centre; a fade is `opacity`; a focus ring is the support
    /// file's `penFocusRing`, which follows the component's `cornerRadius` as an outline
    /// does; ignoring the pointer is `allowsHitTesting(false)`.
    func swiftUIModifier(when condition: String, cornerRadius: Double) -> String {
        switch self {
        case let .dim(brightness):
            ".colorMultiply(Color(white: \(condition) ? \(SwiftUILiteral.number(brightness)) : 1))"
        case let .scale(factor):
            ".scaleEffect(\(condition) ? \(SwiftUILiteral.number(factor)) : 1)"
        case let .fade(opacity):
            ".opacity(\(condition) ? \(SwiftUILiteral.number(opacity)) : 1)"
        case let .focusRing(width, offset):
            ".penFocusRing(\(condition), width: \(SwiftUILiteral.number(width)), offset: \(SwiftUILiteral.number(offset)), "
                + "cornerRadius: \(SwiftUILiteral.number(cornerRadius)))"
        case .ignoresPointer:
            ".allowsHitTesting(!\(condition.contains(" ") ? "(\(condition))" : condition))"
        }
    }
}
