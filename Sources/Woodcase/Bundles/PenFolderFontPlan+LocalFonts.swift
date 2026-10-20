//
//  PenFolderFontPlan+LocalFonts.swift
//  Woodcase
//

import Foundation

extension PenFolderFontPlan {
    /// What a plan asks of this Mac's fonts, one question per closure.
    ///
    /// ``coreText`` asks Core Text. A test passes its own answers, so what the machine it
    /// runs on has installed — Apple's developer SF Pro in `/Library/Fonts`, say — cannot
    /// decide the outcome.
    ///
    /// `Sendable` but not `Friendly`: it is a bundle of functions, which are neither data
    /// nor comparable.
    struct LocalFonts {
        /// Whether Core Text has a family by exactly that name.
        var isFamilyAvailable: @Sendable (String) -> Bool

        /// Whether the operating system ships the family (``GoogleFontResolver/isSystemFamily(_:)``).
        var isSystemFamily: @Sendable (String) -> Bool

        /// Whether Apple made the font a face is drawn in (``PenFolderFontPlan/isAppleMade(_:)``).
        var isAppleMade: @Sendable (PenFontFace) -> Bool

        /// The installed file a face is drawn in (``PenFolderFontPlan/installedFile(_:)``).
        var installedFile: @Sendable (PenFontFace) -> FontFile?

        /// The answers Core Text gives on this Mac.
        static var coreText: LocalFonts {
            LocalFonts(
                isFamilyAvailable: PenTextMeasurer.fontFamilyAvailable,
                isSystemFamily: GoogleFontResolver.isSystemFamily,
                isAppleMade: PenFolderFontPlan.isAppleMade,
                installedFile: PenFolderFontPlan.installedFile
            )
        }

        /// Whether Woodcase draws `family` as the system UI font by design, rather than as
        /// a stand-in for a family it cannot find.
        ///
        /// Only ``PenTextStyle/defaultFontFamily`` ("SF Pro") is: where Apple's developer
        /// SF Pro is not installed it is drawn as the system font, which is the same
        /// design (``PenTextMeasurer`` ▸ `familySource(for:isAvailable:)`). Any other
        /// family Core Text lacks draws in the system font too, but as a substitute: it is
        /// missing.
        ///
        /// - Parameter family: The family as the document writes it.
        /// - Returns: Whether it is the system UI font.
        func drawsAsSystemFont(_ family: String) -> Bool {
            family.caseInsensitiveCompare(PenTextStyle.defaultFontFamily) == .orderedSame
                && PenTextMeasurer.familySource(for: family, isAvailable: isFamilyAvailable) == .systemFont
        }
    }
}
