//
//  PenPostIt+Drawing.swift
//  Woodcase
//

import Foundation

extension PenPostIt {
    /// What one expansion is drawn with: the chrome's measures, the text measurer, the
    /// caller's words for the labels, its colors for identities, and how the body is drawn.
    ///
    /// Not ``Friendly``: it holds the caller's functions, and lives for one expansion.
    struct Drawing {
        /// The look's measures at the node's look scale and type size.
        let chrome: Chrome
        /// The layout's text measurer, for the chrome's labels.
        let measure: TextMeasurer
        /// The caller's words for the chrome's labels.
        let labels: (Label) -> String
        /// The caller's color for an identity, or `nil` to use its ``ActorColor``.
        let identityColors: (String) -> PenHexColor?
        /// Whether the body is styled from its markdown or drawn as written.
        let bodyText: BodyText

        /// The look.
        var style: Style {
            chrome.style
        }

        /// The color an identity is drawn in — its dot and its mention pills: the
        /// caller's, or the identity's ``ActorColor``.
        ///
        /// - Parameter name: The identity, as `woodcase.author` or an `@mention` spells it.
        /// - Returns: The color, opaque.
        func identityColor(for name: String) -> PenHexColor {
            identityColors(name) ?? ActorColor(name: name).color
        }

        /// A label as the caller spells it, with the look's ▶ before a prompt's header and
        /// the Run label — not before Cancel, which plays nothing.
        ///
        /// - Parameter label: The label.
        /// - Returns: The string drawn.
        func text(_ label: Label) -> String {
            switch label {
            case .promptTitle, .run: style.playGlyph + " " + labels(label)
            case .contextTitle, .cancel, .status: labels(label)
            }
        }
    }
}
