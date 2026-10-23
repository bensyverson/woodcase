//
//  PenBundle+Export.swift
//  Woodcase
//

import Foundation

public extension PenBundle {
    /// Copies a bundle out into a plain folder any `.pen` tool opens — `woodcase unbundle`.
    ///
    /// The folder gets `<name>.pen` — `Design.pen` for `Design.umbra` — beside `images/`
    /// and `fonts/` holding every local file the document points at, with relative
    /// references that resolve from there. Files inside the bundle keep their relative
    /// paths; a reference that reached outside the bundle is copied in too, so the folder
    /// stands alone — except a font file Apple made (``PenFontMaker/isApple``), wherever
    /// it is: Apple's license lets nobody pass its fonts on, so that declaration is left
    /// out (one at a web address is kept as written). The bundle itself, its local state and
    /// its ``ConvertedFrom`` record are left where they are; the new file's log starts
    /// with a `new` row, as any file woodcase creates does. Nothing in the folder is
    /// overwritten.
    ///
    /// With `history` ``HistoryInclusion/included`` every writer's file from the
    /// bundle's `history/` is also copied into the folder's own `history/`. A plain
    /// `.pen` has no shared history, so Woodcase does not read those files there; they
    /// keep the record with the export, for a person or a later conversion. Export
    /// refuses, before writing anything, when the folder's `history/` already holds a
    /// file of the same name.
    ///
    /// - Parameters:
    ///   - bundle: The bundle to export.
    ///   - folder: Where to write. Created if missing; it may already hold other files.
    ///   - identity: The writer's name for the new file's `new` row, or `nil`.
    ///   - history: Whether the writers' history files go with it.
    /// - Returns: The exported `.pen`, its revision, how many files were copied, and any
    ///   reference whose file was missing.
    /// - Throws: ``PenBundleError`` when `bundle` is not a bundle or `<name>.pen` or a
    ///   history file exists in `folder`; ``PenFileError`` or ``PenParserError`` when the bundle cannot be
    ///   read or the folder written.
    @discardableResult
    static func export(
        _ bundle: URL,
        to folder: URL,
        identity: String?,
        history: HistoryInclusion
    ) async throws -> Report {
        try await export(bundle, to: folder, identity: identity, history: history) { $0 }
    }
}

extension PenBundle {
    /// ``export(_:to:identity:history:)`` with the document passed through `prepare` before its
    /// files are gathered — how ``export(_:to:identity:history:fontPlan:bundling:)`` adds the
    /// fonts it bundles. Whatever `prepare` returns, a local declared font file Apple
    /// made is neither copied nor declared (``droppingAppleMadeFonts(_:relativeTo:)``).
    ///
    /// - Parameters:
    ///   - bundle: The bundle to export.
    ///   - folder: Where to write.
    ///   - identity: The writer's name for the new file's `new` row, or `nil`.
    ///   - history: Whether the writers' history files go with it.
    ///   - prepare: The bundle's document to the document to write, its references
    ///     still relative to the bundle.
    /// - Returns: The report.
    /// - Throws: As ``export(_:to:identity:history:)`` does.
    static func export(
        _ bundle: URL,
        to folder: URL,
        identity: String?,
        history: HistoryInclusion,
        prepare: (PenDocument) -> PenDocument
    ) async throws -> Report {
        let location = PenLocation(bundle)
        guard location.kind == .bundle else { throw PenBundleError.notABundle(bundle) }
        let destination = folder.appendingPathComponent(location.name).appendingPathExtension("pen")
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw PenBundleError.destinationExists(destination)
        }
        let historyFolder = folder.appendingPathComponent(ActivityLog.historyDirectoryName, isDirectory: true)
        if history == .included, let taken = collidingHistoryFile(from: bundle, into: historyFolder) {
            throw PenBundleError.destinationExists(taken)
        }

        let document = try await droppingAppleMadeFonts(
            prepare(PenFileTransaction.read(at: location.document) { $0.materialize() }.value),
            relativeTo: location.document
        )
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw PenFileError.writeFailed(url: folder, reason: PenFileError.oneLineReason(error))
        }
        var gathering = PenAssetGathering(from: location.resourceDirectory, into: folder)
        let exported = try PenAssetReferences.rewrite(document) { kind, value in
            try gathering.place(kind, value)
        }
        let created = try await PenFileTransaction.create(at: destination, document: exported, identity: identity)
        let historyCopied = history == .included ? try copyHistory(from: bundle, into: historyFolder) : 0
        return Report(
            document: destination,
            revision: created.value,
            copied: gathering.copiedCount,
            missing: gathering.missing.map(\.value),
            historyCopied: historyCopied
        )
    }

    /// The document without its local font declarations whose file Apple made
    /// (``PenFontMaker/isApple``): Apple's fonts are never bundled, wherever they are
    /// installed (Ben, 2026-10-15). A declaration at a web address, or of a file that is
    /// missing or unreadable, is kept as it is.
    ///
    /// - Parameters:
    ///   - document: The document to export.
    ///   - sourceURL: The .pen file a relative declared url resolves against.
    /// - Returns: The document, its `fonts` array filtered.
    static func droppingAppleMadeFonts(_ document: PenDocument, relativeTo sourceURL: URL) -> PenDocument {
        guard let declarations = document.fonts else { return document }
        let kept = declarations.filter { declaration in
            guard case let .local(url) = GoogleFontResolver.location(of: declaration, relativeTo: sourceURL),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else { return true }
            return PenFontMaker(fontFile: data)?.isApple != true
        }
        guard kept.count < declarations.count else { return document }
        var filtered = document
        filtered.fonts = kept.isEmpty ? nil : kept
        return filtered
    }
}
