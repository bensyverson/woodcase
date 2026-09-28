//
//  RelativeAge.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// How long ago something happened, in the two spellings the page uses.
///
/// The viewer has no absolute times outside the activity feed's clock column: what a
/// person watching agents work wants to know is *how stale* a row is, and a wall-clock
/// time makes them do the subtraction.
///
/// ```swift
/// RelativeAge.text(from: event.time, to: Date(), style: .compact)  // "9m"
/// RelativeAge.text(from: event.time, to: Date(), style: .long)     // "9 min ago"
/// ```
public enum RelativeAge {
    /// Which spelling to use.
    ///
    /// Two, because they sit in different places: a table column has room for one
    /// number and one unit, and a file row is read as a sentence.
    public enum Style: String, Friendly {
        /// `4s`, `9m`, `1h`, `2d` — fits a fixed narrow column.
        case compact
        /// `just now`, `18 min ago`, `1 h ago`, `yesterday` — reads as prose.
        case long
    }

    /// How recently a row must have been touched to carry its editor's colour.
    ///
    /// Thirty seconds is the ruling's window: long enough to catch the edit you just
    /// heard about, short enough that the panel is not permanently striped.
    public static let recencyWindow: TimeInterval = 30

    /// Whether a time falls inside ``recencyWindow``.
    ///
    /// - Parameters:
    ///   - time: When it happened.
    ///   - now: The moment to measure against.
    /// - Returns: `true` while the row should still carry an identity colour.
    public static func isRecent(_ time: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(time)
        return age >= 0 && age < recencyWindow
    }

    /// The age of a moment, as text.
    ///
    /// - Parameters:
    ///   - time: When it happened.
    ///   - now: The moment to measure against.
    ///   - style: Which spelling to use.
    /// - Returns: The age. A time in the future reads as no age at all rather than as a
    ///   negative one: clocks disagree, and "-3s ago" is never the answer.
    public static func text(from time: Date, to now: Date = Date(), style: Style) -> String {
        let seconds = max(0, now.timeIntervalSince(time))
        return switch style {
        case .compact: compact(seconds)
        case .long: long(seconds)
        }
    }

    /// The compact spelling.
    private static func compact(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: "\(Int(seconds))s"
        case ..<3600: "\(Int(seconds / 60))m"
        case ..<86400: "\(Int(seconds / 3600))h"
        default: "\(Int(seconds / 86400))d"
        }
    }

    /// The long spelling.
    private static func long(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<10: "just now"
        case ..<60: "\(Int(seconds)) s ago"
        case ..<3600: "\(Int(seconds / 60)) min ago"
        case ..<86400: "\(Int(seconds / 3600)) h ago"
        case ..<172_800: "yesterday"
        default: "\(Int(seconds / 86400)) days ago"
        }
    }
}
