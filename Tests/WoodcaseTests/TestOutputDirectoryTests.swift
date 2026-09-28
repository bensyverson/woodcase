//
//  TestOutputDirectoryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing

/// The per-process output directory the rendering suites share: one per process,
/// created on first use, and never the fixed path two suites used to fight over.
@Suite("TestOutputDirectory")
struct TestOutputDirectoryTests {
    @Test("Answers the same directory on every call in this process")
    func sameDirectoryEveryCall() {
        let first = TestOutputDirectory.url
        let second = TestOutputDirectory.url
        #expect(first == second)
    }

    @Test("The directory exists once it has been used")
    func directoryExists() {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: TestOutputDirectory.url.path, isDirectory: &isDirectory
        )
        #expect(exists)
        #expect(isDirectory.boolValue)
    }

    @Test("Is not the old shared fixed path")
    func notTheOldSharedPath() {
        #expect(TestOutputDirectory.url.path != "/tmp/pen-exports")
        #expect(TestOutputDirectory.url.path != "/private/tmp/pen-exports")
    }

    @Test("The webview-regression subfolder sits under the process directory")
    func webViewRegressionSubfolder() {
        #expect(
            TestOutputDirectory.webViewRegressionURL.deletingLastPathComponent().path
                == TestOutputDirectory.url.path
        )
        #expect(TestOutputDirectory.webViewRegressionURL.lastPathComponent == "webview-regression")

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: TestOutputDirectory.webViewRegressionURL.path, isDirectory: &isDirectory
        )
        #expect(exists)
        #expect(isDirectory.boolValue)
    }
}

/// Each run sweeps the folders that runs which have since exited left behind, so test
/// output no longer piles up in the temporary directory one 65 MB folder per run.
@Suite("TestOutputDirectory sweep")
struct TestOutputDirectorySweepTests {
    /// A fresh parent directory standing in for the system temporary directory.
    private func makeParent() throws -> URL {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestOutputDirectorySweepTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return parent
    }

    private func makeFolder(_ name: String, in parent: URL) throws {
        try FileManager.default.createDirectory(
            at: parent.appendingPathComponent(name), withIntermediateDirectories: true
        )
    }

    private func contents(of parent: URL) throws -> Set<String> {
        try Set(FileManager.default.contentsOfDirectory(atPath: parent.path))
    }

    @Test("Preparing creates this process's folder and removes those of exited processes")
    func removesExitedProcessFolders() throws {
        let parent = try makeParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        try makeFolder("pen-exports-111", in: parent)
        try makeFolder("pen-exports-222", in: parent)

        let url = TestOutputDirectory.prepare(
            in: parent, processIdentifier: 333, environment: [:], isAlive: { _ in false }
        )

        #expect(url.lastPathComponent == "pen-exports-333")
        #expect(try contents(of: parent) == ["pen-exports-333"])
    }

    @Test("A folder whose process is still running survives the sweep")
    func keepsLiveProcessFolders() throws {
        let parent = try makeParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        try makeFolder("pen-exports-111", in: parent)
        try makeFolder("pen-exports-222", in: parent)

        _ = TestOutputDirectory.prepare(
            in: parent, processIdentifier: 333, environment: [:], isAlive: { $0 == 222 }
        )

        #expect(try contents(of: parent) == ["pen-exports-222", "pen-exports-333"])
    }

    @Test("Folders that are not pen-exports-<pid> are left alone")
    func leavesUnrelatedFolders() throws {
        let parent = try makeParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        for name in ["pen-exports", "pen-exports-abc", "pen-exports-12x", "other-111"] {
            try makeFolder(name, in: parent)
        }

        _ = TestOutputDirectory.prepare(
            in: parent, processIdentifier: 333, environment: [:], isAlive: { _ in false }
        )

        #expect(try contents(of: parent) == [
            "pen-exports", "pen-exports-abc", "pen-exports-12x", "other-111", "pen-exports-333",
        ])
    }

    @Test("The keep-output variable turns the sweep off")
    func keepVariableDisablesSweep() throws {
        let parent = try makeParent()
        defer { try? FileManager.default.removeItem(at: parent) }
        try makeFolder("pen-exports-111", in: parent)

        _ = TestOutputDirectory.prepare(
            in: parent,
            processIdentifier: 333,
            environment: [TestOutputDirectory.keepVariable: "1"],
            isAlive: { _ in false }
        )

        #expect(try contents(of: parent) == ["pen-exports-111", "pen-exports-333"])
    }

    @Test("This process counts as alive and a reaped child does not")
    func processLiveness() throws {
        #expect(TestOutputDirectory.isProcessAlive(ProcessInfo.processInfo.processIdentifier))

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        #expect(!TestOutputDirectory.isProcessAlive(child.processIdentifier))
    }
}
