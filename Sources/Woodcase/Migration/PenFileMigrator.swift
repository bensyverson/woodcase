//
//  PenFileMigrator.swift
//  Woodcase
//
//  Created by Claude on 2026-08-29.
//

import Foundation

/// Rewrites one .pen file's bytes in the current format version — or, for a file a
/// newer Pen wrote, in its own.
///
/// This is the reusable half of `woodcase migrate`: parse the bytes through
/// ``PenParser`` — which routes them past the version gate and, for a legacy
/// document, through ``PenLegacyMigrator`` — then encode the result the way a
/// .pen file is written on disk.
///
/// ```swift
/// let diagnostics = PenDiagnosticCollector()
/// let outcome = try PenFileMigrator.migrate(Data(contentsOf: url), diagnostics: diagnostics)
/// if !outcome.wasAlreadyCurrent {
///     try outcome.data.write(to: url)
/// }
/// ```
///
/// Migration is idempotent: re-migrating its own output returns the same bytes.
public enum PenFileMigrator {
    /// The result of migrating one file's bytes.
    public struct Outcome: Friendly {
        /// The migrated document, encoded by ``PenParser/encodeForFile(_:)``.
        public let data: Data

        /// The `version` the source declared, or `nil` if it declared none or
        /// declared something that was not a string.
        public let declaredVersion: String?

        /// Whether the source already declared ``PenDocument/currentFormatVersion``, or
        /// a newer minor of the same major — either way there is nothing to migrate.
        ///
        /// A caller that only wants to touch out-of-date files skips these; the
        /// bytes are still produced, so `--force`-style rewriting costs nothing extra.
        /// A newer minor rewritten with `--force` keeps its own version.
        public var wasAlreadyCurrent: Bool {
            guard let declared = declaredVersion.flatMap(PenFormatVersion.init) else { return false }
            return [.current, .newerMinor].contains(declared.relation())
        }

        /// The `version` the rewritten bytes declare.
        public let writtenVersion: String

        /// Creates an outcome.
        public init(data: Data, declaredVersion: String?, writtenVersion: String) {
            self.data = data
            self.declaredVersion = declaredVersion
            self.writtenVersion = writtenVersion
        }
    }

    /// Migrates one .pen file's bytes to the current format version.
    ///
    /// - Parameters:
    ///   - data: The raw bytes of a .pen file, in any version Woodcase reads.
    ///   - url: The file the bytes came from, so an error can name it; `nil` for bytes
    ///     with no file behind them.
    ///   - diagnostics: Optional collector notified about version handling and any
    ///     data the legacy migration discards.
    /// - Returns: The rewritten bytes together with the version the source declared
    ///   and the version they now declare.
    /// - Throws: The errors ``PenParser/parse(_:diagnostics:)-(Data,_)`` throws;
    ///   ``PenFormatWriteRefusal`` for a different major version, which may be read
    ///   but never rewritten; or ``PenParserError/decodingFailed(url:underlying:)`` if
    ///   the document cannot be re-encoded.
    public static func migrate(
        _ data: Data,
        from url: URL? = nil,
        diagnostics: PenDiagnosticCollector? = nil
    ) throws -> Outcome {
        let document = try PenParser.parse(data, from: url, diagnostics: diagnostics)
        try document.requireWritableFormat(at: url)
        return try Outcome(
            data: PenParser.encodeForFile(document),
            declaredVersion: declaredVersion(in: data),
            writtenVersion: document.version
        )
    }

    /// Reads the `version` string a document declares, without decoding it.
    private static func declaredVersion(in data: Data) -> String? {
        guard let probe = try? JSONDecoder().decode(PenParser.VersionProbe.self, from: data),
              case let .string(version) = probe.version
        else {
            return nil
        }
        return version
    }
}
