//
//  FontRegistryGate.swift
//  Woodcase
//

import Foundation

/// Lets one thread at a time into Core Text's font *registry*.
///
/// `CTFontCreateWithFontDescriptor` and its neighbors do not resolve a family name
/// in the calling process. They send a **synchronous XPC message to `fontd`** and
/// block the calling thread on the reply — `xpc_connection_send_message_with_reply_sync`,
/// `mach_msg`, no timeout, no cancellation. So does **typesetting**: Core Text asks
/// `fontd` for a font's properties the first time it shapes with it
/// (`TBaseFont::DetermineFontFlags`) and for a fallback face when the font lacks a
/// character (`TFontCascade::CreateFallback`). Every one of those calls in Woodcase goes
/// through this gate: resolution, ``PenTextMeasurer``'s typesetting, ``PenTextLines``'
/// framesetter, ``PenIconGlyph``'s line, the browser placeholder's label.
///
/// Why: under load, a test host sometimes waits on a `fontd` reply that never comes. Seen
/// three times — 2026-08-30 (all eight cooperative threads in resolution), issue
/// `Wz8Lz8` (parallel fallback layouts) and issue `6StvbE` (one thread resolving inside
/// the gate, one typesetting outside it, six queued on the gate, for 75 minutes, while
/// `fontd` logged nothing for the connection after opening it). The process is never
/// deadlocked on a lock of its own: every waiter is behind a reply `fontd` does not send.
/// Before 2026-10-20 this comment said the wedge was the cooperative pool running out
/// of threads; that was wrong — a synchronous XPC reply needs no pool thread, and the
/// 6StvbE sample had an idle main thread and an idle worker.
///
/// Why the gate helps without explaining `fontd`: the wedge only ever formed with
/// several of the process's Core Text calls reaching `fontd` at once, and keeping them
/// one at a time stops it forming — unserialized `PenTextGeometryTests` hung 9 of 60
/// fresh test hosts at load 30–150 with layout ungated, and none once layout was gated
/// (`project/2026-10-20-fontd-wedge-and-the-layout-gate.md`). The cost is bounded:
/// ``FontResolutionCache`` answers a repeat lookup without coming here, and a
/// typesetting pass is short, but text layout in one process is now serialized.
///
/// The lock is recursive because the registry calls nest — resolving a font asks
/// whether its family is available first, and both are gated.
enum FontRegistryGate {
    /// Guards entry to the font registry. Recursive: gated calls nest.
    private static let lock = NSRecursiveLock()

    /// Runs `body` with this process's only permit for the font registry.
    ///
    /// - Parameter body: The work that reaches Core Text's font registry.
    /// - Returns: Whatever `body` returns.
    /// - Throws: Whatever `body` throws.
    static func withAccess<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
