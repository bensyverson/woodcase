//
//  ViewerFile.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One .pen file the viewer is watching, and the id its URLs are built from.
///
/// The id is a short hash of the file's canonical path — ``ActivityEvent/canonicalPath(for:)``,
/// the same spelling the activity log records — so `/files/a1b2c3d4e5f6` names the same
/// file after a restart, after `/tmp` resolves to `/private/tmp`, and in a link an agent
/// pasted yesterday. A path in a URL would be prettier and would also break the moment
/// it contained a slash.
public struct ViewerFile: Friendly, Identifiable {
    /// Creates the record for a file.
    ///
    /// - Parameter url: The .pen file. Canonicalized on the way in.
    public init(url: URL) {
        path = ActivityEvent.canonicalPath(for: url)
        id = Self.identifier(for: path)
    }

    /// How many hex characters an id has.
    ///
    /// Twelve is 48 bits: far past any collision a person could hit with the handful of
    /// files one viewer watches, and still short enough to read out loud.
    static let identifierLength = 12

    /// The file's id, as it appears in every URL.
    public let id: String

    /// The file's absolute, canonical path.
    public let path: String

    /// The file, as a URL.
    public var url: URL {
        URL(fileURLWithPath: path)
    }

    /// The file's name without its extension — what a person calls it.
    public var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    /// The id for a canonical path.
    ///
    /// FNV-1a, because it must be the same in every process that serves the same
    /// files: Swift's own `Hasher` is seeded per process, so its answer would change
    /// on every restart — exactly what an id must not do.
    ///
    /// - Parameter path: The canonical path.
    /// - Returns: Twelve lowercase hex characters.
    static func identifier(for path: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hex = String(hash, radix: 16, uppercase: false)
        let padded = String(repeating: "0", count: max(0, 16 - hex.count)) + hex
        return String(padded.suffix(identifierLength))
    }
}
