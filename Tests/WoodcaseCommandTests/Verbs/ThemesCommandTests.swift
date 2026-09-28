import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

struct ThemesCommandTests {
    @Test("A file that is not there is exit 4 with the command that would show what is")
    func missingFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("themes", fixture.root.appendingPathComponent("gone.pen").path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains(fixture.root.appendingPathComponent("gone.pen").path))
        #expect(run.stderr.contains("no such file"))
        #expect(run.stderr.contains("ls "))
    }

    @Test("A directory named where a file belongs is exit 4, and the message says so")
    func directoryIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("themes", fixture.root.path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("it is a directory"))
    }

    private let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    @Test("Formats theme axes as 'axis: option1, option2' lines sorted alphabetically")
    func formatsThemeAxes() {
        let themes: [String: [String]] = [
            "mode": ["light", "dark"],
            "platform": ["ios", "web"],
        ]
        let output = ThemeFormatter.format(themes)
        #expect(output == "mode: light, dark\nplatform: ios, web")
    }

    @Test("Returns nil for empty themes dictionary")
    func emptyThemes() {
        let themes: [String: [String]] = [:]
        let output = ThemeFormatter.format(themes)
        #expect(output == nil)
    }

    @Test("Returns nil for nil themes")
    func nilThemes() {
        let output = ThemeFormatter.format(nil)
        #expect(output == nil)
    }

    @Test("Single axis with single option")
    func singleAxisSingleOption() {
        let themes = ["mode": ["dark"]]
        let output = ThemeFormatter.format(themes)
        #expect(output == "mode: dark")
    }
}
