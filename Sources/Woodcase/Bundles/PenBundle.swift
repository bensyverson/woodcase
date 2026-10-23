//
//  PenBundle.swift
//  Woodcase
//

import Foundation

/// Converts documents between bare `.pen` files and `.umbra` bundles, and makes a bundle
/// self-contained.
///
/// A bundle is a directory: `document.pen`, the `images/` and `fonts/` it uses, a
/// `history/` with the shared log, and a `.woodcase/` of local state (``PenLocation``). Woodcase
/// reads and writes both shapes everywhere; these are the explicit moves between them,
/// and nothing here ever runs unless asked.
///
/// - ``convert(_:identity:)`` — `woodcase bundle`: a bare `.pen` becomes a bundle beside
///   it, taking its local images and fonts along; ``convert(_:to:identity:)`` makes it
///   wherever an app's save panel chose, keeping the original.
/// - ``importAsset(_:as:into:)`` — a dropped image or an installed font is copied into
///   the bundle's `images/` or `fonts/`.
/// - ``export(_:to:identity:history:)`` — `woodcase unbundle`: a bundle's document and files
///   are copied out into a plain folder any `.pen` tool opens.
/// - ``copy(_:to:history:)`` — a bundle copied to another bundle: Save As, Duplicate and
///   Save To.
/// - ``embed(_:identity:fetcher:fonts:)`` — `woodcase embed`: remote images and Google
///   Fonts are downloaded into the bundle, so it renders offline.
///
/// See <doc:PenBundles>.
public enum PenBundle {
    /// What a conversion or an export did.
    public struct Report: Friendly {
        /// Creates a report.
        ///
        /// - Parameters:
        ///   - document: The `.pen` file written.
        ///   - revision: Its document revision.
        ///   - copied: How many image and font files were copied or downloaded.
        ///   - missing: References whose file could not be found, read or fetched, left
        ///     as they were.
        ///   - historyCopied: How many history files were copied.
        public init(document: URL, revision: String, copied: Int, missing: [String] = [], historyCopied: Int = 0) {
            self.historyCopied = historyCopied
            self.document = document
            self.revision = revision
            self.copied = copied
            self.missing = missing
        }

        /// The `.pen` file written.
        public var document: URL

        /// Its ``EditableDocument/documentRevision``.
        public var revision: String

        /// How many image and font files were copied or downloaded.
        public var copied: Int

        /// References whose file could not be found, read or fetched, left as they were.
        public var missing: [String]

        /// How many of the source's ``ActivityLog/historyDirectoryName`` files were
        /// copied: every writer's live and archived file when ``HistoryInclusion/included``,
        /// none otherwise.
        public var historyCopied: Int
    }
}
