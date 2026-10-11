//
//  PenPostIt.swift
//  Woodcase
//

import Foundation

/// Post-its: what Woodcase makes of a `note` node.
///
/// Every note is a post-it — a square on the canvas with a size, a tint and an author.
/// This namespace holds what the layout, the editing layer and the renderers agree on:
/// the size an unsized note takes, and the metadata convention that types its kind,
/// state, author and tint (see <doc:PenPostItConvention>).
///
/// ```swift
/// PenPostIt.layoutSizing(nil)          // .fixed(200)
/// PenPostIt.layoutSizing(.fixed(0))    // .fixed(200) — how Pen saves an unsized note
/// PenPostIt.layoutSizing(.fixed(120))  // .fixed(120)
/// ```
public enum PenPostIt {
    /// The width and height, in points, a note lays out at on an axis it does not size.
    public static let defaultSize: Double = 200

    /// The width, in points, a prompt or context lays out at when it does not size it: the
    /// rev 2 mockup's card.
    public static let cardDefaultWidth: Double = 240

    /// The height, in points, a prompt or context lays out at when it does not size it.
    public static let cardDefaultHeight: Double = 160

    /// The sizing a note lays out by on one axis, given the sizing it declares.
    ///
    /// An absent size, and any size that would settle at zero or less — a fixed value
    /// ≤ 0 (Pen saves an unsized note as `width: 0, height: 0`), or `fit_content` /
    /// `fill_container` with no positive fallback — lays out at ``defaultSize``. A
    /// `fill_container` keeps its meaning inside a layout parent and only gains the
    /// fallback; a `$variable` that did not resolve is left for the layout to settle.
    ///
    /// The default is applied in layout rather than written into the file, so `tree`,
    /// hit testing and the renderers read one rect and the file keeps what Pen wrote.
    ///
    /// A prompt or context takes the same rule with the card's size
    /// (``cardDefaultWidth``, ``cardDefaultHeight``) as its default.
    ///
    /// - Parameters:
    ///   - declared: The note's `width` or `height`, after variable resolution.
    ///   - defaultSize: The size an unsized axis takes; ``defaultSize`` for a note.
    /// - Returns: The sizing the layout engine uses on that axis.
    public static func layoutSizing(_ declared: PenSizing?, default defaultSize: Double = defaultSize) -> PenSizing {
        switch declared {
        case nil:
            .fixed(defaultSize)
        case let .fixed(value):
            value > 0 ? .fixed(value) : .fixed(defaultSize)
        case let .fitContent(fallback):
            .fitContent(fallback: positive(fallback) ?? defaultSize)
        case let .fillContainer(fallback):
            .fillContainer(fallback: positive(fallback) ?? defaultSize)
        case let .variable(name):
            .variable(name)
        }
    }

    /// Whether a note's declared size leaves the axis to ``defaultSize``.
    ///
    /// - Parameter declared: The note's `width` or `height`.
    /// - Returns: `true` when the axis is absent or a fixed value ≤ 0.
    public static func isUnsized(_ declared: PenSizing?) -> Bool {
        switch declared {
        case nil: true
        case let .fixed(value): value <= 0
        default: false
        }
    }

    /// A fallback that is above zero, or `nil`.
    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
