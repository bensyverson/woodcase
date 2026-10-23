//
//  BundleCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Every verb takes a `.umbra` bundle where it takes a `.pen`, and a bundle's history
/// lands in its own `history/` — `$WOODCASE_HOME` notwithstanding (moved from
/// `.woodcase/activity.jsonl` on 2026-10-23, leaf KAJTF3).
@Suite("woodcase on bundles")
struct BundleCommandTests {
    /// A subtree `add` can grow a design with.
    private static let hero = #"{"type":"frame","name":"Hero","width":10,"height":10}"#

    private func makeBundle(_ fixture: CommandFixture, named name: String = "Design.umbra") throws -> URL {
        let bundle = fixture.root.appendingPathComponent(name)
        let run = try fixture.run("new", bundle.path, "--as", "ana")
        #expect(run.status == 0, "\(run.stderr)")
        let subtree = fixture.root.appendingPathComponent("hero.json")
        try Self.hero.write(to: subtree, atomically: true, encoding: .utf8)
        let add = try fixture.run("add", bundle.path, "document", "-F", subtree.path, "--as", "ana")
        #expect(add.status == 0, "\(add.stderr)")
        return bundle
    }

    private func bundleRows(_ bundle: URL) throws -> [ActivityEvent] {
        try ActivityReader(log: ActivityLogLocation.log(for: bundle, environment: [:])).read().events
    }

    @Test("new X.umbra creates a bundle holding document.pen, and logs `new` inside it")
    func newCreatesABundle() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let bundle = fixture.root.appendingPathComponent("Design.umbra")

