//
//  PenTextMeasurer.swift
//  Woodcase
//

import CoreText
import Foundation

/// Measures text bounding boxes using Core Text's CTFramesetter.
///
/// Used by the layout engine to determine the intrinsic size of text nodes.
/// Defaults to SF Pro when no font family is specified.
public enum PenTextMeasurer {
    /// The default font family used when none is specified.
    public static let defaultFontFamily = "SF Pro"

    /// The default font size used when none is specified.
    public static let defaultFontSize: Double = 16

    /// Measures the bounding size of a plain text string with the given style properties.
    ///
    /// - Parameters:
    ///   - text: The string to measure.
    ///   - fontFamily: Font family name. Defaults to SF Pro.
    ///   - fontSize: Font size in points. Defaults to 16.
    ///   - fontWeight: CSS-style weight string (e.g. "bold", "700"). Defaults to "normal".
    ///   - fontStyle: CSS-style font style (e.g. "italic"). Defaults to "normal".
    ///   - letterSpacing: Additional spacing between characters in points. Defaults to 0.
    ///   - lineHeight: Line height as a multiplier of font size. Each line is set at the
    ///     pitch Pen sets it at, ``linePitch(lineHeight:fontSize:font:)``: this times the
    ///     font size rounded to a whole point, or with nil the font's natural line height.
    ///   - maxWidth: Maximum width for wrapping. Nil means single-line (no wrapping).
    /// - Returns: The bounding size (width, height) of the measured text.
    public static func measure(
        _ text: String,
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        fontWeight: String? = nil,
        fontStyle: String? = nil,
        letterSpacing: Double? = nil,
        lineHeight: Double? = nil,
        maxWidth: Double? = nil
    ) -> CGSize {
        guard !text.isEmpty else {
            return .zero
        }

        let resolvedFontSize = fontSize ?? defaultFontSize
        let font = resolveFont(
            family: fontFamily ?? defaultFontFamily,
            size: resolvedFontSize,
            weight: fontWeight ?? "normal",
            style: fontStyle ?? "normal"
        )

        var attributes: [(CFString, Any)] = [
            (kCTFontAttributeName, font),
        ]

        if let letterSpacing {
            attributes.append((kCTKernAttributeName, letterSpacing as CFNumber))
        }

        let lineHeightPoints = linePitch(lineHeight: lineHeight, fontSize: resolvedFontSize, font: font)
        attributes.append((kCTParagraphStyleAttributeName, paragraphStyle(lineHeight: lineHeightPoints)))

        let cfAttributes = Dictionary(uniqueKeysWithValues: attributes) as CFDictionary
        let attributedString = CFAttributedStringCreate(
            kCFAllocatorDefault,
            text as CFString,
            cfAttributes
        )!
        return measureCFAttributedString(attributedString, maxWidth: maxWidth, lineHeight: lineHeightPoints)
    }

