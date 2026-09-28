//
//  GoldenFile.swift
//  WoodcaseTests
//

import Foundation
import Testing

/// The golden-file comparison the emitter suites share.
///
/// A golden lives at `Tests/WoodcaseTests/Fixtures/golden/<subdirectory>/<name>.golden`
/// and is read back out of `Bundle.module` at run time. With `UPDATE_GOLDEN=1` in the
/// environment the comparison becomes a *write* against the source tree — resolved from
/// this file's own `#filePath`, not from the bundle, so the rewritten file is the one
/// under version control. Read what it wrote before committing it: a golden nobody
/// looked at only records what the code does today.
enum GoldenFile {
    /// Compare `content` against its golden, or rewrite the golden when `UPDATE_GOLDEN=1`.
    ///
    /// - Parameters:
    ///   - content: The emitted text to check.
    ///   - name: The golden's file name without the `.golden` extension (`"StatCard.tsx"`).
    ///   - subdirectory: A directory under `Fixtures/golden/`, for goldens that mirror the
    ///     emitted tree (`"pages"`). `nil` puts the golden directly in `Fixtures/golden/`.
    ///   - sourceLocation: Where to report a mismatch — the calling test, by default.
    static func assert(
        _ content: String,
        name: String,
        subdirectory: String? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
            let directory = sourceDirectory(subdirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(name).golden")
            try content.write(to: url, atomically: true, encoding: .utf8)
            print("  Updated golden file: \(url.lastPathComponent)")
        } else {
            let golden = try load(name: name, subdirectory: subdirectory)
            #expect(content == golden, sourceLocation: sourceLocation)
        }
    }

    /// Read a golden out of the test bundle.
    ///
    /// - Throws: When the golden does not exist — which is what a new golden test does on
    ///   its first, red run.
    private static func load(name: String, subdirectory: String?) throws -> String {
        var components: [String] = ["Fixtures", "golden"]
        if let subdirectory { components.append(subdirectory) }
        let bundlePath = components.joined(separator: "/")
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "golden", subdirectory: bundlePath),
            "no golden \(bundlePath)/\(name).golden in the test bundle; run with UPDATE_GOLDEN=1 to write it"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The golden's directory in the source tree, for `UPDATE_GOLDEN=1` writes.
    private static func sourceDirectory(_ subdirectory: String?) -> URL {
        var directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("golden")
        if let subdirectory {
            directory = directory.appendingPathComponent(subdirectory)
        }
        return directory
    }
}
