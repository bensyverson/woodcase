//
//  ShaderWarningTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// `render` and `shot` say, once, which nodes lose a shader fill.
///
/// Pen runs a shader fill; Woodcase draws nothing for one (finding F1 of
/// `project/2026-09-27-fidelity-gaps.md`). A picture that silently leaves the paint out
/// reads as authoritative, so both verbs print one warning on standard error naming the
/// shader nodes, and still exit 0: the render happened. `render-shader-warning.pen` has a
/// shader fill (`Swatch`), a shader stroke (`Ring`), a disabled shader (`Off`) and a second
/// artboard with none (`Plain`).
@Suite("Shader warnings")
struct ShaderWarningTests {
    /// The standard-error lines that speak of shaders.
    private func shaderLines(_ stderr: String) -> [Substring] {
        stderr.split(separator: "\n").filter { $0.contains("shader") }
    }

    @Test("render prints one warning naming every shader node, and still succeeds")
    func render() throws {
        let fixture = try CommandFixture(fixture: "render-shader-warning.pen")
        let run = try fixture.run("render", fixture.file.path, "--scale", "1")

        #expect(run.status == 0, "\(run.stderr)")
        let lines = shaderLines(run.stderr)
        #expect(lines.count == 1, "\(run.stderr)")
        let line = try #require(lines.first)
        #expect(line.hasPrefix("warning:"), "\(line)")
        #expect(line.contains("Swatch (Rct01)"), "\(line)")
        #expect(line.contains("Ring (Rct02)"), "\(line)")
        #expect(!line.contains("Rct03"), "\(line)")
    }

    @Test("render --strict fails on the warning, as it does on any other")
    func renderStrict() throws {
        let fixture = try CommandFixture(fixture: "render-shader-warning.pen")
        let run = try fixture.run("render", fixture.file.path, "--scale", "1", "--strict")
        #expect(run.status != 0)
        #expect(shaderLines(run.stderr).count == 1, "\(run.stderr)")
    }

    @Test("shot of the shaded artboard prints the warning once")
    func shot() throws {
        let fixture = try CommandFixture(fixture: "render-shader-warning.pen")
        let out = fixture.root.appendingPathComponent("out.png").path
        let run = try fixture.run("shot", fixture.file.path, "Shaded", "--out", out)

        #expect(run.status == 0, "\(run.stderr)")
        let lines = shaderLines(run.stderr)
        #expect(lines.count == 1, "\(run.stderr)")
        #expect(lines.first?.contains("Swatch (Rct01)") == true, "\(run.stderr)")
    }

    @Test("shot of an artboard with no shader says nothing about the other's")
    func shotScoped() throws {
        let fixture = try CommandFixture(fixture: "render-shader-warning.pen")
        let out = fixture.root.appendingPathComponent("out.png").path
        let run = try fixture.run("shot", fixture.file.path, "Plain", "--out", out)

        #expect(run.status == 0, "\(run.stderr)")
        #expect(shaderLines(run.stderr).isEmpty, "\(run.stderr)")
    }
}
