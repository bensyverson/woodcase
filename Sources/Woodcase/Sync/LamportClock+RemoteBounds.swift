//
//  LamportClock+RemoteBounds.swift
//  Woodcase
//

import Foundation

/// The range of remote times a replica will witness.
///
/// ``LamportClock/witness(_:)`` sets the clock to `max(local, remote) + 1`, so a remote
/// time of `UInt64.max` would overflow and trap — and a relay replays a stored operation
/// to every peer that rejoins, so one bad operation would crash every replica, again and
/// again. A time merely huge is quieter but as bad: the sender's writes would win every
/// last-writer-wins race forever. So a remote time is witnessed only when
/// ``admits(_:after:)`` says so, and the boundary refuses the rest with a
/// ``RemoteInputError``.
public extension LamportClock {
    /// How far ahead of the local clock an honest remote time can be: 2³².
    ///
    /// A Lamport time grows by one per operation a peer makes or witnesses, so a peer this
    /// far ahead would have made four billion operations this replica has not seen —
    /// more than any editing session produces, however long it was offline. It is far
    /// looser than the multiplayer relay's jump bound (10⁶ past the room's high-water
    /// time, relay plan §6.2) on purpose: a replica judges against its own clock, which
    /// can lag the room's while it catches up, so it must never refuse what the relay
    /// accepted from an honest peer. A peer still needs two million operations to climb
    /// from zero to the ceiling.
    static let maximumLead: UInt64 = 1 << 32

    /// The largest remote time a replica witnesses: 2⁵³ − 1.
    ///
    /// It is the largest integer a JavaScript number holds exactly, so a time at or below
    /// it survives any JSON hop; it is also the multiplayer relay's `MaxTime` (relay plan
    /// §5.1), so the two refuse the same times. It leaves the clock about 2⁶⁴ − 2⁵³
    /// ticks of headroom, so local ticks never near `UInt64.max`.
    static let ceiling: UInt64 = (1 << 53) - 1

    /// Whether a remote time is in range for a clock at `localTime`.
    ///
    /// - Parameters:
    ///   - remote: The time a peer sent.
    ///   - localTime: The local clock's time.
    /// - Returns: `true` when `remote` is at most ``ceiling`` and at most
    ///   ``maximumLead`` ahead of `localTime`.
    static func admits(_ remote: UInt64, after localTime: UInt64) -> Bool {
        remote <= ceiling && (remote <= localTime || remote - localTime <= maximumLead)
    }
}
