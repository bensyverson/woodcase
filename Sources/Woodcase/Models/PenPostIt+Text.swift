//
//  PenPostIt+Text.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// The space between a note's edges and its text, in points: 14 on every side, as
    /// the rev 2 mockup pads a post-it.
    ///
    /// The chrome — a note's author line, a card's header and run row — adds to them
    /// (``bodyInsets(of:style:)``); the layout grows a note by its text's height plus those
    /// insets, and the expansion sets the text in the box they leave
    /// (``textFrame(of:width:height:style:)``), so the two agree on where the text ends.
    static let textInsets = PenPadding.Edges(top: 14, right: 14, bottom: 14, left: 14)

    /// The size a note's, prompt's or context's text is set at when nothing sets one: 13
    /// points, as the rev 2 mockup sets a post-it.
    static let defaultFontSize: Double = 13

    /// The line height a note's, prompt's or context's text takes when nothing sets one: 1.35
    /// times its size, as the rev 2 mockup sets a post-it.
    static let defaultLineHeight = 1.35
}
