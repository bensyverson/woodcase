//
//  PenTextLayoutSample.swift
//  Woodcase
//

import Foundation

/// A text, a style and a box that exercise every case of text layout an editor meets: the
/// shared fixture for anyone who checks their text against ``PenTextLayout``.
///
/// Woodcase's own geometry tests run on these, and so do Penumbra's contract test (a caret
/// rect and a hit-test invert each other) and RapidPro's adoption test (its line origins
/// equal the layout's). They live in the library rather than in a test bundle so that every
/// consumer reaches the same values by importing Woodcase — a copy in each repo would drift.
/// Each sets in the default face, SF Pro, which every Apple platform has, so no font needs
/// registering.
public struct PenTextLayoutSample: Friendly {
    /// The sample's name, for test output.
    public var name: String

    /// The text.
    public var text: String

    /// Its style.
    public var style: PenTextStyle

    /// The box it is placed in.
    public var box: PenSize

    /// Creates a sample.
    ///
    /// - Parameters:
    ///   - name: Its name.
    ///   - text: The text.
    ///   - style: Its style.
    ///   - box: The box it is placed in.
    public init(name: String, text: String, style: PenTextStyle, box: PenSize) {
        self.name = name
        self.text = text
        self.style = style
        self.box = box
    }

    /// The multi-line text: a paragraph that wraps, a hard newline, a blank line, clusters
    /// that are more than one UTF-16 unit — a combining accent, a surrogate pair and an
    /// emoji ZWJ sequence — and a trailing newline.
    public static let multiLineText = "Pen sets this paragraph so that it wraps across several lines.\n"
        + "A hard break, then cafe\u{301}, \u{1D4B3} and \u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F467} together.\n"
        + "\nLast line\n"

    /// ``multiLineText`` in a 180 × 240 box, set left, centered, right and justified, with
    /// natural and explicit line heights and every vertical alignment.
    public static let multiLine: [PenTextLayoutSample] = [
        sample("left", PenTextStyle(textAlign: .left)),
        sample("center", PenTextStyle(lineHeight: 1.5, textAlign: .center, textAlignVertical: .middle)),
        sample("right", PenTextStyle(textAlign: .right, textAlignVertical: .bottom)),
        sample("justify", PenTextStyle(lineHeight: 1.25, textAlign: .justify)),
    ]

    /// An empty text in the same box, centered both ways: its one caret line.
    public static let empty = PenTextLayoutSample(
        name: "empty", text: "",
        style: PenTextStyle(textAlign: .center, textAlignVertical: .middle),
        box: PenSize(width: 180, height: 240)
    )

    /// ``multiLineText`` in `style`, in the multi-line box.
    private static func sample(_ name: String, _ style: PenTextStyle) -> PenTextLayoutSample {
        PenTextLayoutSample(name: name, text: multiLineText, style: style, box: PenSize(width: 180, height: 240))
    }
}
