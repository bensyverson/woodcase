//
//  PenNodePatcherEquivalenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Proves that applying overrides through ``PenNodeOverlay`` gives exactly the documents
/// the JSON round trip gave, over every fixture in the repository.
///
/// The overlay replaced four coder passes per override with a shallow capture and a
/// decode of the patch alone (see <doc:WoodcasePerformance>). Its whole claim is that it
/// is the *same* merge, so the reference is the round trip itself, kept as
/// ``PenNodePatcher/Route/jsonRoundTrip``, and the overlay runs as
/// ``PenNodePatcher/Route/overlayOnly`` — no falling back to JSON when it declines, so a
/// case it cannot answer shows up here as a difference instead of hiding behind the
/// fallback. The comparison is `==` on the expanded ``PenDocument``, extras, root
/// overrides and unknown properties included.
@Suite("Overlay patching equals the JSON round trip")
struct PenNodePatcherEquivalenceTests {
    @Test("every fixture expands to the same document through the overlay as through JSON")
    func everyFixture() throws {
        var documents = 0
        var withOverrides = 0
        for url in try Self.fixtureURLs() {
            guard let parsed = try? PenParser.parse(Data(contentsOf: url)) else { continue }
            documents += 1
            if Self.hasOverrides(parsed) { withOverrides += 1 }
            for purpose in [PenRefExpander.Purpose.canvas, .export] {
                let reference = PenNodePatcher.$route.withValue(.jsonRoundTrip) {
                    PenRefExpander.expand(parsed, for: purpose)
                }
                let overlay = PenNodePatcher.$route.withValue(.overlayOnly) {
                    PenRefExpander.expand(parsed, for: purpose)
                }
                #expect(overlay == reference, "\(url.lastPathComponent) (\(purpose)): the overlay's expansion differs")
            }
        }
        // A corpus that stopped holding overrides would pass vacuously.
        #expect(documents > 150, "only \(documents) fixtures parsed")
        #expect(withOverrides > 20, "only \(withOverrides) fixtures have an instance override to apply")
    }

    // MARK: - Helpers

    /// Whether any `ref` in the document carries root or descendant overrides.
    private static func hasOverrides(_ document: PenDocument) -> Bool {
        var pending = document.children
        while let node = pending.popLast() {
            if case let .ref(data) = node.kind,
               !(data.rootOverrides ?? [:]).isEmpty || !(data.descendants ?? [:]).isEmpty
            {
                return true
            }
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        return false
    }

    /// Every `.pen` file under the test bundle's `Fixtures`, sorted.
    private static func fixtureURLs() throws -> [URL] {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        let urls = (walk?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "pen" }
        return urls.sorted { $0.path < $1.path }
    }
}
