//
//  PenPostIt+Ink.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// The three inks a post-it is written in: only black or only white, at three alphas.
    ///
    /// Which one is the paper's call (Penumbra's notes design, decision 12): paper whose
    /// relative luminance is above ``Style/darkPaperLuminance`` takes ``Style/inkOnLight``,
    /// darker paper ``Style/inkOnDark``. An alpha rather than a gray lets the tint show
    /// through the ink, so every tint keeps its own cast.
    struct Ink: Friendly {
        /// The body text.
        public var primary: PenHexColor
        /// The author line, a card's header, chip and status, and a resolved note's body.
        public var secondary: PenHexColor
        /// A ticked checklist item's words and a list's bullets.
        public var tertiary: PenHexColor

        /// Creates an ink from its three colors.
        ///
        /// - Parameters:
        ///   - primary: The body text's.
        ///   - secondary: The labels'.
        ///   - tertiary: The quietest marks'.
        public init(primary: PenHexColor, secondary: PenHexColor, tertiary: PenHexColor) {
            self.primary = primary
            self.secondary = secondary
            self.tertiary = tertiary
        }

        /// The ink for a paper.
        ///
        /// - Parameters:
        ///   - paper: The color the ink is written on; its alpha is ignored.
        ///   - style: The look whose two inks and threshold are chosen between.
        public init(on paper: PenHexColor, style: Style = .standard) {
            self = paper.relativeLuminance > style.darkPaperLuminance ? style.inkOnLight : style.inkOnDark
        }
    }
}
