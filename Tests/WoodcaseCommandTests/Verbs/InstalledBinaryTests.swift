//
//  InstalledBinaryTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase

/// The built binary run from somewhere other than the products directory, the way a
/// broken install runs it: a copy with no resource bundle beside it.
@Suite("Installed binary")
struct InstalledBinaryTests {
    /// A copy of the built `woodcase` in `<root>/libexec/` with no bundle beside it, and a
    /// relative symlink to it in `<root>/bin/`.
    ///
    /// There is no test of the same layout *with* the bundle: on macOS `Bundle.main`
    /// already resolves the symlink, so one passed before any fix.
    private static func install(into root: URL) throws -> URL {
        let libexec = root.appendingPathComponent("libexec", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: libexec, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: CommandFixture.binary(), to: libexec.appendingPathComponent("woodcase"))
        let link = bin.appendingPathComponent("woodcase")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../libexec/woodcase")
        return link
    }

    @Test("Without its resource bundle, generate swiftui fails with an environment error that names the fix")
    func missingBundle() throws {
        let fixture = try CommandFixture(fixture: "layout-nested.pen")
        let binary = try Self.install(into: fixture.root.appendingPathComponent("install"))
        let output = fixture.root.appendingPathComponent("ui", isDirectory: true)

        let run = try fixture.run(["generate", "swiftui", fixture.file.path, "--output", output.path], binary: binary)

        #expect(run.status == 5, "\(run.stderr)")
        #expect(!run.stderr.contains("Fatal error"), "\(run.stderr)")
        #expect(run.stderr.contains(WoodcaseResources.bundleName), "\(run.stderr)")
        #expect(run.stderr.contains("scripts/install"), "\(run.stderr)")
    }
}
