//
//  PenFileFollowerContractTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase

/// The contract Penumbra follows a document by, driven through the real binary: an
/// attributed write arrives as a change naming its writer and nodes, on a bare `.pen`
/// and on a `.umbra` bundle alike, and following survives a delete-then-recreate write.
@Suite(.timeLimit(.minutes(8)))
struct PenFileFollowerContractTests {
    /// The log a fixture's runs append to for a bare `.pen`.
    private static func log(_ fixture: CommandFixture) -> ActivityLog {
        ActivityLog(home: fixture.home, origin: .environmentOverride)
    }

    @Test("`woodcase set --as claude` on a bare .pen arrives as an attributed change with node ids")
    func setOnABareFileIsAttributed() async throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let recorder = FollowerRecorder(PenFileFollower(
            file: fixture.file, log: Self.log(fixture), matchWindow: .seconds(60)
        ))
        defer { recorder.cancel() }

        let run = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--as", "claude")
        #expect(run.status == 0, "\(run.stderr)")

        let event = await recorder.next("the attributed change") { $0.change?.isAttributed == true }
        let change = try #require(event?.change)
        #expect(change.identities == ["claude"])
        #expect(!change.nodes.isEmpty)
        #expect(change.revision != nil)
    }

    @Test("`woodcase set --as claude` on a .umbra bundle arrives through the bundle's own log")
    func setOnABundleIsAttributed() async throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let bundle = fixture.root.appendingPathComponent("Design.umbra")
        let made = try fixture.run("new", bundle.path, "--as", "ana")
        #expect(made.status == 0, "\(made.stderr)")
        let subtree = fixture.root.appendingPathComponent("hero.json")
        try #"{"type":"frame","name":"Hero","width":10,"height":10}"#.write(to: subtree, atomically: true, encoding: .utf8)

        // No log passed: a bundle's is inside it, whatever $WOODCASE_HOME says.
        let recorder = FollowerRecorder(PenFileFollower(file: bundle, matchWindow: .seconds(60)))
        defer { recorder.cancel() }

        let run = try fixture.run("add", bundle.path, "document", "-F", subtree.path, "--as", "claude")
        #expect(run.status == 0, "\(run.stderr)")

        let event = await recorder.next("the attributed change") { $0.change?.isAttributed == true }
        let change = try #require(event?.change)
        #expect(change.identities == ["claude"])
        #expect(!change.nodes.isEmpty)
    }

    @Test("`woodcase get --as claude` arrives as a view with node ids and the revision")
    func attributedGetIsAView() async throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let recorder = FollowerRecorder(PenFileFollower(file: fixture.file, log: Self.log(fixture)))
        defer { recorder.cancel() }

        let run = try fixture.run("get", fixture.file.path, "Canvas/Title", "--as", "claude")
        #expect(run.status == 0, "\(run.stderr)")

        let event = await recorder.next("the view") { $0.view != nil }
        let view = try #require(event?.view)
        #expect(view.identity == "claude")
        #expect(view.verb == .get)
        #expect(view.nodes == [String(run.stdoutLines[0].split(separator: " ")[0])])
        let header = try #require(try fixture.run("tree", fixture.file.path, "--depth", "0").stdoutLines.first)
        #expect(view.revision == String(header.split(separator: " ")[1]))
    }

    @Test("Following continues through a delete-then-recreate write")
    func followsThroughDeleteThenRecreate() async throws {
        let fixture = try CommandFixture(fixture: "batch.pen", editedOutsideWoodcase: true)
        let original = try Data(contentsOf: fixture.file)
        let recorder = FollowerRecorder(PenFileFollower(
            file: fixture.file, log: Self.log(fixture), matchWindow: .seconds(60)
        ))
        defer { recorder.cancel() }

        let first = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=One", "--as", "claude")
        #expect(first.status == 0, "\(first.stderr)")
        _ = await recorder.next("the first change") { $0.change?.isAttributed == true }

        // A writer that deletes the file and writes a new one in its place.
        try FileManager.default.removeItem(at: fixture.file)
        try await Task.sleep(for: .milliseconds(150))
        try original.write(to: fixture.file)

        let second = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=Two", "--as", "claude")
        #expect(second.status == 0, "\(second.stderr)")
        let event = await recorder.next("the change after the recreate") {
            $0.change?.events.contains { $0.identity == "claude" && $0.op == .set } == true
        }
        #expect(event?.change?.nodes.isEmpty == false)
    }
}
