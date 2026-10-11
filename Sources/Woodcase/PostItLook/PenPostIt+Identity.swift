//
//  PenPostIt+Identity.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// The color an author's identity dot falls back to: one of the style's
    /// ``Style/identityPalette``, chosen by a hash of the author string.
    ///
    /// Identity colors are the editor's presence colors, which Woodcase does not know. So
    /// the expansion draws this fallback and names the author beside it
    /// (``PenPostItExpansion/identity``), and an editor that knows the person's presence
    /// color repaints the ``PenPostItExpansion/Role/identityDot`` part — and the mention
    /// pills (``PenPostItExpansion/mentions``) — in it. The hash is
    /// ``identityHash(_:)``, so `woodcase shot`, the CG renderer and RapidPro agree on
    /// every platform and every run.
    ///
    /// - Parameters:
    ///   - author: The author, as `woodcase.author` spells it.
    ///   - style: The look whose palette is chosen from.
    /// - Returns: The fallback color; the style's secondary light ink when its palette is
    ///   empty.
    static func identityColor(for author: String, style: Style = .standard) -> PenHexColor {
        let palette = style.identityPalette
        guard !palette.isEmpty else { return style.inkOnLight.secondary }
        return palette[Int(identityHash(author) % UInt64(palette.count))]
    }

    /// A stable 64-bit hash of an author string: FNV-1a over its UTF-8 bytes.
    ///
    /// Not Swift's `Hasher`, which is seeded per process, so two runs would color one
    /// author differently.
    ///
    /// - Parameter author: The author string.
    /// - Returns: The hash.
    static func identityHash(_ author: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in author.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
