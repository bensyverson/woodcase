//
//  PenParser+VersionGate.swift
//  Woodcase
//
//  Created by Claude on 2026-08-29.
//

import Foundation

/// The version gate: reading a document's declared `version` and deciding how to decode it.
extension PenParser {
    /// Reads nothing from a .pen file but its declared `version`, so a current
    /// document is not materialized as a generic JSON tree just to be routed.
    struct VersionProbe: Decodable {
        /// The raw `version` value, kept type-erased so a non-string one can be
        /// reported back in the error message.
        let version: AnyCodable?
    }

    /// What the version gate decided to do with a document.
    enum Route {
        /// The tree is already current-shaped; decode the original bytes. The version
        /// the decoded document reports follows from `relation`: an older minor is
        /// stamped with the model's version, a newer one keeps its own.
        case decodeAsIs(PenFormatVersion.Relation)
        /// The tree is older than the model; run ``PenLegacyMigrator`` over it first, with
        /// the rules ``PenLegacyMigrator/rules(upgrading:)`` picks for the declared
        /// version — `nil` for a document that declares none, read as legacy.
        case migrate(PenFormatVersion?)
        /// Another major, as declared: read it only if ``StructuralProbe`` says it is
        /// still a document of the modelled major's shape.
        case probeDifferentMajor(String)
    }

    /// Reads the document's `version` and picks a decoding route, noting where the
    /// declared version is one Pen has never been seen to write, or one newer than
    /// the model.
    ///
    /// - Parameters:
    ///   - declaredVersion: The document's raw `version` value, or `nil` if it has none.
    ///   - diagnostics: Optional collector for the notices and warnings this gate emits.
    /// - Returns: The route to decode by.
    /// - Throws: ``PenParserError/unsupportedVersion(url:version:)`` for a version that
    ///   is not a `major.minor` string.
    static func route(
        declaredVersion: AnyCodable?,
        diagnostics: PenDiagnosticCollector?
    ) throws -> Route {
        guard let rawVersion = declaredVersion, rawVersion != .null else {
            diagnostics?.warn(
                "Document has no \"version\" field; reading it as a legacy (pre-2.11) document.",
                stage: .migration
            )
            return .migrate(nil)
        }

        guard case let .string(versionString) = rawVersion,
              let version = PenFormatVersion(versionString)
        else {
            throw PenParserError.unsupportedVersion(
                url: nil, version: scalarDescription(of: rawVersion)
            )
        }

        let relation = version.relation()
        if relation == .differentMajor {
            return .probeDifferentMajor(versionString)
        }

        if version < PenFormatVersion.oldestObserved {
            diagnostics?.warn(
                "Format version \(versionString) predates the oldest .pen version ever observed "
                    + "(\(PenFormatVersion.oldestObserved)); reading it as legacy.",
                stage: .migration
            )
            return .migrate(nil)
        }

        if version <= PenFormatVersion.newestLegacy {
            return .migrate(version)
        }

        switch relation {
        case .older:
            if !PenFormatVersion.observedModern.contains(version) {
                diagnostics?.warn(
                    "Format version \(versionString) has never been observed in the wild; "
                        + "decoding it with the \(PenDocument.currentFormatVersion) model.",
                    stage: .migration
                )
            }
            return .migrate(version)
        case .newerMinor:
            diagnostics?.notice(
                "Format version \(versionString) is newer than this build's "
                    + "\(PenDocument.currentFormatVersion); reading it with the "
                    + "\(PenDocument.currentFormatVersion) model, and it is written back as \(versionString).",
                stage: .migration
            )
        case .current, .differentMajor:
            break
        }
        return .decodeAsIs(relation)
    }

    /// Warns that a different-major document passed the probe and is open read-only.
    ///
    /// Emitted only once the probe has passed, so a document that fails it throws
    /// without leaving a warning behind that describes a read that never happened.
    ///
    /// - Parameters:
    ///   - version: The version the document declares.
    ///   - diagnostics: Optional collector for the warning.
    static func warnReadOnly(_ version: String, diagnostics: PenDiagnosticCollector?) {
        diagnostics?.warn(
            "Format version \(version) is a different major version from the "
                + "\(PenDocument.currentFormatVersion) this build models; reading it with the "
                + "\(PenDocument.currentFormatVersion) model, read-only — writes are refused.",
            stage: .migration
        )
    }

    /// Renders a `version` value that is not a version string, for the error message.
    static func scalarDescription(of value: AnyCodable) -> String {
        switch value {
        case let .string(text): text
        case let .int(number): String(number)
        case let .double(number): String(number)
        case let .bool(flag): String(flag)
        case .null: "null"
        case .array, .dictionary: "<non-scalar>"
        }
    }
}
