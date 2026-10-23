//
//  PenBundleImageStoreTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Images added to a bundle are stored once per content: named by a prefix of their
/// SHA-256 and the extension their bytes say they have, so the same image dropped or
/// pasted twice is one file that both fills reference.
struct PenBundleImageStoreTests {
    /// A PNG signature followed by a few bytes, so it sniffs as a PNG.
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data("oo7".utf8)

    /// The first 16 hex digits of `png`'s SHA-256 (`shasum -a 256`).
    private static let pngHash = "5280ed5c223e2c4a"

    /// A scratch folder holding one empty bundle.
    private struct Scratch {
        let root: URL
        let bundle: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("PenBundleImageStoreTests-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            bundle = root.appendingPathComponent("Design.umbra")
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        }

        var images: URL {
            bundle.appendingPathComponent("images")
        }

        func imageNames() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: images.path).sorted()
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test("adding the same image bytes twice writes one file and returns the same reference")
    func sameBytesStoredOnce() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }

        let first = try PenBundle.storeImage(Self.png, fileExtension: "png", in: scratch.bundle)
        let second = try PenBundle.storeImage(Self.png, fileExtension: "png", in: scratch.bundle)

        #expect(first == second)
        #expect(try scratch.imageNames() == ["\(Self.pngHash).png"])
        #expect(try Data(contentsOf: scratch.images.appendingPathComponent("\(Self.pngHash).png")) == Self.png)
    }

    @Test("the reference is ./images/ and 16 hex digits of the bytes' SHA-256, with the sniffed extension")
    func referenceIsTheContentHash() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }

        let reference = try PenBundle.storeImage(Self.png, fileExtension: "JPG", in: scratch.bundle)

        #expect(reference == "./images/\(Self.pngHash).png")
        #expect(PenBundle.imageFileName(for: Self.png, fileExtension: nil) == "\(Self.pngHash).png")
    }

    @Test("bytes no signature names keep the given extension, lowercased, or take .img")
    func unsniffedExtension() {
        let svg = Data("<svg/>".utf8)

        #expect(PenBundle.imageFileName(for: svg, fileExtension: "SVG").hasSuffix(".svg"))
        #expect(PenBundle.imageFileName(for: svg, fileExtension: nil).hasSuffix(".img"))
        #expect(PenBundle.imageFileName(for: svg, fileExtension: "").hasSuffix(".img"))
        #expect(PenBundle.imageFileName(for: svg, fileExtension: "../png").hasSuffix(".img"))
    }

    @Test("a dropped file and pasted bytes with the same content share one file")
    func droppedAndPastedShare() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let dropped = scratch.root.appendingPathComponent("Hero Shot.PNG")
        try Self.png.write(to: dropped)

        let fromFile = try PenBundle.storeImage(contentsOf: dropped, in: scratch.bundle)
        let fromPaste = try PenBundle.storeImage(Self.png, fileExtension: nil, in: scratch.bundle)

        #expect(fromFile == "./images/\(Self.pngHash).png")
        #expect(fromPaste == fromFile)
        #expect(try scratch.imageNames() == ["\(Self.pngHash).png"])
    }

    @Test("different bytes are different files")
    func differentBytesDifferentFiles() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }

        let first = try PenBundle.storeImage(Self.png, fileExtension: nil, in: scratch.bundle)
        let second = try PenBundle.storeImage(Self.png + Data([0]), fileExtension: nil, in: scratch.bundle)

        #expect(first != second)
        #expect(try scratch.imageNames().count == 2)
    }

    @Test("a different file under the hash's name is never overwritten, and the bytes are numbered past it")
    func occupiedNameIsNotOverwritten() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(at: scratch.images, withIntermediateDirectories: true)
        let squatter = scratch.images.appendingPathComponent("\(Self.pngHash).png")
        try Data("not the image".utf8).write(to: squatter)

        let first = try PenBundle.storeImage(Self.png, fileExtension: nil, in: scratch.bundle)
        let second = try PenBundle.storeImage(Self.png, fileExtension: nil, in: scratch.bundle)

        #expect(first == "./images/\(Self.pngHash)-2.png")
        #expect(second == first)
        #expect(try Data(contentsOf: squatter) == Data("not the image".utf8))
        #expect(try scratch.imageNames() == ["\(Self.pngHash)-2.png", "\(Self.pngHash).png"])
    }

    @Test("a file already inside the bundle is not copied: its own path is returned")
    func insideFileIsNotCopied() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(at: scratch.images, withIntermediateDirectories: true)
        let inside = scratch.images.appendingPathComponent("hero.png")
        try Self.png.write(to: inside)

        let reference = try PenBundle.storeImage(contentsOf: inside, in: scratch.bundle)

        #expect(reference == "./images/hero.png")
        #expect(try scratch.imageNames() == ["hero.png"])
    }

    @Test("storing leaves no temporary file behind")
    func noDebris() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }

        _ = try PenBundle.storeImage(Self.png, fileExtension: nil, in: scratch.bundle)
        _ = try PenBundle.storeImage(Self.png, fileExtension: nil, in: scratch.bundle)

        let state = scratch.bundle.appendingPathComponent(".woodcase")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: state.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test("storing into a bare file is refused")
    func bareFileRefused() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let bare = scratch.root.appendingPathComponent("Design.pen")

        #expect(throws: PenBundleError.notABundle(bare)) {
            try PenBundle.storeImage(Self.png, fileExtension: nil, in: bare)
        }
    }
}
