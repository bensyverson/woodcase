//
//  StateEffect+CSS.swift
//  Woodcase
//

extension StateEffect {
    /// The effect as CSS declarations, `(property, value)` in the order they are written.
    var cssDeclarations: [(property: String, value: String)] {
        switch self {
        case let .dim(brightness):
            [("filter", "brightness(\(ReactEmitter.cssNumber(brightness)))")]
        case let .scale(factor):
            [("transform", "scale(\(ReactEmitter.cssNumber(factor)))")]
        case let .fade(opacity):
            [("opacity", ReactEmitter.cssNumber(opacity))]
        case let .focusRing(width, offset):
            [
                ("outline", "\(ReactEmitter.cssNumber(width))px solid currentColor"),
                ("outline-offset", "\(ReactEmitter.cssNumber(offset))px"),
            ]
        case .ignoresPointer:
            [("pointer-events", "none")]
        }
    }
}
