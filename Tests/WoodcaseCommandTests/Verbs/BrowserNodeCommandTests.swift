//
//  BrowserNodeCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// What an agent sees of a Pen 2.19 `browser` node through the CLI: its real size in
/// `tree`, and its keys through `get`/`set`.
@Suite("A browser node through the CLI")
struct BrowserNodeCommandTests {
    @Test("`tree` shows a browser at its declared size, and the column around it grows to fit")
    func treeShowsRealSize() throws {
        let fixture = try CommandFixture(fixture: "browser.pen")
        let run = try fixture.run("tree", fixture.file.path)
        #expect(run.status == 0)
        let web = try #require(run.stdoutLines.first { $0.hasSuffix("BrWeb") })
        #expect(web.contains("browser"))
        #expect(web.contains("10,60 300×120"))
        let device = try #require(run.stdoutLines.first { $0.hasSuffix("BrDev") })
        #expect(device.contains("10,190 300×90"))
        let root = try #require(run.stdoutLines.first { $0.hasSuffix("BrRt0") })
        #expect(root.contains("0,0 320×390"))
    }

    @Test("`set` writes a browser's url and `get` reads it back")
    func setAndGetURL() throws {
        let fixture = try CommandFixture(fixture: "browser.pen")
        let set = try fixture.run("set", fixture.file.path, "BrWeb", "kind.url=pen.dev", "--as", "t")
        #expect(set.status == 0, "set failed: \(set.stderr)")
        let get = try fixture.run("get", fixture.file.path, "BrWeb")
        #expect(get.status == 0)
        #expect(get.stdout.contains(#""url": "pen.dev""#))
        #expect(get.stdout.contains(#""type": "browser""#))
    }
}
