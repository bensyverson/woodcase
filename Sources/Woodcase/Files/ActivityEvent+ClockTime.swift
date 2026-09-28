//
//  ActivityEvent+ClockTime.swift
//  Woodcase
//

import Foundation

/// The time of day a sentence names an event by.
///
/// ``ActivityEvent/wireTime(_:)`` is the log's own format — UTC, to the millisecond,
/// exact enough to round-trip. A sentence a person reads wants neither: "at 10:32" is
/// what makes an outside edit findable in a working day, and it is local, because the
/// reader's clock is the one they are comparing against.
public extension ActivityEvent {
    /// A time of day, as a sentence names it: 24-hour `HH:mm`, in the reader's zone.
    ///
    /// - Parameters:
    ///   - date: The time to name.
    ///   - timeZone: The zone to read it in. Defaults to the system's, which is the
    ///     one the reader is standing in; a test passes its own.
    /// - Returns: The hour and minute, zero-padded, as in `10:32`.
    static func clockTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(
            Date.FormatStyle(timeZone: timeZone)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }
}
