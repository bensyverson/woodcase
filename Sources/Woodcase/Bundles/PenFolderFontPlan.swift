//
//  PenFolderFontPlan.swift
//  Woodcase
//

import Foundation

/// Which of a document's font families a Pen Folder export can carry beside the .pen,
/// and why the rest cannot.
///
/// One ``Family`` per family the document's text draws, under every theme it can show
/// (``themeCoverage``), with where its fonts come from (``Source``), the files of the
/// faces drawn, each file's embedding permission and license, and whether the row
/// starts checked. An app shows the rows as checkboxes; the families the person leaves
/// checked go to ``PenBundle/export(_:to:identity:fontPlan:bundling:)``, which copies
/// their files into `fonts/` and declares them in the exported document's root `fonts`
/// array (``exportedDocument(_:bundling:)``).
///
/// The rules (Ben, 2026-10-15): every family is listed, and every one starts checked
/// except Apple's fonts — the operating system's own, and any other font Apple made,
/// such as the SF Pro installed in `/Library/Fonts` from Apple's developer downloads,
/// which Apple's license does not let anyone pass on, whatever their `fsType` says — and
/// Google Fonts, which Pen downloads by name so nothing needs to ship. Those two are unchecked and disabled, with a ``Reason``. A
/// font whose `fsType` restricts embedding or allows only preview and print starts
/// checked like the rest, flagged by its reason: the designer reads the license.
///
/// Build one with ``make(for:relativeTo:fonts:)``, or for a bundle with
/// ``PenBundle/exportFontPlan(_:fonts:)``. See <doc:PenBundles>.
public struct PenFolderFontPlan: Friendly {
    /// The families the document draws, sorted by name.
    public var families: [Family]

    /// Which theme combinations the families were collected under.
    public var themeCoverage: ThemeCoverage

    /// A plan of `families`, collected under `themeCoverage`.
    public init(families: [Family], themeCoverage: ThemeCoverage) {
        self.families = families
        self.themeCoverage = themeCoverage
    }

    /// Where a family's fonts come from, in the order the plan asks.
    public enum Source: String, Friendly, CaseIterable {
        /// The document declares it in its root `fonts` array.
        case declared
        /// Apple's: the operating system ships it — its file is under `/System/` (which
        /// holds `/System/Library/Fonts` and the downloadable fonts under
        /// `/System/Library/AssetsV2`) or `/Library/Apple/` — or Apple made it, wherever
        /// it is installed (``PenFontMaker/isApple``), or it is the default family, SF Pro,
        /// which a Mac without Apple's developer download draws as the system UI font.
        case system
        /// Google Fonts has a family of the name, which Pen downloads by name.
        case googleFonts
        /// A font on this Mac outside the system's folders — `~/Library/Fonts`,
        /// `/Library/Fonts`, or anywhere a font manager or app registered it — that Apple
        /// did not make.
        case installed
        /// Nothing provides it here: Pen will substitute.
        case missing
    }

    /// Why a row is disabled, or what its checkbox should warn about. An app words it.
    public enum Reason: String, Friendly, CaseIterable {
        /// Disabled: Apple's license does not allow passing on its system fonts.
        case systemFont
        /// Disabled: Pen downloads it by name; nothing to ship.
        case googleFonts
        /// Disabled: the document declares it only at a web address, kept as written.
        case declaredRemotely
        /// Disabled: no font of the family is on this Mac and Google Fonts has none.
        case notFound
        /// Disabled: no font of the family is on this Mac, and Google Fonts could not be
        /// asked whether it has one.
        case googleFontsUnreachable
        /// Checked, flagged: a file's `fsType` restricts embedding (2).
        case restrictedEmbedding
        /// Checked, flagged: a file's `fsType` allows only preview and print (4).
        case previewAndPrintEmbedding
        /// Checked, flagged: a file has no readable `fsType`.
        case unreadableEmbedding
    }

    /// Which theme combinations a plan's families were collected under.
    public enum ThemeCoverage: Friendly {
        /// Every combination of every theme axis's options: `count` of them.
        case everyCombination(count: Int)
        /// More combinations than ``maximumCombinations``: each option of each axis
        /// with every other axis at its default, `count` resolutions in all. A family
        /// that only one combination of two non-default options draws is not listed.
        case eachOptionAlone(count: Int)
    }

    /// The most theme combinations resolved one by one; more fall back to
    /// ``ThemeCoverage/eachOptionAlone(count:)``.
    public static let maximumCombinations = 64
}
