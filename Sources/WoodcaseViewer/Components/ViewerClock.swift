//
//  ViewerClock.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The moment a page was rendered, and the zone its clock column reads in.
///
/// Every component that shows a time takes one of these rather than calling `Date()`
/// itself. Two reasons, and the second is the one that matters: a page rendered in one
/// pass must not have rows from two different "now"s, and a golden fixture must render
/// the same bytes on any machine in any time zone.
///
/// ```swift
/// let clock = ViewerClock(now: Date())
/// clock.time(event.time)                  // "14:02"
/// clock.age(event.time, style: .compact)  // "9m"
/// ```
public struct ViewerClock: Friendly {
    /// Creates a clock.
    ///
    /// - Parameters:
    ///   - now: The moment the page is being rendered for.
    ///   - timeZone: The zone the clock column reads in. The viewer is a local tool, so
    ///     the default is the machine's own.
    public init(now: Date = Date(), timeZone: TimeZone = .current) {
        self.now = now
        self.timeZone = timeZone
    }

    /// The moment the page is being rendered for.
    public var now: Date

    /// The zone the clock column reads in.
    public var timeZone: TimeZone

    /// A wall-clock time, `HH:mm`.
    ///
    /// - Parameter date: The moment to show.
    /// - Returns: The time, zero-padded.
    public func time(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// How long ago something happened.
    ///
    /// - Parameters:
    ///   - date: The moment it happened.
    ///   - style: Which spelling to use.
    /// - Returns: The age.
    public func age(_ date: Date, style: RelativeAge.Style) -> String {
        RelativeAge.text(from: date, to: now, style: style)
    }

    /// Whether a moment is inside the 30-second window a touched row is coloured for.
    ///
    /// - Parameter date: The moment to test.
    /// - Returns: `true` while it is still recent.
    public func isRecent(_ date: Date) -> Bool {
        RelativeAge.isRecent(date, now: now)
    }
}
