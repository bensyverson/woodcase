//
//  PenLocationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// ``PenLocation`` turns a path someone named — a bare `.pen`, a `.umbra` bundle, or the
/// `document.pen` inside one — into the file to read and write, the folder relative
/// paths resolve against, and where the bundle keeps its own state.
struct PenLocationTests {
    private static let folder = URL(fileURLWithPath: "/tmp/designs", isDirectory: true)

    // MARK: - Bare files

    @Test("a bare .pen is its own document, resolving relative paths against its folder")
    func bareFile() {
        let file = Self.folder.appendingPathComponent("Design.pen")

        let location = PenLocation(file)

        #expect(location.kind == .file)
        #expect(location.document == file)
        #expect(location.bundle == nil)
        #expect(location.resourceDirectory.path == Self.folder.path)
        #expect(location.containingDirectory.path == Self.folder.path)
        #expect(location.stateDirectory == nil)
        #expect(location.temporaryDirectory.path == Self.folder.path)
        #expect(location.name == "Design")
    }

    @Test("a bare file keeps the URL it was given, so callers comparing it see no change")
    func bareFileKeepsItsSpelling() {
        let file = URL(fileURLWithPath: "/tmp/designs/../designs/Design.pen")

        #expect(PenLocation(file).document == file)
    }

    @Test("a file named document.pen outside a bundle is a bare file")
    func documentPenOutsideABundle() {
        let file = Self.folder.appendingPathComponent(PenLocation.documentName)

        #expect(PenLocation(file).kind == .file)
        #expect(PenLocation(file).document == file)
    }

    // MARK: - Bundles

    @Test("a bundle's document is document.pen, and its assets resolve inside it")
    func bundle() {
        let bundle = Self.folder.appendingPathComponent("Design.umbra", isDirectory: true)

        let location = PenLocation(bundle)

        #expect(location.kind == .bundle)
        #expect(location.bundle?.path == bundle.path)
        #expect(location.document.path == bundle.path + "/document.pen")
        #expect(location.resourceDirectory.path == bundle.path)
        #expect(location.containingDirectory.path == Self.folder.path)
        #expect(location.stateDirectory?.path == bundle.path + "/.woodcase")
        #expect(location.temporaryDirectory.path == bundle.path + "/.woodcase")
        #expect(location.name == "Design")
    }

    @Test("the document.pen inside a bundle names the same bundle")
    func documentInsideBundle() {
        let bundle = Self.folder.appendingPathComponent("Design.umbra", isDirectory: true)
        let inner = bundle.appendingPathComponent("document.pen")

        let location = PenLocation(inner)

        #expect(location.kind == .bundle)
        #expect(location.bundle?.path == bundle.path)
        #expect(location.document.path == inner.path)
        #expect(location == PenLocation(bundle))
    }

    @Test("a bundle path with a trailing slash, or no directory hint, is the same bundle")
    func bundleSpellings() {
        let slashed = PenLocation(URL(fileURLWithPath: "/tmp/designs/Design.umbra/"))
        let bare = PenLocation(URL(fileURLWithPath: "/tmp/designs/Design.umbra", isDirectory: false))

        #expect(slashed.kind == .bundle)
        #expect(bare.kind == .bundle)
        #expect(slashed.document.path == bare.document.path)
    }

    @Test("the extension is matched without regard to case")
    func extensionCase() {
        #expect(PenLocation(Self.folder.appendingPathComponent("Design.UMBRA")).kind == .bundle)
    }

    @Test("isBundle answers from the path alone")
    func isBundle() {
        #expect(PenLocation.isBundle(Self.folder.appendingPathComponent("A.umbra")))
        #expect(!PenLocation.isBundle(Self.folder.appendingPathComponent("A.pen")))
    }
}
