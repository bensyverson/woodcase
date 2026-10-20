//
//  FigmaWindingRule.swift
//  Woodcase
//

/// How a Figma fill decides which areas a self-overlapping outline covers.
///
/// The raw values are the case names of the schema's `WindingRule` enum, which a `Path`
/// message carries, so `FigmaWindingRule(rawValue: value.enumName)` reads one. A vector
/// network region stores its rule as a bit instead (``FigmaVectorNetwork/Region``).
public enum FigmaWindingRule: String, Friendly, CaseIterable {
    /// The nonzero rule: a point is inside when the outline winds around it at all.
    case nonzero = "NONZERO"
    /// The even-odd rule: a point is inside when a ray from it crosses the outline an odd
    /// number of times. Figma names it `ODD`; SVG writes `evenodd`.
    case evenOdd = "ODD"
}
