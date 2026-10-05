//
//  PenBundleAssetsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The files a document points at, and adding one to a bundle: what an app needs to ask
/// for access before converting, and to drop an image or install a font.
struct PenBundleAssetsTests {
    typealias Project = PenBundleTests.Project

    // MARK: - localAssets

    @Test("local assets are every local image and font file, resolved, whether or not they exist")
    func localAssetsResolves() throws {
        let project = try Project()
        defer { project.remove() }

        let assets = try PenBundle.localAssets(of: project.file)

        #expect(assets.map(\.path).sorted() == [
            project.root.appendingPathComponent("shared/photo.png").path,
            project.folder.appendingPathComponent("hero.png").path,
            project.folder.appendingPathComponent("images/other.png").path,
            project.folder.appendingPathComponent("missing.png").path,
            project.folder.appendingPathComponent("type/Mono.ttf").path,
        ].sorted())
    }

    @Test("a bundle's local assets resolve against the bundle")
    func localAssetsOfABundle() async throws {
        let project = try Project()
        defer { project.remove() }
        try await PenBundle.convert(project.file, identity: nil)
        let bundle = project.folder.appendingPathComponent("Design.umbra")

        let assets = try PenBundle.localAssets(of: bundle)

        #expect(assets.contains(bundle.appendingPathComponent("images/hero.png").standardizedFileURL))
        #expect(assets.contains(bundle.appendingPathComponent("fonts/Mono.ttf").standardizedFileURL))
    }

    // MARK: - importAsset

    @Test("importing a file copies it into the kind's folder and returns its relative reference")
    func importCopies() throws {
        let project = try Project()
        defer { project.remove() }
        let bundle = try makeBundle(in: project)

        let reference = try PenBundle.importAsset(project.folder.appendingPathComponent("hero.png"), as: .image, into: bundle)
        let font = try PenBundle.importAsset(project.folder.appendingPathComponent("type/Mono.ttf"), as: .font, into: bundle)

        #expect(reference == "./images/hero.png")
        #expect(font == "./fonts/Mono.ttf")
        #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("images/hero.png").path))
        #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("fonts/Mono.ttf").path))
    }

    @Test("importing a file whose name is taken numbers it, and never overwrites")
    func importNumbersOnAClash() throws {
        let project = try Project()
        defer { project.remove() }
        let bundle = try makeBundle(in: project)
        let hero = project.folder.appendingPathComponent("hero.png")

        let first = try PenBundle.importAsset(hero, as: .image, into: bundle)
        let second = try PenBundle.importAsset(hero, as: .image, into: bundle)

        #expect(first == "./images/hero.png")
        #expect(second == "./images/hero-2.png")
    }

    @Test("importing a file already in the bundle copies nothing and returns its path")
    func importOfAnInsideFile() throws {
        let project = try Project()
        defer { project.remove() }
        let bundle = try makeBundle(in: project)
        let inside = try PenBundle.importAsset(project.folder.appendingPathComponent("hero.png"), as: .image, into: bundle)

        let again = try PenBundle.importAsset(bundle.appendingPathComponent("images/hero.png"), as: .image, into: bundle)

        #expect(again == inside)
        #expect(try FileManager.default.contentsOfDirectory(atPath: bundle.appendingPathComponent("images").path) == ["hero.png"])
    }

    @Test("importing data writes it under the given name")
    func importData() throws {
        let project = try Project()
        defer { project.remove() }
        let bundle = try makeBundle(in: project)
        let data = Data([0x89, 0x50, 0x4E, 0x47])

        let reference = try PenBundle.importAsset(data, named: "Pasted.png", as: .image, into: bundle)

        #expect(reference == "./images/Pasted.png")
        #expect(try Data(contentsOf: bundle.appendingPathComponent("images/Pasted.png")) == data)
    }

    @Test("importing into a bare file is refused")
    func importRefusesABareFile() throws {
        let project = try Project()
        defer { project.remove() }

        #expect(throws: PenBundleError.notABundle(project.file)) {
            try PenBundle.importAsset(project.folder.appendingPathComponent("hero.png"), as: .image, into: project.file)
        }
    }

    // MARK: - Helpers

    /// An empty bundle in the project's root.
    private func makeBundle(in project: Project) throws -> URL {
        let bundle = project.root.appendingPathComponent("Empty.umbra")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        return bundle
    }
}
