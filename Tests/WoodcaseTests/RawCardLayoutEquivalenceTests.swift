//
//  RawCardLayoutEquivalenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Proves that drawing a card raw, editing it while raw and drawing it styled again lays
/// out exactly what a full layout with the same raw cards gives, on every fixture that
/// places a note, prompt or context (leaf `WfbzYQ`).
///
/// Two incremental paths are held to it: a host's own pipeline, which passes the
/// rawness change as an invalidation (``PenLayoutOptions/invalidation(from:)``) with its
/// measurement cache; and a host holding a ``PenLayoutState``, which is handed the new
/// options and works the change out itself.
@MainActor
struct RawCardLayoutEquivalenceTests {
    /// Which incremental path lays the document out.
    enum Path: CaseIterable {
        /// ``PenLayoutEngine/layoutIncremental(_:previousRects:invalidation:textMeasurer:options:measurementCache:)``.
        case host
        /// ``PenLayoutState/update(to:invalidation:options:)``.
        case state
    }

    /// A host's layout between runs.
    struct Host {
        var rects: [String: PenRect] = [:]
        var measurementCache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        var state: PenLayoutState?
        var options = PenLayoutOptions()
    }

    /// Markdown whose raw source is much longer than its display text, long enough to
    /// outgrow the fixtures' set heights.
    private static let edited = String(
        repeating: "**Read** **the** **guide** **today**, **then** **tell** **us** **what** **you** **think**. ", count: 4
    )

    @Test("a card drawn raw, edited raw and drawn styled again lays out as a full layout does", arguments: Path.allCases)
    func everyCard(path: Path) throws {
        let measurer = SettledTreeReuseTests.measurer
        var compared = 0
        var grown = 0
        for url in try FixtureFlatStore.fixtureURLs() {
            guard let parsed = try? PenParser.parse(Data(contentsOf: url)) else { continue }
            let document = PenFileTransaction.editableDocument(from: parsed, at: url, fonts: nil)
            let cards = FixtureFlatStore.documentOrder(of: document).filter { id in
                document.nodes[id].flatMap { PenPostIt.Variant($0.kind) } != nil
                    && !FixtureFlatStore.isInsideDefinition(id, in: document)
            }
            guard let card = cards.first else { continue }
            let raw = PenLayoutOptions(rawBodies: [card])

            var host = Host()
            _ = layOut(document, path: path, host: &host, options: PenLayoutOptions(), measurer: measurer)
            let steps: [(name: String, options: PenLayoutOptions, edit: Bool)] = [
                ("raw", raw, false), ("edited raw", raw, true), ("styled", PenLayoutOptions(), false),
            ]
            for step in steps {
                if step.edit {
                    try document.apply(.setProperties(EditOperation.SetProperties(
                        nodeID: card, properties: ["kind.content": .string(Self.edited)]
                    )))
                }
                let incremental = layOut(document, path: path, host: &host, options: step.options, measurer: measurer)
                let full = LayoutOracle.fullLayout(of: document, textMeasurer: measurer, options: step.options)
                if step.options == raw, full != LayoutOracle.fullLayout(of: document, textMeasurer: measurer) {
                    grown += 1
                }
                let differences = LayoutOracle.differences(incremental, full)
                #expect(differences.isEmpty, "\(url.lastPathComponent), \(card) \(step.name) (\(path)): \(differences.joined(separator: "; "))")
                compared += 1
            }
        }
        #expect(compared >= 9, "Only \(compared) comparisons: too few fixtures place a card.")
        #expect(grown >= 3, "Drawing a card raw changed the layout only \(grown) times: the comparisons prove little.")
    }

    /// Lays the document out by one path with the given raw cards, and takes its dirty
    /// tracking, as a host does.
    private func layOut(
        _ document: EditableDocument, path: Path, host: inout Host,
        options: PenLayoutOptions, measurer: @escaping TextMeasurer
    ) -> [String: PenRect] {
        let invalidation = document.layoutInvalidation
        let resolved = PenVariableResolver.resolve(document.expandedDocument().0)
        document.primeLayoutCache(with: [:])
        document.clearDirtyNodes()
        defer { host.options = options }
        switch path {
        case .host:
            if host.rects.isEmpty {
                host.rects = PenLayoutEngine.layout(resolved, textMeasurer: measurer, options: options)
            } else {
                host.rects = PenLayoutEngine.layoutIncremental(
                    resolved, previousRects: host.rects,
                    invalidation: invalidation.union(options.invalidation(from: host.options)),
                    textMeasurer: measurer, options: options, measurementCache: &host.measurementCache
                )
            }
            return host.rects
        case .state:
            guard var state = host.state else {
                let state = PenLayoutState(document: resolved, textMeasurer: measurer, options: options)
                host.state = state
                return state.rects
            }
            _ = state.update(to: resolved, invalidation: invalidation, options: options)
            host.state = state
            return state.rects
        }
    }
}
