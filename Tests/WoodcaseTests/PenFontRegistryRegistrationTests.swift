//
//  PenFontRegistryRegistrationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenFontRegistry/registerFont(at:)`` says what a registration did to the font set,
/// because only a registration that added a face may move the font generation.
///
/// Registration is process-global and irreversible (`project/gotchas.md`, 2026-09-02),
/// so these tests never take a family from absent to present: the "already registered"
/// case uses a test font ``registerTestFonts()`` has already placed, and the "added" case
/// registers a fresh copy of a bundled icon font — the same bytes as a face the process
/// has or will have, so no other suite measures anything different. That copy is left on
/// disk: Core Text reads a registered face's glyphs from its file for the rest of the
/// process.
struct PenFontRegistryRegistrationTests {
    private static let fontsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fonts")

    /// A fresh directory for one test.
    private static func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFontRegistryRegistrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("a file Core Text already has is reported as already registered")
    func alreadyRegistered() {
        TestFontRegistration.registerTestFonts()
        let url = Self.fontsDirectory.appendingPathComponent("IBMPlexSans[wdth,wght].ttf")
        #expect(PenFontRegistry.registerFont(at: url) == .alreadyRegistered)
    }

    @Test("a file Core Text has never seen is reported as added")
    func added() throws {
        let directory = try Self.scratch()
        let source = try #require(PenIconFontRegistry.shared.fontFileURLs(for: "feather").first)
        let copy = directory.appendingPathComponent("feather-copy.ttf")
        try FileManager.default.copyItem(at: source, to: copy)
        #expect(PenFontRegistry.registerFont(at: copy) == .added)
        #expect(PenFontRegistry.registerFont(at: copy) == .alreadyRegistered)
    }

    @Test("a file that is not a font is reported as refused")
    func refused() throws {
        let directory = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bogus = directory.appendingPathComponent("not-a-font.ttf")
        try Data("not a font".utf8).write(to: bogus)
        #expect(PenFontRegistry.registerFont(at: bogus) == .refused)
    }
}
