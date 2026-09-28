//
//  GenerateSwiftUICommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

@Suite("Generate.SwiftUI")
struct GenerateSwiftUICommandTests {
    @Test("Parses minimal arguments: the default module and floor")
    func minimalArguments() throws {
        let command = try Generate.SwiftUI.parse(["input.pen"])
        #expect(command.input.path == "input.pen")
        #expect(command.output == ".")
        #expect(command.name == "PenUI")
        #expect(command.floor == .iOS26)
        #expect(command.force == false)
    }

    @Test("--floor ios18 selects the lower floor")
    func lowerFloor() throws {
        let command = try Generate.SwiftUI.parse(["input.pen", "--floor", "ios18"])
        #expect(command.floor == .iOS18)
    }

    @Test("A module name that is not a Swift identifier is refused")
    func badModuleName() {
        #expect(throws: (any Error).self) {
            try Generate.SwiftUI.parse(["input.pen", "--name", "my-ui"])
        }
    }

    @Test("It writes the package: the manifest, a page per top-level frame, the support file")
    func writesThePackage() throws {
        let fixture = try CommandFixture(fixture: "layout-nested.pen")
        let output = fixture.root.appendingPathComponent("ui", isDirectory: true)
        let run = try fixture.run("generate", "swiftui", fixture.file.path, "--output", output.path, "--name", "Acme")

        #expect(run.status == 0, "\(run.stderr)")
        for path in ["Package.swift", "Sources/Acme/Pages/LayoutNested.swift", "Sources/Acme/Support/PenSupport.swift"] {
            #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(path).path), "\(path)")
        }
        // Each concern adds its own support file, so the count follows what was written.
        let support = try FileManager.default.contentsOfDirectory(atPath: output.appendingPathComponent("Sources/Acme/Support").path)
        // The catalog adds three views under Catalog/ and the executable's main.swift, and
        // Resources/.gitkeep keeps the resource directory Package.swift always declares.
        #expect(run.stdout.contains("Generated \(3 + support.count + 4) file(s)"))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("Sources/AcmeCatalog/main.swift").path))
    }

    @Test("An image fill's file is copied into the module's resources, where Bundle.module finds it")
    func copiesImages() throws {
        let fixture = try CommandFixture(fixture: "layout-nested.pen")
        let images = fixture.root.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: images.appendingPathComponent("photo.png"))
        let pen = fixture.root.appendingPathComponent("photo.pen")
        let json = ##"{"version": "2.17", "children": [{"type": "frame", "id": "b", "name": "Board", "width": 10, "height": 10, "fill": {"type": "image", "url": "./images/photo.png"}}]}"##
        try Data(json.utf8).write(to: pen)
        let output = fixture.root.appendingPathComponent("ui", isDirectory: true)
        let run = try fixture.run("generate", "swiftui", pen.path, "--output", output.path, "--name", "Acme")

        #expect(run.status == 0, "\(run.stderr)")
        let copied = output.appendingPathComponent("Sources/Acme/Resources/photo.png")
        #expect(FileManager.default.contents(atPath: copied.path) == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(run.stdout.contains("+ 1 image(s)"))
    }

    @Test("An icon's font is copied into the module's resources, where its PenIconShape reads it")
    func copiesIconFonts() throws {
        let fixture = try CommandFixture(fixture: "layout-nested.pen")
        let pen = fixture.root.appendingPathComponent("icon.pen")
        let json = ##"{"version": "2.17", "children": [{"type": "frame", "id": "b", "name": "Board", "width": 10, "height": 10, "children": [{"type": "icon", "id": "i", "width": 24, "height": 24, "library": "lucide", "icon": "star"}]}]}"##
        try Data(json.utf8).write(to: pen)
        let output = fixture.root.appendingPathComponent("ui", isDirectory: true)
        let run = try fixture.run("generate", "swiftui", pen.path, "--output", output.path, "--name", "Acme")

        #expect(run.status == 0, "\(run.stderr)")
        let source = try #require(SwiftUIEmitter.iconFontFiles(for: "lucide").first)
        let copied = output.appendingPathComponent("Sources/Acme/Resources/lucide.ttf")
        #expect(FileManager.default.contents(atPath: copied.path) == FileManager.default.contents(atPath: source.path))
        #expect(run.stdout.contains("+ 1 icon font(s)"))
    }

    /// Until faces were resolved every cached file was copied, drawn or not; now the
    /// italic nothing draws stays behind. IBM Plex Mono, because it ships a static file
    /// per face, as IBM Plex Sans no longer does.
    @Test("The file of each text face drawn is copied from the font cache into the module's resources, and no other")
    func copiesTextFonts() throws {
        let fixture = try CommandFixture(fixture: "layout-nested.pen")
        let mono = ["IBMPlexMono-Bold.ttf", "IBMPlexMono-Regular.ttf"]
        try fixture.seedFontCache(family: "IBM Plex Mono", files: (mono + ["IBMPlexMono-Italic.ttf"]).map { "GoogleFonts/\($0)" })
        let pen = fixture.root.appendingPathComponent("text.pen")
        let json = ##"{"version": "2.17", "children": [{"type": "frame", "id": "b", "name": "Board", "width": 10, "height": 10, "children": [{"type": "text", "id": "t", "content": "Hi", "fontFamily": "IBM Plex Mono"}, {"type": "text", "id": "m", "content": "Hi", "fontFamily": "IBM Plex Mono", "fontWeight": "700"}]}]}"##
        try Data(json.utf8).write(to: pen)
        let output = fixture.root.appendingPathComponent("ui", isDirectory: true)
        let run = try fixture.run("generate", "swiftui", pen.path, "--output", output.path, "--name", "Acme")

        #expect(run.status == 0, "\(run.stderr)")
        for name in mono {
            let copied = output.appendingPathComponent("Sources/Acme/Resources/\(name)")
            let source = CommandFixture.testFonts.appendingPathComponent("GoogleFonts/\(name)")
            #expect(FileManager.default.contents(atPath: copied.path) == FileManager.default.contents(atPath: source.path), "\(name)")
        }
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("Sources/Acme/Resources/IBMPlexMono-Italic.ttf").path))
        #expect(run.stdout.contains("+ 2 text font(s)"))
    }

    @Test("A family the OS ships is not bundled, and is not a warning")
    func systemFamilyNotBundled() throws {
        let fixture = try CommandFixture(fixture: "layout-nested.pen")
        let pen = fixture.root.appendingPathComponent("text.pen")
        let json = ##"{"version": "2.17", "children": [{"type": "frame", "id": "b", "name": "Board", "width": 10, "height": 10, "children": [{"type": "text", "id": "t", "content": "Hi", "fontFamily": "Helvetica"}]}]}"##
        try Data(json.utf8).write(to: pen)
        let output = fixture.root.appendingPathComponent("ui", isDirectory: true)
        let run = try fixture.run("generate", "swiftui", pen.path, "--output", output.path, "--name", "Acme")

        #expect(run.status == 0, "\(run.stderr)")
        #expect(!run.stdout.contains("text font(s)"))
        #expect(!run.stderr.contains("Helvetica"))
        let resources = try FileManager.default.contentsOfDirectory(atPath: output.appendingPathComponent("Sources/Acme/Resources").path)
        #expect(resources == [".gitkeep"])
    }

    @Test("A file that is not there is exit 4")
    func missingFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "layout-nested.pen")
        let run = try fixture.run("generate", "swiftui", fixture.root.appendingPathComponent("gone.pen").path)
        #expect(run.status == ExitCode.targetFailure.rawValue)
    }
}