        let run = try fixture.run("new", bundle.path, "--as", "ana")

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("document.pen").path))
        #expect(try bundleRows(bundle).map(\.op) == [.new])
        #expect(!FileManager.default.fileExists(atPath: fixture.activityLog.path))
    }

    @Test("read and write verbs work on a bundle, and every row lands in its history")
    func verbsWorkOnABundle() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let bundle = try makeBundle(fixture)
        let path = bundle.path

        for arguments in [
            ["tree", path],
            ["get", path, "Hero"],
            ["find", path, "r => r.type === 'frame'"],
            ["lint", path],
            ["vars", "list", path],
            ["imports", "list", path],
            ["set", path, "Hero", "common.name=Banner", "--as", "ana"],
            ["shot", path, "Banner", "--out", fixture.root.appendingPathComponent("banner.png").path],
            ["rm", path, "Banner", "--as", "ana"],
            ["undo", path, "--as", "ana"],
            ["cp", path, "Banner", "document", "--as", "ana"],
            ["vars", "set", path, "accent=#FF0000", "--as", "ana"],
            ["activity", path],
        ] {
            let run = try fixture.run(arguments)
            #expect(run.status == 0, "\(arguments.joined(separator: " ")): \(run.stderr)")
        }

        let ops = try bundleRows(bundle).map(\.op)
        #expect(ops.first == .new)
        #expect(ops.contains(.set))
        #expect(ops.count(where: { $0 == .add }) == 2)
        #expect(ops.contains(.rm))
        #expect(ops.contains(.undo))
        #expect(ops.contains(.var))
        #expect(!FileManager.default.fileExists(atPath: fixture.activityLog.path))
        let root = try FileManager.default.contentsOfDirectory(atPath: bundle.path).sorted()
        #expect(root == [".gitignore", ".woodcase", "document.pen", "history"])
    }

    @Test("the document.pen inside a bundle is the same document, with the same log")
    func innerDocumentIsTheBundle() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let bundle = try makeBundle(fixture)

        let run = try fixture.run(
            "set", bundle.appendingPathComponent("document.pen").path, "Hero", "common.name=Inner", "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(try bundleRows(bundle).last?.op == .set)
    }

    @Test("render writes beside the bundle, named after it")
    func renderWritesBesideTheBundle() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let bundle = try makeBundle(fixture)

        let run = try fixture.run("render", bundle.path)

        #expect(run.status == 0, "\(run.stderr)")
        let beside = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        #expect(beside.contains { $0.hasPrefix("Design") && $0.hasSuffix(".png") })
        #expect(try FileManager.default.contentsOfDirectory(atPath: bundle.path).sorted() == [".gitignore", ".woodcase", "document.pen", "history"])
    }

    @Test("a bundle with no document.pen is refused, naming what is missing")
    func emptyBundleIsRefused() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let bundle = fixture.root.appendingPathComponent("Empty.umbra")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        let run = try fixture.run("tree", bundle.path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("document.pen"))
    }

    // MARK: - bundle, unbundle, embed

    @Test("bundle then unbundle round-trips a .pen with a local image and font")
    func bundleThenUnbundle() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let project = fixture.root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project.appendingPathComponent("art"), withIntermediateDirectories: true)
        let fixtures = CommandFixture.packageRoot.appendingPathComponent("Tests/WoodcaseTests")
        try FileManager.default.copyItem(
            at: fixtures.appendingPathComponent("Fixtures/blur1.png"), to: project.appendingPathComponent("art/hero.png")
        )
        try FileManager.default.copyItem(
            at: fixtures.appendingPathComponent("Fonts/WoodcaseDeclaredMono.ttf"), to: project.appendingPathComponent("Mono.ttf")
        )
        let file = project.appendingPathComponent("Design.pen")
        try Data("""
        {"version": "\(PenDocument.currentFormatVersion)", "children": [
          {"type": "frame", "id": "card", "width": 100, "height": 100,
           "fill": {"type": "image", "url": "art/hero.png", "mode": "cover"}},
          {"type": "text", "id": "label", "content": "Hi", "fontFamily": "Woodcase Declared Mono"}
        ], "fonts": [{"name": "Woodcase Declared Mono", "url": "./Mono.ttf"}]}
        """.utf8).write(to: file)

        let bundled = try fixture.run("bundle", file.path, "--as", "ana")
        #expect(bundled.status == 0, "\(bundled.stderr)")
        let bundle = project.appendingPathComponent("Design.umbra")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("images/hero.png").path))
        #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("fonts/Mono.ttf").path))

        let out = fixture.root.appendingPathComponent("for-pen")
        let unbundled = try fixture.run("unbundle", bundle.path, "--to", out.path, "--as", "ana")
        #expect(unbundled.status == 0, "\(unbundled.stderr)")
        let exported = out.appendingPathComponent("Design.pen")
        let document = try PenParser.parse(contentsOf: exported)
        #expect(document.fonts?.first?.url == "./fonts/Mono.ttf")
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("images/hero.png").path))
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("fonts/Mono.ttf").path))
        let lint = try fixture.run("lint", exported.path)
        #expect(!lint.stderr.contains("does not exist"), "\(lint.stdout)\(lint.stderr)")
    }

    @Test("a command on a .pen a bundle was converted from warns to edit the bundle")
    func warnsOnTheConvertedOriginal() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let original = try Data(contentsOf: fixture.file)
        #expect(try fixture.run("bundle", fixture.file.path).status == 0)
        try original.write(to: fixture.file)

        let run = try fixture.run("tree", fixture.file.path)

        #expect(run.status == 0)
        #expect(run.stderr.contains("batch.pen was converted to batch.umbra on "))
        #expect(run.stderr.contains("edit that instead"))
    }

    @Test("embed refuses a bare .pen, pointing at bundle")
    func embedRefusesABareFile() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("embed", fixture.file.path)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("woodcase bundle"))
    }

    @Test("embed on a bundle with nothing remote downloads nothing and succeeds")
    func embedWithNothingRemote() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let bundle = try makeBundle(fixture)

        let run = try fixture.run("embed", bundle.path, "--json")

        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout.contains("\"files\" : 0"))
    }

    @Test("unbundle --history copies every writer's file into the folder's history/, and without it none")
    func unbundleHistoryFlag() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let bundle = try makeBundle(fixture)
        let history = bundle.appendingPathComponent("history")
        try Data("{}\n".utf8).write(to: history.appendingPathComponent("claude@mac.jsonl"))
        let written = try FileManager.default.contentsOfDirectory(atPath: history.path).sorted()
        #expect(written.count == 2)

        let without = fixture.root.appendingPathComponent("without")
        let plain = try fixture.run("unbundle", bundle.path, "--to", without.path)
        #expect(plain.status == 0, "\(plain.stderr)")
        #expect(!FileManager.default.fileExists(atPath: without.appendingPathComponent("history").path))
        #expect(!plain.stdout.contains("history"))

        let with = fixture.root.appendingPathComponent("with")
        let carried = try fixture.run("unbundle", bundle.path, "--to", with.path, "--history")
        #expect(carried.status == 0, "\(carried.stderr)")
        #expect(try FileManager.default.contentsOfDirectory(atPath: with.appendingPathComponent("history").path).sorted() == written)
        #expect(carried.stdout.contains("history   2 files"))
    }

    @Test("unbundle refuses a bare .pen")
    func unbundleRefusesABareFile() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("unbundle", fixture.file.path)

        #expect(run.status == ExitCode.usage.rawValue)
    }
}
