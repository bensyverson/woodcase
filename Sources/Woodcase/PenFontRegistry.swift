//
//  PenFontRegistry.swift
//  Woodcase
//

import CoreText
import Foundation
import os

/// Tracks how many times the set of fonts Core Text knows about has changed in
/// this process.
///
/// That set is not fixed for the life of a process: ``PenIconFontRegistry``
/// registers bundled icon fonts on first use, ``GoogleFontResolver`` registers
/// downloaded families, and a host application may register its own. Anything
/// that memoizes a font *resolution* — notably the cache behind
/// ``PenTextMeasurer/resolveFont(family:size:weight:style:)`` — is therefore
/// only valid for the font set it was computed against.
/// ``generation`` names that font set: it increases every time fonts are
/// registered or unregistered, which is the signal a cache needs to discard
/// entries resolved against an older set. Without it, a lookup that ran before
/// a font was registered pins the fallback for the rest of the process.
///
/// This is not a font *database* — ``PenIconFontRegistry`` is the registry of
/// icon fonts. This type only records that the database changed.
///
/// The generation advances from two independent sources, because neither alone
/// is complete:
///
/// - ``registerFont(at:)``, the one registration every path inside Woodcase takes,
///   which calls ``didRegisterFonts()`` when — and only when — a registration added
///   a face. This works in a headless process, which the notification below may not.
/// - `kCTFontManagerRegisteredFontsChangedNotification`, which Core Text posts
///   when *anyone* registers or unregisters fonts. This covers registrars
///   outside Woodcase, but only reaches us in a process that runs a run loop: it is
///   delivered on the run loop, not during the registering call. It is not posted
///   for a file Core Text already has, so a no-op registration moves nothing here
///   either (measured 2026-09-27, leaf 0IegsD).
///
/// Code outside Woodcase that registers font files should call ``registerFont(at:)``;
/// code that registers any other way — `CTFontManagerRegisterFontDescriptors` or
/// `CTFontManagerRegisterGraphicsFont` — should call ``didRegisterFonts()`` after
/// a registration that succeeded, rather than rely on the notification.
public enum PenFontRegistry {
    /// The generation counter, and the one-time installation of the Core Text
    /// observer that also advances it.
    private static let state: OSAllocatedUnfairLock<Int> = {
        let lock = OSAllocatedUnfairLock(initialState: 0)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetLocalCenter(),
            nil,
            { _, _, _, _, _ in PenFontRegistry.didRegisterFonts() },
            kCTFontManagerRegisteredFontsChangedNotification,
            nil,
            .deliverImmediately
        )
        return lock
    }()

    /// The number of font-set changes observed in this process.
    ///
    /// Starts at zero and only ever increases. Two resolutions taken at the
    /// same generation saw the same set of registered fonts.
    public static var generation: Int {
        state.withLock { $0 }
    }

    /// Records that fonts were registered with, or unregistered from, Core Text.
    ///
    /// Call this immediately *after* a Core Text call that changed the font set
    /// returns; ``registerFont(at:)`` does it for a file. Caches keyed on
    /// ``generation`` discard everything resolved before this point. Calling it
    /// for a registration that added nothing is correct but not free: it discards
    /// every cached font resolution and text size, and every settled tree's
    /// reusable pieces, so a caller that cannot tell should still call it, and one
    /// that can should not.
    public static func didRegisterFonts() {
        state.withLock { $0 += 1 }
    }

    /// What registering one font file did to the font set.
    public enum Registration: Friendly {
        /// Core Text added the file's faces, so the font set changed.
        case added
        /// The file was already registered, or a face of the same name was: the font
        /// set is unchanged, and the family is as available as it was.
        case alreadyRegistered
        /// Core Text refused the file — not a font, unreadable, or gone.
        case refused
    }

    /// Registers a font file with Core Text for this process, and moves ``generation``
    /// only when that added a face.
    ///
    /// Every registration inside Woodcase comes here. Registering a file Core Text
    /// already has is common — a settled read registers a document's declared fonts on
    /// every read — and must not move the generation: a move discards every cached
    /// resolution and text size, and every settled tree's reusable pieces with them, so
    /// an unchanged document would be laid out whole on each read. A file registered
    /// again from another path *is* added (Core Text accepts it as a second face), and
    /// moves the generation, since which of the two a name resolves to may change.
    ///
    /// Registration goes through the file URL on purpose: descriptors created *from
    /// data* carry no `kCTFontURLAttribute`, and `CTFontManagerRegisterFontDescriptors`
    /// rejects them with error 303 — silently, when nobody reads the handler
    /// (`project/gotchas.md`).
    ///
    /// - Parameter url: The font file.
    /// - Returns: What the registration did to the font set.
    @discardableResult
    public static func registerFont(at url: URL) -> Registration {
        let registration: Registration = FontRegistryGate.withAccess {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return .added }
            guard let code = (error?.takeRetainedValue()).map(CFErrorGetCode) else { return .refused }
            switch code {
            case CTFontManagerError.alreadyRegistered.rawValue, CTFontManagerError.duplicatedName.rawValue:
                return .alreadyRegistered
            default:
                return .refused
            }
        }
        // Any resolution cached before this point predates these faces.
        if registration == .added { didRegisterFonts() }
        return registration
    }
}
