//
//  ScratchDirectoryTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

/// `FileManager.default.temporaryDirectory` resolves to the per-user `/var/folders/…/T`
/// on macOS, not `$TMPDIR` — a directory the Claude Code Bash sandbox denies writes to
/// while it allows `$TMPDIR` itself. `ScratchDirectory` is the one place that
/// disagreement gets resolved.
@Suite("Where a process's scratch directory is")
struct ScratchDirectoryTests {
    @Test("A set $TMPDIR is the whole answer")
    func tmpdirWins() {
        let environment = [ScratchDirectory.environmentVariable: "/private/tmp/claude-501"]

        #expect(ScratchDirectory.url(in: environment).path == "/private/tmp/claude-501")
    }

    @Test("An empty $TMPDIR is not an override")
    func emptyIsIgnored() {
        let environment = [ScratchDirectory.environmentVariable: ""]

        #expect(ScratchDirectory.url(in: environment) == FileManager.default.temporaryDirectory)
    }

    @Test("With nothing set the directory is FileManager's own answer")
    func defaultsToFileManager() {
        #expect(ScratchDirectory.url(in: [:]) == FileManager.default.temporaryDirectory)
    }
}
