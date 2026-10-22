//
//  PenImageLoadingPlaceholder.swift
//  Woodcase
//

/// The quiet gray an image fill draws while its image is not to hand — still downloading
/// into the bundle, or missing — so the layer's shape shows while it loads.
///
/// Every renderer draws it, so a missing image looks the same everywhere: Woodcase's CG
/// renderer (``PenRenderer``) and RapidPro read this one constant. It fills the fill's clip
/// — the shape, the stroke band or the glyphs — with the fill's own opacity and blend mode.
/// An image fill naming no image, or a disabled one, still draws nothing.
///
/// It is a translucent mid-gray rather than an opaque light one because a design's own
/// colors, not the editor's appearance, sit behind it: over white it composites to about
/// `#E6E6E6`, lighter than the failed-download placeholder (``FigmaImagePlaceholder/gray``,
/// `#C4C4C4`) so a loading image never reads as a failed one, and over a dark design it
/// still shows as a slightly lighter patch.
public enum PenImageLoadingPlaceholder {
    /// The gray, as `#80808033`: sRGB mid-gray at 20 % opacity.
    public static let color = PenHexColor(red: 0x80, green: 0x80, blue: 0x80, alpha: 0x33)
}
