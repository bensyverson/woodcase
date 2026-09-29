//
//  FontRegistryGate.swift
//  Woodcase
//

import Foundation

/// Lets one thread at a time into Core Text's font *registry*.
///
/// `CTFontCreateWithFontDescriptor` and its neighbors do not resolve a family name
/// in the calling process. They send a **synchronous XPC message to `fontd`** and
/// block the calling thread on the reply — `__NSXPCCONNECTION_IS_WAITING_FOR_A_SYNCHRONOUS_REPLY__`,
/// `mach_msg`, no timeout, no cancellation. That is fine once. It is not fine from
/// several threads at once: Swift's cooperative pool has one thread per core, a
/// blocking call occupies one for as long as it blocks, and a render that resolves
/// fonts on every pool thread simultaneously leaves the process with nothing left to
/// run — including whatever would have made `fontd` answer sooner.
///
/// That is not theoretical. On 2026-08-30 a full `swift test` under load sat for five
/// minutes with **all eight** cooperative threads inside this exact XPC wait, six in
/// ``PenTextMeasurer/resolveFont(family:size:weight:style:)`` and two in
/// ``PenTextMeasurer/fontFamilyAvailable(_:)``, at ~0 % CPU and a flat 188 MB
/// footprint; it never recovered and printed nothing. Earlier runs were sampled in
/// the same place and the hang was recorded as a CoreText bug — see
/// `project/2026-08-30-suite-stability.md`.
///
/// So every call that reaches the registry goes through this gate. One request is in
/// flight at a time, which is what `fontd` serves anyway; the pile-up that wedges it
/// never forms. The cost is bounded and small: ``FontResolutionCache`` answers a
/// repeat lookup without coming here at all, so the gate is only ever contended by
/// *first* resolutions of distinct families.
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
