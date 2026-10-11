//
//  PenTextStyle+Runs.swift
//  Woodcase
//

import Foundation

public extension PenTextStyle {
    /// This style with a run's character keys over it: family, size, weight, italic,
    /// underline and strikethrough where the run sets them. Line height, letter spacing and
    /// alignment stay this style's — they belong to the paragraph, not to a run.
    ///
    /// - Parameter run: The run.
    /// - Returns: The style its characters are set in.
    func applying(_ run: PenTextRun) -> PenTextStyle {
        var style = self
        style.fontFamily = run.fontFamily ?? fontFamily
        style.fontSize = run.fontSize ?? fontSize
        style.fontWeight = run.fontWeight ?? fontWeight
        style.isItalic = run.isItalic ?? isItalic
        style.underline = run.underline ?? underline
        style.strikethrough = run.strikethrough ?? strikethrough
        return style
    }

    /// Partitions `text` into stretches of one style each: the one place runs are resolved
    /// over a node's style.
    ///
    /// Each run is clamped to the text and its edges widened outward to grapheme-cluster
    /// boundaries, so no character's glyphs are split between faces; a run that is then
    /// empty sets nothing. Where runs overlap, a later run's keys win. Stretches no run
    /// covers are this style, with no fill of their own. A stretch carries the mention of
    /// the last run covering it that has one (``PenTextRun/mention``). Adjacent stretches may resolve
    /// to the same style; they are not merged.
    ///
    /// - Parameters:
    ///   - text: The text.
    ///   - runs: Its runs, offsets in UTF-16 code units.
    /// - Returns: The segments, in order, covering the whole text; none for an empty text.
    func segments(of text: String, runs: [PenTextRun]) -> [PenTextSegment] {
        let length = text.utf16.count
        guard length > 0 else { return [] }
        let graphemes = text.graphemeBoundariesInUTF16
        let snapped: [(range: Range<Int>, run: PenTextRun)] = runs.compactMap { run in
            let lower = graphemes.last { $0 <= min(max(run.start, 0), length) } ?? 0
            let upper = graphemes.first { $0 >= min(max(run.end, 0), length) } ?? length
            return lower < upper ? (lower ..< upper, run) : nil
        }
        let edges = Set([0, length] + snapped.flatMap { [$0.range.lowerBound, $0.range.upperBound] }).sorted()
        return zip(edges, edges.dropFirst()).map { lower, upper in
            var style = self
            var fill: PenHexColor?
            var mention: String?
            for (range, run) in snapped where range.lowerBound <= lower && range.upperBound >= upper {
                style = style.applying(run)
                fill = run.fill ?? fill
                mention = run.mention ?? mention
            }
            return PenTextSegment(range: lower ..< upper, style: style, fill: fill, mention: mention)
        }
    }
}
