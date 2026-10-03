//
//  ReactEmitter+PaintSplit.swift
//  Woodcase
//

extension ReactEmitter {
    /// A paint stack split where a CSS background stops being able to draw it: at the first
    /// cropped image paint (``ReactEmitter/isCroppedImage(_:)``).
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
            let first = fills.firstIndex(where: ReactEmitter.isCroppedImage) ?? fills.endIndex
            background = Array(fills[..<first])
            layered = Array(fills[first...])
        }

        /// Splits a node's `fills`.
        init(_ fills: PenFills?) {
            self.init(fills?.all ?? [])
        }

        /// The background paints as a fill list, or `nil` when there are none.
        var backgroundFills: PenFills? {
            background.isEmpty ? nil : .multiple(background)
        }
    }
}
