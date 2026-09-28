//
//  WoodcaseResourcesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@Suite("WoodcaseResources")
struct WoodcaseResourcesTests {
    /// A scratch directory laid out like an install: `libexec/` holds the binary and
    /// (optionally) its bundle, and `bin/woodcase` is a relative symlink to the binary.
    private struct Install {
        let root: URL
        let libexec: URL
        let binary: URL
        let link: URL

        init(withBundle: Bool) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("WoodcaseResourcesTests-\(UUID().uuidString)", isDirectory: true)
            libexec = root.appendingPathComponent("libexec", isDirectory: true)
            let bin = root.appendingPathComponent("bin", isDirectory: true)
            try FileManager.default.createDirectory(at: libexec, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            binary = libexec.appendingPathComponent("woodcase")
            FileManager.default.createFile(atPath: binary.path, contents: Data())
            link = bin.appendingPathComponent("woodcase")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../libexec/woodcase")
            if withBundle {
                try FileManager.default.createDirectory(
                    at: libexec.appendingPathComponent(WoodcaseResources.bundleName, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test("The bundle is found beside the binary a symlink points at")
    func followsTheSymlink() throws {
        let install = try Install(withBundle: true)
        defer { install.remove() }

        let bundle = try WoodcaseResources.locate(in: WoodcaseResources.searchDirectories(executable: install.link, others: []))

        #expect(bundle.bundleURL.resolvingSymlinksInPath().lastPathComponent == WoodcaseResources.bundleName)
        #expect(
            bundle.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent().path
                == install.libexec.resolvingSymlinksInPath().path
        )
    }

    @Test("The directory the executable was invoked from is searched before the symlink's target")
    func invokedDirectoryFirst() throws {
        let install = try Install(withBundle: true)
        defer { install.remove() }

        let directories = WoodcaseResources.searchDirectories(executable: install.link, others: [])

        #expect(directories.map(\.lastPathComponent) == ["bin", "libexec"])
    }

    @Test("A missing bundle throws an error that names the bundle, the places searched and the fix")
    func missingBundle() throws {
        let install = try Install(withBundle: false)
        defer { install.remove() }
        let directories = WoodcaseResources.searchDirectories(executable: install.link, others: [])

        #expect {
            try WoodcaseResources.locate(in: directories)
        } throws: { error in
            guard let missing = error as? WoodcaseResources.Missing else { return false }
            let message = missing.description
            return missing.searched == directories
                && message.contains(WoodcaseResources.bundleName)
                && message.contains(install.libexec.lastPathComponent)
                && message.contains("scripts/install")
        }
    }

    @Test("The test process finds the real bundle, and the SwiftUI templates in it")
    func realBundle() throws {
        let bundle = try WoodcaseResources.bundle()
        let templates = bundle.urls(forResourcesWithExtension: "swift", subdirectory: "SwiftUITemplates") ?? []
        #expect(templates.contains { $0.lastPathComponent == "PenSupport.swift" })
    }
}
