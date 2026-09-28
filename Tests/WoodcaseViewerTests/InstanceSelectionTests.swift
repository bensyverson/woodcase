//
//  InstanceSelectionTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// Three walks name the same node, and they have to agree: the layout the render is
/// hit-tested against, the outline rows a selection highlights, and the address the
/// Details pane resolves.
///
/// `addressing-nested-instance.pen` is the fixture that exercises both levels. `Page1`
/// places the instance `Card1` of the component `CardC`, and `CardC` itself places the
/// instance `Btn02` of `BtnC` — so the artboard carries an instance, and an instance
/// inside an instance.
///
/// The disagreement this suite exists to catch is the instance **root**:
/// ``Woodcase/PenRefExpander`` roots a clone at `<ref>/<component root>` (`Card1/CardC`),
/// while the tree view names that row after the ref alone (`Card1`) and
/// ``Woodcase/EditableDocument/resolve(_:tags:)-(String,_)`` has no step onto a component
/// root at all. A layout that answers `Card1/CardC` therefore selects nothing and makes
/// the pane say the address names no node.
@Suite("Selection inside component instances")
struct InstanceSelectionTests {
    /// The fixture on disk, prepared for rendering.
    private func bench() async throws -> (scratch: URL, file: ViewerFile, prepared: PreparedDocument) {
        let scratch = try ViewerFixtures.scratch()
        let file = try ViewerFile(url: ViewerFixtures.copy("addressing-nested-instance.pen", into: scratch))
        let prepared = try await ViewerFixtures.renders().prepared(file)
        return (scratch, file, prepared)
    }

    /// The layout of the fixture's one placed artboard.
    private func layout(_ prepared: PreparedDocument) throws -> ArtboardLayout {
        let artboard = try #require(prepared.artboard(id: "Page1"))
        return try #require(ArtboardLayout.of(artboard: artboard, in: prepared, scale: 1))
    }

    @Test("An instance's box is named by its ref, not by the component it clones")
    func instanceRootsAreNamedByTheirRef() async throws {
        let (scratch, _, prepared) = try await bench()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let ids = try Set(layout(prepared).nodes.map(\.id))

        // The instance, and the instance inside it.
        #expect(ids.contains("Card1"))
        #expect(ids.contains("Card1/Btn02"))
        // Never the expansion's own root id, which resolves to nothing.
        #expect(!ids.contains("Card1/CardC"))
        #expect(!ids.contains("Card1/Btn02/BtnC"))
        // Descendants keep the id-path they already agreed on.
        #expect(ids.contains("Card1/Ttl03"))
        #expect(ids.contains("Card1/Btn02/Lbl02"))
        #expect(ids.contains("Card1/Btn02/Ico02"))
    }

    @Test("Every box the render can be clicked on has a row in the outline")
    func everyBoxHasAnOutlineRow() async throws {
        let (scratch, file, prepared) = try await bench()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let rows = try await ArtboardPageBuilder.rows(of: file, artboard: "Page1", state: ViewState(), fonts: nil)
        let addressable = Set(rows.map(\.id)).union(rows.map(\.address))
        for node in try layout(prepared).nodes {
            #expect(
                addressable.contains(node.id),
                "clicking \(node.path) selects \(node.id), which no outline row carries"
            )
        }
    }

    @Test("Every box the render can be clicked on has details to show")
    func everyBoxHasDetails() async throws {
        let (scratch, file, prepared) = try await bench()
        defer { try? FileManager.default.removeItem(at: scratch) }

        for node in try layout(prepared).nodes {
            let selection = try await ArtboardPageBuilder.selection(
                of: file, state: ViewState().selecting(node.id), prepared: prepared, fonts: nil
            )
            #expect(
                selection.unresolved == nil,
                "the details pane says '\(node.id)' names no node in this file"
            )
            #expect(selection.details != nil)
        }
    }

    @Test("The outline walks into instances, because the render always shows them")
    func theOutlineWalksIntoInstances() async throws {
        let (scratch, file, _) = try await bench()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let ids = try await Set(ArtboardPageBuilder.rows(of: file, artboard: "Page1", state: ViewState(), fonts: nil).map(\.id))
        #expect(ids.contains("Card1/Ttl03"))
        #expect(ids.contains("Card1/Btn02/Lbl02"))
    }
}
