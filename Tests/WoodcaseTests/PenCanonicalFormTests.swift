//
//  PenCanonicalFormTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Compares ``PenParser/encodeForFile(_:)`` against Pen's own headless `save()` of the
/// same fixture — `layout-gap.pen-saved.pen`, produced by `scripts/pen-oracle` and
/// committed beside its source fixture. See
/// [project/2026-08-29-pen-canonical-form.md](../../project/2026-08-29-pen-canonical-form.md)
/// for how that pair was generated and the full rationale for each difference below.
///
/// Every difference is either eliminated or named here; a difference that appears
/// without being named fails ``matchesPensOwnSaveApartFromDocumentedDifferences()``.
struct PenCanonicalFormTests {
    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let nameWithoutExtension = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: nameWithoutExtension, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureLoadError.notFound(name)
        }
        return url
    }

    /// Defaults `x`/`y` to `0` on every top-level (root) node, the way Pen's own save
    /// does, and clears `fileToken` — Pen mints a fresh random one on every save, so no
    /// fixed value can ever match byte for byte.
    ///
    /// Both are documented, standing differences (see the project doc); this is not a
    /// general-purpose normalizer, only what this one fixture pair needs.
    private func normalizedForComparison(_ document: PenDocument) -> PenDocument {
        var result = document
        result.fileToken = nil
        result.children = document.children.map { child in
            var normalizedChild = child
            normalizedChild.common.x = normalizedChild.common.x ?? .literal(0)
            normalizedChild.common.y = normalizedChild.common.y ?? .literal(0)
            return normalizedChild
        }
        return result
    }

    @Test("Documents exactly which fields Pen's save adds that encodeForFile omits")
    func documentedDifferencesAreExactlyThese() throws {
        let originalURL = try fixtureURL("layout-gap.pen")
        let original = try PenParser.parse(contentsOf: originalURL)

        let goldenURL = try fixtureURL("layout-gap.pen-saved.pen")
        let golden = try PenParser.parse(contentsOf: goldenURL)

        // Difference 1: fileToken. We never mint one; Pen always does on save.
        #expect(original.fileToken == nil)
        #expect(golden.fileToken != nil)
        let fileTokenIsUUIDShaped = golden.fileToken.map {
            $0.wholeMatch(of: #/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/#) != nil
        } ?? false
        #expect(fileTokenIsUUIDShaped, "Pen's fileToken should look like a UUID: \(String(describing: golden.fileToken))")

        // Difference 2: x/y defaults on root-level nodes. encodeForFile omits a nil
        // optional; Pen writes the literal 0 it used for layout.
        let originalRoot = try #require(original.children.first)
        #expect(originalRoot.common.x == nil)
        #expect(originalRoot.common.y == nil)

        let goldenRoot = try #require(golden.children.first)
        #expect(goldenRoot.common.x == .literal(0))
        #expect(goldenRoot.common.y == .literal(0))
    }

    @Test("encodeForFile matches Pen's own save once the documented differences are normalized away")
    func matchesPensOwnSaveApartFromDocumentedDifferences() throws {
        let originalURL = try fixtureURL("layout-gap.pen")
        let original = try PenParser.parse(contentsOf: originalURL)
        let ours = try PenParser.parse(PenParser.encodeForFile(original))

        let goldenURL = try fixtureURL("layout-gap.pen-saved.pen")
        let golden = try PenParser.parse(contentsOf: goldenURL)

        #expect(normalizedForComparison(ours) == normalizedForComparison(golden))
    }
}