    /// Measures a CFAttributedString, optionally constrained to a maximum width.
    ///
    /// - Parameters:
    ///   - attributedString: The text to measure.
    ///   - maxWidth: Maximum width for wrapping. Nil means no wrapping.
    ///   - lineHeight: The pitch every line is set at, when the string's paragraph style
    ///     fixes one. The height is then the number of lines times this — Pen's answer —
    ///     rather than Core Text's frame height, which rounds the first baseline and the
    ///     last descent separately and can come out a point taller (Inter at 14 pt: 18
    ///     for one 17-point line). Both the width and the line count then come from one
    ///     typesetting pass.
    /// - Returns: The bounding size, rounded up to whole points.
    public static func measureCFAttributedString(
        _ attributedString: CFAttributedString,
        maxWidth: Double? = nil,
        lineHeight: CGFloat? = nil
    ) -> CGSize {
        if let lineHeight {
            // One typesetting pass gives both the width and the line count.
            let block = typeset(attributedString, width: maxWidth.map { CGFloat($0) })
            return CGSize(width: ceil(block.width), height: ceil(CGFloat(block.lineCount) * lineHeight))
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let constraintSize = CGSize(
            width: maxWidth ?? CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        let fitSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            constraintSize,
            nil
        )
        // Ceil to avoid sub-pixel clipping
        return CGSize(width: ceil(fitSize.width), height: ceil(fitSize.height))
    }

    // MARK: - Font Resolution

    /// OpenType axis tag for `wght` (weight), encoded as a big-endian 32-bit integer.
    static let wghtAxisTag: Int = 0x7767_6874

    /// The `kCTFontOpticalSizeAttribute` value that turns automatic optical sizing off.
    ///
    /// Core Text moves a variable font's `opsz` axis to the point size on its own; Pen
    /// draws every size at the font's default optical size. Inter above 14 pt otherwise
    /// comes out in its tighter display cut — 3 pt narrower than Pen for two letters at
    /// 32 pt, 9 pt for a 56 pt word (`PenTextOpticalSizeTests`). The SwiftUI template's
    /// `PenFontFace` pins it the same way. ``defaultFontFamily`` is exempt: it is
    /// Woodcase's own fallback, not a face Pen draws, and SF Pro pinned to its default
    /// optical size sets small text in its display cut.
    static let opticalSizingOff = "none"

    /// Process-wide cache for ``resolveFont`` and ``hasWeightAxis``.
    ///
    /// Font resolution is expensive — `CTFontCopyVariationAxes` and
    /// `CGFontCopyTableForTag` dominate the profile of any text-heavy render.
    /// Repeated calls with the same style parameters return the same `CTFont`
    /// without re-reading the font tables.
    static let fontCache = FontResolutionCache()

    /// Resolves a CTFont from family name, size, weight string, and style string.
    ///
    /// If the requested font family is not available on the system, falls back
    /// to ``defaultFontFamily`` ("SF Pro") to ensure weight and style traits
    /// are applied correctly. A fallback is only correct for as long as the
    /// requested family stays absent, so the cached answer is tied to
    /// ``PenFontRegistry/generation`` and is discarded when fonts are
    /// registered.
    ///
    /// For variable fonts with a `wght` axis, the weight is applied via
    /// `kCTFontVariationAttribute` for precise control. For static fonts,
    /// the weight is applied via `kCTFontWeightTrait`. Optical sizing is off at
    /// every size, as Pen draws it, except in the fallback family (``opticalSizingOff``).
    public static func resolveFont(
        family: String,
        size: Double,
        weight: String,
        style: String
    ) -> CTFont {
        resolveFont(family: family, size: size, weight: weight, style: style, cache: fontCache)
    }

    /// ``resolveFont(family:size:weight:style:)`` against a specific cache.
    ///
    /// - Parameter cache: The resolution cache to consult and fill. Production
    ///   always passes the process-wide ``fontCache``; a test passes its own
    ///   instance so its hit/miss accounting is not shared with other suites
    ///   running in parallel.
    static func resolveFont(
        family: String,
        size: Double,
        weight: String,
        style: String,
        cache: FontResolutionCache
    ) -> CTFont {
        let cacheKey = FontResolutionCache.Key(
            family: family, size: size, weight: weight, style: style
        )
        if let cached = cache.font(for: cacheKey) {
            return cached
        }
        let (font, generation) = resolveFontUncached(
            family: family, size: size, weight: weight, style: style, cache: cache
        )
        cache.setFont(font, for: cacheKey, resolvedAt: generation)
        return font
    }

    /// Resolves a font without consulting the cache.
    ///
    /// The whole body runs inside ``FontRegistryGate``: every `CTFont…` call below
    /// reaches Core Text's font registry, which is a blocking synchronous XPC round
    /// trip to `fontd`. Several of those at once exhaust the cooperative thread pool
    /// and hang the process — see the gate's own documentation.
    ///
    /// - Parameters:
    ///   - family: The requested family name; the default family stands in when it is
    ///     not installed.
    ///   - size: The point size.
    ///   - weight: A CSS-style weight: a `wght` axis value on a variable face, and on a
    ///     static family the cut CSS font matching picks (``PenFaceMatching``).
    ///   - style: `"italic"` selects the italic trait; anything else does not.
    ///   - cache: The cache whose weight-axis answers to reuse.
    /// - Returns: The resolved font, and the registration generation it was resolved
    ///   under — read *inside* the gate, as close to the Core Text call as it can be,
    ///   so a registration that landed while this thread was queued counts as having
    ///   happened before the resolution it actually did affect.
    private static func resolveFontUncached(
        family: String,
        size: Double,
        weight: String,
        style: String,
        cache: FontResolutionCache
    ) -> (font: CTFont, generation: Int) {
        FontRegistryGate.withAccess {
            let generation = PenFontRegistry.generation
            let font = resolveFontThroughTheRegistry(
                family: family, size: size, weight: weight, style: style, cache: cache
            )
            return (font, generation)
        }
    }

    /// ``resolveFontUncached(family:size:weight:style:cache:)``, already inside the gate.
    ///
    /// - Parameters:
    ///   - family: The requested family name.
    ///   - size: The point size.
    ///   - weight: A CSS-style weight.
    ///   - style: `"italic"` selects the italic trait.
    ///   - cache: The cache whose weight-axis answers to reuse.
    /// - Returns: The resolved font.
    private static func resolveFontThroughTheRegistry(
        family: String,
        size: Double,
        weight: String,
        style: String,
        cache: FontResolutionCache
    ) -> CTFont {
        let isItalic = style.lowercased() == "italic"
        let resolvedFamily = fontFamilyAvailable(family) ? family : defaultFontFamily

        // Create a base font to inspect for variable font axes
        // Pen's faces at their default optical size; Woodcase's own fallback as Apple designs it.
        let opticalSizing: [CFString: Any] = resolvedFamily == defaultFontFamily
            ? [:] : [kCTFontOpticalSizeAttribute: opticalSizingOff]
        let baseFontDescAttrs = opticalSizing.merging([kCTFontFamilyNameAttribute: resolvedFamily]) { $1 }
        let baseDescriptor = CTFontDescriptorCreateWithAttributes(baseFontDescAttrs as CFDictionary)
        let baseFont = CTFontCreateWithFontDescriptor(baseDescriptor, size, nil)

        // Check if this is a variable font with a wght axis
        let font: CTFont
        if hasWeightAxis(baseFont, cache: cache) {
            let axisValue = mapWeightToAxisValue(weight)
            let variations: [Int: Double] = [wghtAxisTag: axisValue]
            let varAttrs = opticalSizing.merging([kCTFontVariationAttribute: variations]) { $1 }
            let varDescriptor = CTFontDescriptorCreateWithAttributes(varAttrs as CFDictionary)
            font = CTFontCreateCopyWithAttributes(baseFont, size, nil, varDescriptor)
        } else if let face = PenFaceMatching.descriptor(
            family: resolvedFamily, weight: mapWeightToAxisValue(weight), italic: isItalic
        ) {
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(face, opticalSizing as CFDictionary)
            font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        } else {
            font = baseFont
        }

        // Apply italic via CTFontCreateCopyWithSymbolicTraits if needed
        // Matching already picked a static family's italic cut when it has one.
        if isItalic, !CTFontGetSymbolicTraits(font).contains(.traitItalic) {
            if let italicFont = CTFontCreateCopyWithSymbolicTraits(
                font, size, nil,
                .traitItalic, .traitItalic
            ) {
                return italicFont
            }
        }

        return font
    }

    /// Returns whether the given font has a `wght` variation axis.
    ///
    /// Results are cached by PostScript name because
    /// `CTFontCopyVariationAxes` + `CGFontCopyTableForTag` are the hottest
    /// frames during text rasterization — the same font gets reinterrogated
    /// for every glyph run otherwise.
    static func hasWeightAxis(_ font: CTFont, cache: FontResolutionCache = PenTextMeasurer.fontCache) -> Bool {
        let psName = CTFontCopyPostScriptName(font) as String
        if let cached = cache.hasWeightAxis(forPostScriptName: psName) {
            return cached
        }
        let (result, generation): (Bool, Int) = FontRegistryGate.withAccess {
            let generation = PenFontRegistry.generation
            guard let axes = CTFontCopyVariationAxes(font) as? [[CFString: Any]] else {
                return (false, generation)
            }
            let hasAxis = axes.contains { axis in
                (axis[kCTFontVariationAxisIdentifierKey] as? Int) == wghtAxisTag
            }
            return (hasAxis, generation)
        }
        cache.setHasWeightAxis(result, forPostScriptName: psName, resolvedAt: generation)
        return result
    }

    /// Returns true if the given font family name is available on the system.
    ///
    /// Gated by ``FontRegistryGate``: asking whether a family exists is a blocking
    /// synchronous XPC round trip to `fontd`, and several at once hang the process.
    ///
    /// - Parameter family: The family name to look for.
    /// - Returns: `true` when Core Text resolves that exact family rather than a
    ///   fallback.
    static func fontFamilyAvailable(_ family: String) -> Bool {
        FontRegistryGate.withAccess {
            let descriptor = CTFontDescriptorCreateWithAttributes(
                [kCTFontFamilyNameAttribute: family] as CFDictionary
            )
            let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
            let resolvedFamily = CTFontCopyFamilyName(font) as String
            return resolvedFamily.lowercased() == family.lowercased()
        }
    }

    /// Maps a CSS-style font weight string to a `wght` variation axis value (100–900).
    ///
    /// This is used for variable fonts where the weight is set via the OpenType
    /// `wght` axis rather than Core Text weight traits. The reading itself is
    /// ``PenFontWeight/cssWeight(_:)``, shared with the SwiftUI emitter.
    public static func mapWeightToAxisValue(_ weight: String) -> Double {
        PenFontWeight.cssWeight(weight)
    }
}
