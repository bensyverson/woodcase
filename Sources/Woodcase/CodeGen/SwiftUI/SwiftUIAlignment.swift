//
//  SwiftUIAlignment.swift
//  Woodcase
//

/// A two-axis SwiftUI `Alignment`, built from Pen's per-axis choices.
struct SwiftUIAlignment: Friendly {
    /// Where content sits across the width.
    enum Horizontal: String, Friendly {
        case leading, center, trailing
    }

    /// Where content sits down the height.
    enum Vertical: String, Friendly {
        case top, center, bottom
    }

    /// The horizontal part.
    var horizontal: Horizontal

    /// The vertical part.
    var vertical: Vertical

    /// Centred on both axes: SwiftUI's default, which the emitter leaves unwritten.
    static let center = SwiftUIAlignment(horizontal: .center, vertical: .center)

    /// The `Alignment` spelling: `.topLeading`, `.bottom`, `.center`.
    var code: String {
        switch (vertical, horizontal) {
        case (.center, .center): ".center"
        case (.center, _): ".\(horizontal.rawValue)"
        case (_, .center): ".\(vertical.rawValue)"
        default: ".\(vertical.rawValue)\(horizontal.rawValue.prefix(1).uppercased())\(horizontal.rawValue.dropFirst())"
        }
    }

    /// Pen's `start`/`center`/`end` on the horizontal axis.
    static func horizontal(_ position: PenAlignItems) -> Horizontal {
        switch position {
        case .start: .leading
        case .center: .center
        case .end: .trailing
        }
    }

    /// Pen's `start`/`center`/`end` on the vertical axis.
    static func vertical(_ position: PenAlignItems) -> Vertical {
        switch position {
        case .start: .top
        case .center: .center
        case .end: .bottom
        }
    }
}
