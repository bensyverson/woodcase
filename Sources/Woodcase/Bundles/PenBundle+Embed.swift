//
//  PenBundle+Embed.swift
//  Woodcase
//

import Foundation

public extension PenBundle {
    /// Downloads a bundle's remote images and Google Fonts into it, so it renders offline
    /// and the same everywhere — `woodcase embed`, and `woodcase bundle --embed`.
    ///
    /// - Every `http(s)` image fill is fetched into `images/` and its reference rewritten
    ///   to `./images/…`.
    /// - Every remote declared font (a root `fonts` entry with an `http(s)` url) is
    ///   fetched into `fonts/` and its url rewritten.
    /// - Every family a text node sets that the document does not declare and the
    ///   operating system does not ship is looked up on Google Fonts; the file of each
    ///   face the document draws is copied into `fonts/` and declared in the root
    ///   `fonts` array, so the declared file is drawn ahead of any cache.
    ///
    /// Embedding is explicit only: nothing calls this on its own. Downloads happen first;
    /// the document is then rewritten in one logged transaction — a `replace` row per
    /// top-level node whose fills moved and a `set` row for the `fonts` array — so
    /// `woodcase undo` can take it back. A download that fails leaves its reference
    /// remote and is reported in ``Report/missing``.
    ///
    /// - Parameters:
    ///   - bundle: The bundle.
    ///   - identity: The writer's name for the rows, or `nil`.
    ///   - fetcher: What downloads remote images and declared fonts.
    ///   - fonts: The resolver Google Fonts files come from — its cache first, its own
    ///     fetcher otherwise.
    /// - Returns: The document, its new revision, how many files were downloaded, and any
    ///   reference or family that could not be.
    /// - Throws: ``PenBundleError/notABundle(_:)`` for a bare `.pen`; ``PenFileError``
    ///   or ``PenParserError`` when the bundle cannot be read or written.
    @discardableResult
    static func embed(
        _ bundle: URL,
        identity: String?,
        fetcher: any RemoteDataFetching,
        fonts: GoogleFontResolver
    ) async throws -> Report {
        let location = PenLocation(bundle)
        guard location.kind == .bundle else { throw PenBundleError.notABundle(bundle) }
        let document = try await PenFileTransaction.read(at: location.document) { $0.materialize() }.value

        var downloads = EmbeddedDownloads(bundle: location.resourceDirectory)
        for reference in try PenAssetReferences.collect(from: document)
            where RemoteImageResolver.isRemote(reference.value)
        {
            await downloads.fetch(reference, with: fetcher)
        }
        let declared = Set((document.fonts ?? []).map(\.name))
        let faces = GoogleFontResolver.collectFontFaces(from: document).filter { !declared.contains($0.family) }
        for (family, familyFaces) in Dictionary(grouping: faces, by: \.family).sorted(by: { $0.key < $1.key })
            where !GoogleFontResolver.isSystemFamily(family)
        {
            await downloads.embedGoogleFamily(family, faces: Set(familyFaces), from: fonts)
        }

        let outcome = try await PenFileTransaction.run(at: location.document, identity: identity) { editable, recorder in
            for operation in try downloads.operations(rewriting: editable.materialize()) {
                try recorder.apply(operation)
            }
            return editable.documentRevision
        }
        return Report(
            document: location.document,
            revision: outcome.value,
            copied: downloads.count,
            missing: downloads.missing
        )
    }
}
