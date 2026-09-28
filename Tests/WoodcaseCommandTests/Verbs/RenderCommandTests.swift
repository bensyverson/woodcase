//
//  RenderCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `render` takes a `.pen` file, so a file that is not there is the same refusal here
/// as on every other verb: exit 4, the path named, and the command that would show
/// what *is* there.
@Suite("Render")
struct RenderCommandTests {
    @Test("A file that is not there is exit 4 with the command that would show what is")
    func missingFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("render", fixture.root.appendingPathComponent("gone.pen").path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains(fixture.root.appendingPathComponent("gone.pen").path))
        #expect(run.stderr.contains("no such file"))
        #expect(run.stderr.contains("ls "))
    }

    @Test("A directory named where a file belongs is exit 4, and the message says so")
    func directoryIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("render", fixture.root.path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("it is a directory"))
    }

    // MARK: - Theme Combinations

    /// `render-theme-unthemed-only.pen` has one unthemed frame and a two-option `mode`
    /// axis. An unthemed artboard has no `theme` to narrow it, so it belongs in every
    /// combination — the bug left the second combination with zero matching frames,
    /// which `guard !frames.isEmpty else { continue }` in `RenderCommand` silently skips.
    @Test("An unthemed artboard renders once per combination of a two-option axis")
    func unthemedArtboardRendersInEveryCombination() throws {
        let fixture = try CommandFixture(fixture: "render-theme-unthemed-only.pen")
        let run = try fixture.run("render", fixture.file.path)

        #expect(run.status == 0)
        #expect(run.stdout.contains("Rendered 2 file(s)"))

        let light = fixture.root.appendingPathComponent("light/render-theme-unthemed-only@2x.png")
        let dark = fixture.root.appendingPathComponent("dark/render-theme-unthemed-only@2x.png")
        #expect(FileManager.default.fileExists(atPath: light.path))
        #expect(FileManager.default.fileExists(atPath: dark.path))
    }

    /// `render-theme-axis.pen` pairs an unthemed frame (`Screen`) with a frame pinned to
    /// `mode: dark` (`Special`). `Special` must render only under the `dark` combination —
    /// a frame pinned to one option of an axis must not also render under another.
    @Test("A themed artboard renders only in matching combinations")
    func themedArtboardRendersOnlyInMatchingCombinations() throws {
        let fixture = try CommandFixture(fixture: "render-theme-axis.pen")
        let run = try fixture.run("render", fixture.file.path)

        #expect(run.status == 0)
        #expect(run.stdout.contains("Rendered 3 file(s)"))

        let lightFiles = try fileNames(in: fixture.root.appendingPathComponent("light"))
        let darkFiles = try fileNames(in: fixture.root.appendingPathComponent("dark"))

        // The document has two artboards, so `Screen` is named in every combination,
        // including the one where it is the only artboard that matches.
        #expect(lightFiles == ["render-theme-axis-Screen@2x.png"])
        #expect(darkFiles.contains("render-theme-axis-Screen@2x.png"))
        #expect(darkFiles.contains("render-theme-axis-Special@2x.png"))
        #expect(darkFiles.count == 2)
    }

    // MARK: - Reusable Definitions

    /// `render-reusable-visible.pen` places a `reusable: true` definition (`Component`)
    /// directly in the document's visible flow, the way `shot`, `tree` and the viewer
    /// already show it. `render` used to strip every reusable definition from the
    /// expanded tree before laying it out, so `Component` never got a rect and never
    /// got drawn — the pilot's board rendered 511 pt short for exactly this reason.
    @Test("A reusable definition in visible flow appears in render output")
    func reusableDefinitionInVisibleFlowAppearsInOutput() throws {
        let fixture = try CommandFixture(fixture: "render-reusable-visible.pen")
        let run = try fixture.run("render", fixture.file.path)

        #expect(run.status == 0)
        #expect(run.stdout.contains("Rendered 2 file(s)"))

        let files = try fileNames(in: fixture.root)
        #expect(files.contains("render-reusable-visible-Component@2x.png"))
        #expect(files.contains("render-reusable-visible-Screen@2x.png"))
    }

    /// The names of the regular files directly inside a directory, or `[]` if the
    /// directory does not exist — a combination the buggy code skipped never creates
    /// its subdirectory at all.
    private func fileNames(in directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }
}
