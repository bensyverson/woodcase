//
//  PenBundle.swift
//  Woodcase
//

import Foundation

/// Converts documents between bare `.pen` files and `.umbra` bundles, and makes a bundle
/// self-contained.
///
/// A bundle is a directory: `document.pen`, the `images/` and `fonts/` it uses, and a
/// `.woodcase/` holding its activity log and temporary files (``PenLocation``). Woodcase
/// reads and writes both shapes everywhere; these are the explicit moves between them,
/// and nothing here ever runs unless asked.
///
/// - ``convert(_:identity:)`` — `woodcase bundle`: a bare `.pen` becomes a bundle beside
///   it, taking its local images and fonts along.
/// - ``export(_:to:identity:)`` — `woodcase unbundle`: a bundle's document and files are
///   copied out into a plain folder any `.pen` tool opens.
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
        ///   - missing: References whose file could not be found or fetched, left as
        ///     they were.
        public init(document: URL, revision: String, copied: Int, missing: [String] = []) {
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

        /// References whose file could not be found or fetched, left as they were.
        public var missing: [String]
    }
}
