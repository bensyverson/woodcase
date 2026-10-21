//
//  FigmaImagePlaceholder.swift
//  Woodcase
//

/// The gray fill that stands in for a Figma image whose bytes are not to hand.
///
/// The clipboard carries an image's hash, never its bytes. ``FigmaImporter`` puts this fill
/// in an image paint's place when ``FigmaImportOptions/imageURLs`` names no URL for its hash,
/// and reports a ``FigmaImportLoss/Feature/imageNotEmbedded`` loss treated as a
/// ``FigmaImportLoss/Treatment/placeholder``. A caller that named a URL and then failed to
/// fetch the bytes (``FigmaImageFetcher``) swaps the image fill for the same placeholder
/// with ``fill(replacing:)``, so both routes draw alike.
public enum FigmaImagePlaceholder {
    /// The placeholder's color, opaque, as Pen's `#RRGGBBAA`: a neutral mid-light gray,
    /// light enough to read as empty and dark enough to show on white.
    public static let gray = "#C4C4C4FF"

    /// The placeholder as a color fill carrying an image paint's own settings.
    ///
    /// - Parameters:
    ///   - enabled: The paint's visibility; `nil` is visible.
    ///   - blendMode: The paint's blend mode; `nil` is normal.
    ///   - opacity: The paint's opacity, baked into the gray's alpha (Pen carries a color
    ///     fill's opacity only there).
    /// - Returns: The fill.
    public static func fill(enabled: PenValue<Bool>? = nil, blendMode: PenBlendMode? = nil, opacity: Double = 1) -> PenFill.PenColorFill {
        let color = FigmaColor(red: 0xC4 / 255, green: 0xC4 / 255, blue: 0xC4 / 255, alpha: 1)
        return PenFill.PenColorFill(enabled: enabled, blendMode: blendMode, color: .literal(color.hex(opacity: opacity)))
    }

    /// The placeholder in place of an image fill, keeping its visibility, blend mode and
    /// opacity.
    ///
    /// - Parameter image: The image fill to replace. An opacity that is not a literal
    ///   (bound to a variable) cannot be baked into a color, and is dropped.
    /// - Returns: The fill.
    public static func fill(replacing image: PenFill.PenImageFill) -> PenFill.PenColorFill {
        let opacity: Double = if case let .literal(value)? = image.opacity { value } else { 1 }
        return fill(enabled: image.enabled, blendMode: image.blendMode, opacity: opacity)
    }
}
