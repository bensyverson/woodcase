//
//  RenderCacheImportsTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseViewer

/// The viewer draws what `shot` draws: an instance of an imported component expands,
/// and the imported definition is not an artboard.
struct RenderCacheImportsTests {
    /// `imports/app.pen` and its library, copied into a scratch directory.
    private static func stage(in scratch: URL) throws -> ViewerFile {
        for name in ["app.pen", "kit.lib.pen"] {
            try FileManager.default.copyItem(
                at: ViewerFixtures.directory.appendingPathComponent("imports/\(name)"),
                to: scratch.appendingPathComponent(name)
            )
        }
        return ViewerFile(url: scratch.appendingPathComponent("app.pen"))
    }

    @Test("A prepared document expands imported instances and lists no imported artboard")
    func preparedDocumentSeesImports() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try Self.stage(in: scratch)

        let prepared = try await ViewerFixtures.renders().prepared(file)

        #expect(prepared.artboards.map(\.id) == ["Art01", "Wrap1"])
        #expect(prepared.rects["Ins01/K:Chip1"]?.width == 80)
    }

    @Test("The code panel generates what `generate` does: imported components included (5jQhdY)")
    func emissionIncludesImportedComponents() async throws {
        let scratch = try ViewerFixtures.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = try Self.stage(in: scratch)

        let emission = try await ViewerFixtures.renders().emission(file)

        let ids = emission.components.map(\.id)
        #expect(ids.contains("K:Chip1"), "components: \(ids)")
        #expect(ids.contains("K:Card1"), "components: \(ids)")
        let chip = try #require(emission.components.first { $0.id == "K:Chip1" })
        #expect(emission.result.files.contains { $0.path == "components/\(chip.name).tsx" })
        // The page that places the chip now has a component to import rather than a
        // dangling ref.
        let page = try #require(ArtboardCode.of(artboard: "Art01", in: emission, target: .react))
        #expect(page.text.contains(chip.name))
    }
}
