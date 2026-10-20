//
//  KiwiGenericityTests.swift
//  WoodcaseTests
//

import Foundation
import Testing

/// The Kiwi reader knows Kiwi, not any one application of it: every definition it decodes
/// comes from the schema it is handed. This scans its sources for the names of the one
/// application we know uses it, so a Figma-specific shortcut cannot creep in unnoticed.
struct KiwiGenericityTests {
    /// Words that would only appear in the reader if it special-cased Figma's schema.
    private static let forbidden = ["Figma", "fig-kiwi", "NodeChange", "NODE_CHANGES", "MessageType", "\"Message\""]

    @Test func theReaderNamesNoApplicationSchema() throws {
        let kiwiSources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Kiwi
            .deletingLastPathComponent() // WoodcaseTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Sources/Woodcase/Kiwi")
        let files = try FileManager.default.contentsOfDirectory(at: kiwiSources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 5)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for word in Self.forbidden {
                #expect(!text.contains(word), "\(file.lastPathComponent) mentions \(word)")
            }
        }
    }
}
