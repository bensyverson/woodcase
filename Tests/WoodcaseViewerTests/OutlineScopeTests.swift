//
//  OutlineScopeTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The outline lists the showcased artboard's tree, and nothing beside it.
///
/// `batch.pen` carries three top-level frames — `Cnv01`, a sibling artboard `Brd01`,
/// and a component definition `Cmp01` — so a listing that leaked every root would show
/// three unrelated trees at once. `banking.pen` goes further: its two real screens are
/// **ref-placed** at the top level, which is the case ``ArtboardLayout`` documents as
/// the one place an expanded node's id and the address the resolver accepts diverge.
@Suite("The outline is scoped to the showcased artboard")
struct OutlineScopeTests {
    /// Copies a fixture into a scratch directory and wraps it as a ``ViewerFile``.
    private func bench(_ fixture: String) throws -> (scratch: URL, file: ViewerFile) {
        let scratch = try ViewerFixtures.scratch()
        let file = try ViewerFile(url: ViewerFixtures.copy(fixture, into: scratch))
        return (scratch, file)
    }

    @Test("A plain top-level frame's outline excludes its sibling artboards and components")
    func scopedToAPlainFrame() async throws {
        let (scratch, file) = try bench("batch.pen")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let rows = try await ArtboardPageBuilder.rows(of: file, artboard: "Cnv01", state: ViewState(), fonts: nil)
        let ids = Set(rows.map(\.id))

        // Cnv01's own tree, in full.
        #expect(ids == ["Cnv01", "Ttl01", "Crd01", "Cd101", "Cd201"])
        // Never a sibling top-level frame, its children, or the component definition.
        #expect(!ids.contains("Brd01"))
        #expect(!ids.contains("Chi01"))
        #expect(!ids.contains("Cmp01"))
        #expect(!ids.contains("Lbl01"))
    }

    @Test("A different artboard of the same file gets a disjoint outline")
    func scopedToASiblingFrame() async throws {
        let (scratch, file) = try bench("batch.pen")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let rows = try await ArtboardPageBuilder.rows(of: file, artboard: "Brd01", state: ViewState(), fonts: nil)
        let ids = Set(rows.map(\.id))

        // `Chi01` is a `ref` to `Cmp01` — always walked into, so its one child comes
        // along too. `Cmp01` itself, the definition, is not: it is a different root.
        #expect(ids == ["Brd01", "Chi01", "Chi01/Lbl01"])
        #expect(!ids.contains("Cnv01"))
        #expect(!ids.contains("Ttl01"))
        #expect(!ids.contains("Cmp01"))
    }

    @Test("A ref-placed artboard's outline roots at the ref, not the expansion's compound id")
    func scopedToARefPlacedArtboard() async throws {
        let (scratch, file) = try bench("banking.pen")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let prepared = try await ViewerFixtures.renders().prepared(file)

        // The two real screens are `ref` nodes at the top level; expansion roots their
        // clone at `<ref>/<component root>` — the compound id `Artboard.id` carries.
        let screen = try #require(prepared.artboards.first { $0.id.contains("/") })
        let ref = try #require(screen.id.split(separator: "/").first).description

        let rows = try await ArtboardPageBuilder.rows(of: file, artboard: screen.id, state: ViewState(), fonts: nil)
        let ids = Set(rows.map(\.id))

        // The root row is named after the ref alone — the id the outline already
        // carries and the resolver already accepts — never the expansion's own root id.
        #expect(ids.contains(ref))
        #expect(!ids.contains(screen.id))

        // None of the component definitions — including the one this screen is a copy
        // of — leak in as their own rows.
        for other in prepared.artboards where other.id != screen.id {
            #expect(!ids.contains(other.id), "artboard '\(other.id)' leaked into '\(screen.id)`'s outline")
        }
    }
}
