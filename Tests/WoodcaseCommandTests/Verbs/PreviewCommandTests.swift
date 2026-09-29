//
//  PreviewCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore
import WoodcaseViewer

/// The `preview` verb, driven as a process.
///
/// Like `serve`, the running server never ends, so the cases that can drive the binary
/// to completion are the ones that print and stop: `--list`, `--list --json`, `--help`,
/// and the refusals. What the served pages contain is the viewer target's business
/// (`PreviewRoutesTests`); what is tested here is the adapter — the rows, the JSON, the
/// exit codes, and that none of it touches the disk.
struct PreviewCommandTests {
    /// Runs with no `$WOODCASE_HOME` override, so the project-local default is what
    /// would be used if the verb touched a log at all. It must not.
    private static let noOverride = [ActivityLog.homeEnvironmentVariable: ""]

    /// Every `component/state` pair the catalog declares.
    private static var pairs: [(component: PreviewComponent, state: PreviewState)] {
        PreviewCatalog.all.flatMap { component in
            component.states.map { (component, $0) }
        }
    }

    @Test("--help works with nothing set up, and names the flags")
    func helpHasNoPreconditions() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("preview", "--help")

        #expect(run.status == 0)
        #expect(run.stdout.contains("--port"))
        #expect(run.stdout.contains("--open"))
        #expect(run.stdout.contains("--list"))
    }

    @Test("The verb is listed in the tool's own primer")
    func verbIsDiscoverable() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("--help")

        #expect(run.stdout.contains("preview"))
    }

    @Test("--list prints one row per state, with its frame and its path, and exits 0")
    func listPrintsEveryState() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(["preview", "--list"], environment: Self.noOverride)

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == Self.pairs.count)

        for (component, state) in Self.pairs {
            let row = "\(component.slug)/\(state.slug)  \(state.frame.rawValue)  "
                + "/preview/\(component.slug)/\(state.slug)"
            #expect(run.stdoutLines.contains(row), "no row for \(component.slug)/\(state.slug)")
        }
    }

    @Test("--list names no host and no port: the base is the running verb's to report")
    func listNamesNoOrigin() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(["preview", "--list"], environment: Self.noOverride)

        #expect(run.status == 0)
        #expect(!run.stdout.contains("http://"))
        #expect(!run.stdout.contains("127.0.0.1"))
        #expect(!run.stdout.contains(":7333"))
    }

    @Test("--port cannot change what --list prints, because a path has no port in it")
    func listIgnoresThePort() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let bare = try fixture.run(["preview", "--list"], environment: Self.noOverride)
        let pinned = try fixture.run(
            ["preview", "--list", "--port", "8123"], environment: Self.noOverride
        )

        #expect(pinned.status == 0)
        #expect(pinned.stdout == bare.stdout)
        #expect(!pinned.stdout.contains("8123"))
    }

    @Test("--list --json is the catalog's metadata plus a path for every component and state")
    func listJSONCarriesTheCatalog() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(["preview", "--list", "--json"], environment: Self.noOverride)

        #expect(run.status == 0)
        let decoded = try JSONDecoder().decode(
            [Preview.Listing.Component].self, from: Data(run.stdout.utf8)
        )
        #expect(decoded.count == PreviewCatalog.all.count)

        for (listed, component) in zip(decoded, PreviewCatalog.all) {
            #expect(listed.slug == component.slug)
            #expect(listed.title == component.title)
            #expect(listed.blurb == component.blurb)
            #expect(listed.source == component.source)
            #expect(listed.path == "/preview/\(component.slug)")
            #expect(listed.states.count == component.states.count)
            for (row, state) in zip(listed.states, component.states) {
                #expect(row.slug == state.slug)
                #expect(row.name == state.name)
                #expect(row.note == state.note)
                #expect(row.frame == state.frame)
                #expect(row.path == "/preview/\(component.slug)/\(state.slug)")
            }
        }
        // A path joins to the base the running verb reports; nothing here assumes one.
        #expect(!run.stdout.contains("http://"))
    }

    @Test("--list creates nothing on disk: no .woodcase, no log, no file at all")
    func listWritesNothing() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Set(FileManager.default.contentsOfDirectory(atPath: fixture.root.path))

        let run = try fixture.run(["preview", "--list"], environment: Self.noOverride)
        #expect(run.status == 0)

        let logDirectory = fixture.root.appendingPathComponent(ActivityLog.directoryName)
        #expect(!FileManager.default.fileExists(atPath: logDirectory.path))

        // The run's own stdout/stderr capture files are the only new entries.
        let after = try Set(FileManager.default.contentsOfDirectory(atPath: fixture.root.path))
        #expect(after.subtracting(before).allSatisfy { $0.hasPrefix("stdout-") || $0.hasPrefix("stderr-") })
    }

    @Test("A component that is not in the catalog is exit 2, listing the ones that are")
    func unknownComponentIsUsageListingTheCatalog() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(["preview", "avatr"], environment: Self.noOverride)

        #expect(run.status == 2)
        #expect(run.stderr.contains("avatr"))
        for component in PreviewCatalog.all {
            #expect(run.stderr.contains(component.slug), "the refusal does not name \(component.slug)")
        }
        // Nothing was bound: the refusal happens before the port, so stdout stays empty.
        #expect(run.stdout.isEmpty)
    }

    @Test("A state that component does not have is exit 2, listing the states it does")
    func unknownStateIsUsageListingTheStates() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let component = PreviewCatalog.all[0]
        let run = try fixture.run(["preview", "\(component.slug)/nope"], environment: Self.noOverride)

        #expect(run.status == 2)
        #expect(run.stderr.contains("nope"))
        for state in component.states {
            #expect(run.stderr.contains(state.slug), "the refusal does not name \(state.slug)")
        }
        #expect(run.stdout.isEmpty)
    }

    @Test("--list with a component named is refused rather than half-honored")
    func listAndATargetIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(["preview", "--list", PreviewCatalog.all[0].slug], environment: Self.noOverride)

        #expect(run.status == 2)
        #expect(run.stderr.contains("--list"))
    }

    @Test("--list with --open is refused: there is no server to open")
    func listAndOpenIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(["preview", "--list", "--open"], environment: Self.noOverride)

        #expect(run.status == 2)
        #expect(run.stderr.contains("--open"))
    }

    @Test("A running preview serves the catalog at the URL it printed, and nothing else")
    func theRunningVerbServesWhatItPrinted() async throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let component = PreviewCatalog.all[0]
        // A port base away from the real 7333, which another viewer — a person's or
        // another agent's — may already hold; the same reason `serve` has the flag.
        let run = try fixture.runInBackground(
            ["preview", component.slug, "--port-base", "7811"],
            environment: Self.noOverride
        )
        defer { run.stop() }

        guard let line = run.firstLine(), let url = URL(string: line) else {
            Issue.record("preview did not print a URL before its budget ran out: \(run.stderrText)")
            return
        }
        #expect(url.path == "/preview/\(component.slug)")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains(component.title))

        // No files, no log, no watcher: nothing was created beside the fixture.
        let logDirectory = fixture.root.appendingPathComponent(ActivityLog.directoryName)
        #expect(!FileManager.default.fileExists(atPath: logDirectory.path))
    }

    @Test("The started report is the documented shape")
    func startedReportShape() throws {
        let json = try CanonicalJSON.text(Preview.Started(
            url: "http://127.0.0.1:7333/preview", port: 7333, components: 23, states: 38
        ))
        #expect(json.contains("\"url\": \"http://127.0.0.1:7333/preview\""))
        #expect(json.contains("\"port\": 7333"))
        #expect(json.contains("\"components\": 23"))
        #expect(json.contains("\"states\": 38"))
    }

    @Test("Flags parse in the house's order and shape")
    func flagsParse() throws {
        let command = try Preview.parse(["--port", "0", "--open", "outline-panel/default"])
        #expect(command.port == 0)
        #expect(command.open)
        #expect(!command.list)
        #expect(command.target == "outline-panel/default")

        let bare = try Preview.parse([])
        #expect(bare.port == nil)
        #expect(bare.target == nil)
        #expect(!bare.open)
    }
}
