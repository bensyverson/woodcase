//
//  FillBox.swift
//  Woodcase
//

/// A fill's box as an emitter knows it: each side is `nil` unless it is fixed.
///
/// Codegen does not run layout, so a `fit_content` or `fill_container` side is only
/// known when the emitted code runs; a decision that needs the box's proportions (a
/// mesh raster's size, say) has to work from what is fixed.
struct FillBox: Friendly {
    /// The box's width, when fixed.
    var width: Double?

    /// The box's height, when fixed.
    var height: Double?

    /// A box whose size is only known at layout time.
    static let unknown = FillBox()

    /// Creates a box from explicit sides.
    init(width: Double? = nil, height: Double? = nil) {
        self.width = width
        self.height = height
    }

    /// Creates a box from a node's sizing, keeping only fixed sides.
    init(width: PenSizing?, height: PenSizing?) {
        self.init(width: width?.fixedValue, height: height?.fixedValue)
    }
}
