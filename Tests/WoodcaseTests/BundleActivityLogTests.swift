//
//  BundleActivityLogTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A bundle keeps its own history: its log is `<bundle>/.woodcase/activity.jsonl`
/// wherever the bundle sits, and it travels with the bundle.
struct BundleActivityLogTests {
    private func withScratch<T>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleActivityLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory.resolvingSymlinksInPath())
    }

    private static func event(file: URL, revision: String = "r1") -> ActivityEvent {
        ActivityEvent(time: Date(), identity: "ana", file: file, op: .set, revision: revision)
    }

    @Test("a bundle's log is its own .woodcase, even inside a repository")
    func bundleLogIsInsideTheBundle() async throws {
        try await withScratch { scratch in
            try FileManager.default.createDirectory(
                at: scratch.appendingPathComponent(".git"), withIntermediateDirectories: true
            )
            let bundle = scratch.appendingPathComponent("designs/Design.umbra")

            let log = ActivityLogLocation.log(for: bundle, environment: [:])

            #expect(log.fileURL.path == bundle.path + "/.woodcase/activity.jsonl")
            #expect(log.origin == .bundle(root: URL(fileURLWithPath: bundle.path, isDirectory: true), repository: URL(fileURLWithPath: scratch.path, isDirectory: true)))
            #expect(log.origin.repositoryRoot?.path == scratch.path)
        }
    }

    @Test("naming the document.pen inside a bundle finds the bundle's log")
    func innerDocumentFindsTheBundleLog() async throws {
        try await withScratch { scratch in
            let bundle = scratch.appendingPathComponent("Design.umbra")
            let inner = bundle.appendingPathComponent("document.pen")

            #expect(
                ActivityLogLocation.log(for: inner, environment: [:]).fileURL
                    == ActivityLogLocation.log(for: bundle, environment: [:]).fileURL
            )
        }
    }

    @Test("$WOODCASE_HOME does not move a bundle's log: the history travels with the bundle")
    func environmentOverrideDoesNotMoveABundleLog() async throws {
        try await withScratch { scratch in
            let bundle = scratch.appendingPathComponent("Design.umbra")
            let environment = [ActivityLog.homeEnvironmentVariable: scratch.appendingPathComponent("home").path]

            let log = ActivityLogLocation.log(for: bundle, environment: environment)

            #expect(log.fileURL.path == bundle.path + "/.woodcase/activity.jsonl")
        }
    }

    @Test("a bare .pen still honors $WOODCASE_HOME")
    func bareFileStillHonorsTheOverride() async throws {
        try await withScratch { scratch in
            let home = scratch.appendingPathComponent("home")
            let file = scratch.appendingPathComponent("Design.pen")

            let log = ActivityLogLocation.log(for: file, environment: [ActivityLog.homeEnvironmentVariable: home.path])

            #expect(log.origin == .environmentOverride)
            #expect(log.home.path == home.path)
        }
    }

    @Test("the first append to a bundle log inside a repository ignores .woodcase/ there")
    func bundleLogIgnoresItselfInTheRepository() async throws {
        try await withScratch { scratch in
            try FileManager.default.createDirectory(
                at: scratch.appendingPathComponent(".git"), withIntermediateDirectories: true
            )
            let bundle = scratch.appendingPathComponent("Design.umbra")
            let log = ActivityLogLocation.log(for: bundle, environment: [:])

            try await log.append([Self.event(file: bundle)])

            #expect(FileManager.default.fileExists(atPath: bundle.path + "/.woodcase/activity.jsonl"))
            let ignore = try String(contentsOf: scratch.appendingPathComponent(".gitignore"), encoding: .utf8)
            #expect(ignore.contains(ActivityLog.ignorePattern))
        }
    }

    // MARK: - File identity

    @Test("events name a bundle by its document, however the caller spelled it")
    func eventsNameTheBundleDocument() {
        let bundle = URL(fileURLWithPath: "/tmp/Design.umbra")

        #expect(ActivityEvent.canonicalPath(for: bundle).hasSuffix("/Design.umbra/document.pen"))
        #expect(
            ActivityEvent.canonicalPath(for: bundle)
                == ActivityEvent.canonicalPath(for: bundle.appendingPathComponent("document.pen"))
        )
    }

    @Test("a bundle's log answers for its document after the bundle is renamed")
    func renamedBundleKeepsItsHistory() async throws {
        try await withScratch { scratch in
            let before = scratch.appendingPathComponent("Before.umbra")
            try FileManager.default.createDirectory(at: before, withIntermediateDirectories: true)
            try await ActivityLogLocation.log(for: before, environment: [:]).append([Self.event(file: before, revision: "r7")])

            let after = scratch.appendingPathComponent("After.umbra")
            try FileManager.default.moveItem(at: before, to: after)
            let reader = ActivityReader(log: ActivityLogLocation.log(for: after, environment: [:]))

            #expect(try reader.newest(file: after)?.revision == "r7")
            #expect(try reader.read(file: after).events.count == 1)
            #expect(try reader.tail(count: 5, file: after).count == 1)
        }
    }

    @Test("a log outside a bundle still filters by file")
    func otherLogsStillFilter() async throws {
        try await withScratch { scratch in
            let log = ActivityLog(home: scratch.appendingPathComponent("home"))
            try await log.append([Self.event(file: scratch.appendingPathComponent("a.pen"))])

            #expect(try ActivityReader(log: log).newest(file: scratch.appendingPathComponent("b.pen")) == nil)
        }
    }
}
