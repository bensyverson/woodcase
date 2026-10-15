//
//  PenStrokeDash.swift
//  Woodcase
//

import Foundation

/// The dash a stroke is drawn with: alternating dash and gap lengths, and how far into
/// them the stroke starts.
///
/// The format has had no dash since 2.17, so a dash lives in two `metadata.woodcase` keys
/// (Ben's ruling, 2026-10-14): ``PenMetadata/WoodcaseKey/strokeDash``, the lengths, and
/// ``PenMetadata/WoodcaseKey/strokeDashOffset``, the phase. Pen keeps both and draws the
/// stroke solid. ``PenNode/strokeDash`` reads them as every Woodcase target draws them.
///
/// The lengths alternate dash, gap, dash, … in points, as SVG's `stroke-dasharray` and
/// CoreGraphics' `setLineDash` read them, so an odd count repeats: `[8, 4, 2, 4]` is a
/// dash-dot, and `[0, 6]` with round caps a row of dots. The dashes flow continuously round
/// the whole outline from where SVG starts each shape, clockwise on screen (see
/// <doc:PenRendering>).
///
/// ```swift
/// node.strokeDash  // PenStrokeDash(lengths: [8, 4], phase: 2)
/// ```
public struct PenStrokeDash: Friendly {
    /// The most lengths a dash may have: RapidPro's stroke shader holds sixteen, so a
    /// longer pattern is refused on a write and drawn solid from a file, on every target.
    public static let maximumLengths = 16

    /// What a written dash must be, as a refusal says it.
    public static let writtenForm =
        "an array of at most \(maximumLengths) non-negative lengths, not all zero, such as [8, 4]"

    /// Creates a dash.
    ///
    /// - Parameters:
    ///   - lengths: The alternating dash and gap lengths, in points.
    ///   - phase: How far into the pattern the stroke starts, in points.
    public init(lengths: [Double], phase: Double) {
        self.lengths = lengths
        self.phase = phase
    }

    /// The alternating dash and gap lengths, in points.
    public var lengths: [Double]

    /// How far into the pattern the stroke starts, in points: an offset of a dash's
    /// length makes the stroke open with the gap after it.
    public var phase: Double

    /// Why a written dash cannot be drawn.
    public enum Problem: Friendly {
        /// The value is not an array, or an element of it is not a number.
        case notNumbers
        /// A length is below zero, or not finite.
        case negativeLength
        /// Every length is zero, which would draw nothing at all.
        case allZero
        /// More lengths than ``PenStrokeDash/maximumLengths``.
        case tooManyLengths(Int)

        /// What a refusal or a finding says is wrong, mid-sentence.
        public var reason: String {
            switch self {
            case .notNumbers: "is not an array of numbers"
            case .negativeLength: "has a negative length"
            case .allZero: "has only zero lengths, which would draw nothing"
            case let .tooManyLengths(count):
                "has \(count) lengths, more than the \(PenStrokeDash.maximumLengths) every target can draw"
            }
        }
    }

    /// Why `value` cannot be drawn as a dash, or `nil` when it can. An empty array can: it
    /// is solid.
    ///
    /// - Parameter value: A `strokeDash` value as written.
    /// - Returns: The problem.
    public static func problem(in value: AnyCodable) -> Problem? {
        parse(value).problem
    }

    /// The lengths `value` writes, or `nil` when it is not a dash every target can draw.
    ///
    /// - Parameter value: A `strokeDash` value as written.
    /// - Returns: The lengths, possibly empty.
    public static func lengths(in value: AnyCodable) -> [Double]? {
        let read = parse(value)
        return read.problem == nil ? read.lengths : nil
    }

    // MARK: - Private

    /// Reads a written dash: its lengths, and what stops it being drawn, if anything.
    private static func parse(_ value: AnyCodable) -> (lengths: [Double], problem: Problem?) {
        guard case let .array(elements) = value else { return ([], .notNumbers) }
        var lengths: [Double] = []
        for element in elements {
            switch element {
            case let .int(number): lengths.append(Double(number))
            case let .double(number): lengths.append(number)
            default: return ([], .notNumbers)
            }
        }
        let problem: Problem? = if lengths.contains(where: { !$0.isFinite || $0 < 0 }) {
            .negativeLength
        } else if lengths.count > maximumLengths {
            .tooManyLengths(lengths.count)
        } else if !lengths.isEmpty, lengths.allSatisfy({ $0 == 0 }) {
            .allZero
        } else {
            nil
        }
        return (lengths, problem)
    }
}
