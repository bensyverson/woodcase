//
//  SwiftUIStrokeAlignment.swift
//  Woodcase
//

/// A stroke's alignment as the support file's `PenStrokeAlignment` names it: SwiftUI's own
/// word for a stroke inside the outline is `strokeBorder`'s "inside".
enum SwiftUIStrokeAlignment: String, Friendly {
    /// Entirely inside the outline: Pen's `inner`.
    case inside

    /// Centered on the outline: Pen's `center`, and its default.
    case center

    /// Entirely outside the outline: Pen's `outer`.
    case outside

    /// The alignment Pen's `alignment` names.
    init(_ alignment: PenStrokeAlign) {
        self = switch alignment {
        case .inner: .inside
        case .center: .center
        case .outer: .outside
        }
    }
}
