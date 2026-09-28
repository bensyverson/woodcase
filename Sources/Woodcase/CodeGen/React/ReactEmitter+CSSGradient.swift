//
//  ReactEmitter+CSSGradient.swift
//  Woodcase
//

extension ReactEmitter {
    /// A gradient fill as one CSS background layer: its image, and the tile that image is
    /// drawn in when the gradient's geometry needs one.
    ///
    /// A CSS gradient is laid out over its tile, so a tile other than the whole box is how
    /// the emitter states geometry the gradient functions cannot: a linear gradient whose
    /// slant follows the box's diagonal (``ReactEmitter/cssLinearGradient(_:stops:box:outsets:)``),
    /// or an SVG paint server grown past the box to reach a stroke's outer edge.
    struct CSSGradient: Friendly {
        /// The `background-image` value.
        var image: String

        /// The `background-size` value.
        var size: String = PaintLayer.fullSize

        /// The `background-position` value.
        var position: String = CSSGradient.centered

        /// Whether the image is an image with proportions of its own (an SVG paint server)
        /// rather than a gradient function, which CSS would draw at those proportions and
        /// repeat unless the tile is stated.
        var hasIntrinsicSize = false

        /// The position of a tile centred on the box.
        static let centered = "center"

        /// Whether the image fills the box as a bare gradient function does, needing no tile.
        var fillsBox: Bool {
            !hasIntrinsicSize && size == PaintLayer.fullSize && position == Self.centered
        }

        /// The layer as a `background` shorthand value: the bare image when it fills the
        /// box, else the image with its position, size and `no-repeat`.
        var backgroundLayer: String {
            fillsBox ? image : "\(image) \(position) / \(size) no-repeat"
        }
    }
}
