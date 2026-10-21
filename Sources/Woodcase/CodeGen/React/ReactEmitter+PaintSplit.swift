//
//  ReactEmitter+PaintSplit.swift
//  Woodcase
//

extension ReactEmitter {
    /// A paint stack split where a CSS background stops being able to draw it: at the first
    /// cropped image paint (``ReactEmitter/isCroppedImage(_:)``), or the first enabled paint
    /// at linear dodge above another (``needsOwnElement(_:)``).
    ///
    /// The paints beneath it stay the element's own background, as before. That paint and
    /// every paint above it are drawn by elements of their own, laid over that background in
    /// order (``ReactEmitter/FillLayer``), so a crop keeps Pen's stacking: over the fills
    /// beneath it, under the fills above it.
    struct PaintSplit: Friendly {
        /// The paints the element's own background draws, bottom first.
        var background: [PenFill]
        /// The paints drawn as layers over it, bottom first: empty when nothing is cropped.
        var layered: [PenFill]

        /// Splits `fills`, bottom first as .pen lists them.
        init(_ fills: [PenFill]) {
            let lowest = fills.firstIndex(where: \.isEnabled) ?? fills.endIndex
            let first = fills.indices.first { index in
                ReactEmitter.isCroppedImage(fills[index]) || index > lowest && Self.needsOwnElement(fills[index])
            } ?? fills.endIndex
            background = Array(fills[..<first])
            layered = Array(fills[first...])
        }

        /// Splits a node's `fills`.
        init(_ fills: PenFills?) {
            self.init(fills?.all ?? [])
        }

        /// Whether `fill` blends in a way only an element of its own can: linear dodge, whose
        /// add is `mix-blend-mode: plus-lighter` (``mixBlendModeToCSSValue(_:)``), which
        /// `background-blend-mode` does not take.
        static func needsOwnElement(_ fill: PenFill) -> Bool {
            fill.isEnabled && fill.blendMode == .linearDodge
        }

        /// The background paints as a fill list, or `nil` when there are none.
        var backgroundFills: PenFills? {
            background.isEmpty ? nil : .multiple(background)
        }
    }
}
