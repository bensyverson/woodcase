//
//  PenBundle+ExportFonts.swift
//  Woodcase
//

import Foundation

public extension PenBundle {
    /// The font plan for exporting a bundle to a Pen Folder: every family its text
    /// draws, imported components' text included, and whether the folder can carry it.
    ///
    /// - Parameters:
    ///   - bundle: The bundle.
    ///   - fonts: The resolver asked whether Google Fonts has a family — its cache
    ///     first, its fetcher otherwise.
    /// - Returns: The plan; see ``PenFolderFontPlan``.
    /// - Throws: ``PenBundleError/notABundle(_:)`` for a bare `.pen`; ``PenFileError``
    ///   or ``PenParserError`` when the bundle cannot be read.
    static func exportFontPlan(_ bundle: URL, fonts: GoogleFontResolver) async throws -> PenFolderFontPlan {
        let location = PenLocation(bundle)
        guard location.kind == .bundle else { throw PenBundleError.notABundle(bundle) }
        let (expanded, declarations) = try await PenFileTransaction.read(at: location.document) { editable in
            (editable.expanded(for: .canvas), editable.materialize().fonts ?? [])
        }.value
        return await PenFolderFontPlan.make(
            expanded: expanded, declarations: declarations, relativeTo: location.document, fonts: fonts
        )
    }

    /// Copies a bundle out into a plain folder, as ``export(_:to:identity:)`` does, and
    /// bundles the checked families' fonts with it.
    ///
    /// The document written is ``PenFolderFontPlan/exportedDocument(_:bundling:)``'s:
    /// each checked installed family's files are copied into `fonts/` and declared
    /// under their real family name, each unchecked declared family is left out, and
    /// every local declared font — like every image — is copied in with its url
    /// rewritten relative to the exported `.pen`. Two files of one name are kept apart
    /// by a number (`Brand-2.ttf`), and nothing in the folder is overwritten.
    ///
    /// - Parameters:
    ///   - bundle: The bundle to export.
    ///   - folder: Where to write. Created if missing.
    ///   - identity: The writer's name for the new file's `new` row, or `nil`.
    ///   - fontPlan: The plan the person chose from (``exportFontPlan(_:fonts:)``).
    ///   - families: The names of the families they left checked.
    /// - Returns: The exported `.pen`, its revision, how many files were copied, and any
    ///   reference whose file was missing or unreadable.
    /// - Throws: As ``export(_:to:identity:)`` does.
    @discardableResult
    static func export(
        _ bundle: URL,
        to folder: URL,
        identity: String?,
        fontPlan: PenFolderFontPlan,
        bundling families: Set<String>
    ) async throws -> Report {
        try await export(bundle, to: folder, identity: identity) { document in
            fontPlan.exportedDocument(document, bundling: families)
        }
    }
}
