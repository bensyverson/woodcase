//
//  PenFormatVersion.swift
//  Woodcase
//
//  Created by Claude on 2026-08-29.
//

import Foundation

/// A .pen format version, parsed as a numeric `major.minor` pair.
///
/// The `version` field of a .pen document is a string such as `"2.9"` or `"2.17"`.
/// Comparing those strings lexically is wrong (`"2.9" > "2.17"`), so ``PenParser``
/// parses them into this type before dispatching on them.
///
/// ```swift
/// let version = PenFormatVersion("2.17")   // 2.17
/// version == PenFormatVersion.current      // true
/// ```
public struct PenFormatVersion: Friendly, Comparable, CustomStringConvertible {
    /// The format version Woodcase's model represents. A ``PenDocument`` parsed from
    /// an older file reports this version; see ``Relation`` for the rest.
    public static let current = PenFormatVersion(major: 2, minor: 19)

    /// The newest version that ``PenLegacyMigrator`` must rewrite before decoding.
    public static let newestLegacy = PenFormatVersion(major: 2, minor: 10)

    /// The versions after the legacy range that Pen has been seen to write: 2.17 (Pen up
    /// to 1.2.13) and 2.19 (Pen 1.2.14). A 2.11 – 2.18 file declaring anything else is
    /// read with a warning that its version has never been observed.
    public static let observedModern: Set<PenFormatVersion> = [
        PenFormatVersion(major: 2, minor: 17),
        PenFormatVersion(major: 2, minor: 19),
    ]

    /// The oldest version ever observed in a real .pen file.
    public static let oldestObserved = PenFormatVersion(major: 2, minor: 8)

    /// The major component, incremented for a breaking format change.
    public let major: Int

    /// The minor component.
    public let minor: Int

    /// Creates a version from its numeric components.
    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// Parses a `major.minor` version string, returning `nil` if it is malformed.
    ///
    /// A bare major (`"3"`) is read as `3.0`. Anything else — an empty string, a
    /// third component, leading or trailing whitespace — is rejected.
    public init?(_ string: String) {
        guard let match = string.wholeMatch(of: /([0-9]{1,9})(?:\.([0-9]{1,9}))?/),
              let major = Int(match.1)
        else {
            return nil
        }
        let minor = if let minorText = match.2 {
            Int(minorText) ?? 0
        } else {
            0
        }
        self.init(major: major, minor: minor)
    }

    public var description: String {
        "\(major).\(minor)"
    }

    public static func < (lhs: PenFormatVersion, rhs: PenFormatVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }
}

// MARK: - Codable

public extension PenFormatVersion {
    /// Decodes a version from its `major.minor` string form.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let parsed = PenFormatVersion(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid .pen format version: \(string)"
            )
        }
        self = parsed
    }

    /// Encodes the version as its `major.minor` string form.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
