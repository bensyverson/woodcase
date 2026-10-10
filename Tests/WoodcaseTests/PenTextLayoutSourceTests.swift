//
//  PenTextLayoutSourceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing

/// Holds the library to one place that sets a text's lines in a box: ``PenTextLayout``.
/// The CG renderer and text ink bounds both read their lines and their vertical offset
/// from it, so a second `PenTextLines(…)` or `placed(inBoxOfHeight:)` call in the library
/// is a second copy of where a line goes, and can drift from what an editor's caret reads.
@Suite("One place sets a text's lines in a box")
struct PenTextLayoutSourceTests {
    /// The files that may set or place lines: the line breaker itself and the layout.
    private static let allowed: Set<String> = [
        "Rendering/PenTextLines.swift",
        "Rendering/PenTextLayout.swift",
    ]

    /// `Sources/Woodcase`, found from this file's own path.
    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Woodcase")
    }

    /// The library files whose code (not doc comments) contains `needle`.
    private static func files(containing needle: String) throws -> Set<String> {
        let root = sourcesDirectory
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var found: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let code = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            if code.contains(where: { $0.contains(needle) }) {
                found.insert(String(url.path.dropFirst(root.path.count + 1)))
            }
        }
        return found
    }

    @Test("Only PenTextLayout sets lines with PenTextLines")
    func oneLineSetter() throws {
        #expect(try Self.files(containing: "PenTextLines(").isSubset(of: Self.allowed))
    }

    @Test("Only PenTextLayout places lines in a box")
    func onePlacement() throws {
        #expect(try Self.files(containing: "placed(inBoxOfHeight").isSubset(of: Self.allowed))
    }
}
