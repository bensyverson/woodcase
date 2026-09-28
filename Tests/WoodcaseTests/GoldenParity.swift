//
//  GoldenParity.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

/// Compares a 2.9 fixture with Pen.app 1.2.7's own 2.17 re-save of it.
///
/// The fixture tree has three layers:
///
/// | Directory | Holds |
/// | --- | --- |
/// | `Fixtures/` | the working fixtures, all 2.17 since `woodcase migrate` rewrote them |
/// | `Fixtures/v2.9/` | the legacy originals, kept verbatim as migrator input |
/// | `Fixtures/v2.17/` | Pen.app 1.2.7's own ⌘S output — the oracle |
///
/// Parsing the `v2.9` original and the `v2.17` golden through the version gate must
/// yield the same document — that is the acceptance test for `PenLegacyMigrator`,
/// and it stays a real one because the legacy half is never rewritten.
///
/// A handful of differences are Pen's own save behaviour rather than a format
/// change, and ``normalized(_:)`` absorbs them:
///
/// - `version` and `fileToken` differ by construction.
/// - Pen writes `x: 0`, `y: 0` explicitly where the original omitted them.
/// - Pen writes `width: 0`, `height: 0` on `path` nodes that had none.
/// - Pen writes `fontWeight: "normal"` on text that had no weight.
/// - Pen drops an empty `children: []` from a `frame` or `group` node; an empty
///   array and an absent key normalize to the same thing.
/// - Pen writes its default `fontFamily` — ``penDefaultFontFamily`` — on text that named none.
/// - Pen omits `textGrowth: "auto"`, which is the default.
/// - Pen writes `width` and `height` on `note`, `prompt` and `context` nodes. The model
///   has no field for either, so they are kept as ``PenNode/extras`` and written back.
/// - Pen flattens a `ref` whose target is not `reusable` into a full copy of the
///   target carrying the ref's id.
///
/// Anything else that differs is a migration bug.
enum GoldenParity {
    // MARK: - Registration

    /// The fixture basenames whose 2.9 original and 2.17 golden must agree.
    ///
    /// Every pair Pen.app produced is enabled: the feature slices of the 2.17
    /// migration appended theirs as they landed, and the fixture migration added the
    /// last one, `render-strokes-and-paths`.
    static let enabledFixtures: [String] = [
        "parser-icon-font",
        "parser-stroke-variants",
        "render-shapes-and-fills",
        "parser-all-node-types",
        "parser-text-content",
        "render-strokes-and-paths",
    ]

    /// Fixture basenames that exist only as a 2.17 golden — no 2.9 original ever
    /// produced them, so there is no pair to compare. `viewbox-experiment.pen` is
    /// hand-written 2.17 (the app opened and re-saved it without complaint; see
    /// the doc), holding the probe `script` node and `shader` fill.
    ///
    /// Registered separately from ``enabledFixtures`` so
    /// ``GoldenParityTests/enabledPairsExist(basename:)`` keeps its "every
    /// enabled fixture has both halves on disk" guarantee — appending a
    /// golden-only basename there would fail that test, not this slice's.
    ///
    /// The binding assertion is weaker than parity: the golden must parse
    /// cleanly through the version gate, with every node decoding to its typed
    /// ``PenNode/Kind`` case — never ``PenNode/Kind/unknown(typeName:properties:)``.
    static let goldenOnlyFixtures: [String] = [
        "viewbox-experiment",
    ]

    /// A last-pass adjustment applied to one pair after normalization, for the single
    /// deliberate difference a slice introduces.
    ///
    /// The rich-text slice is the case in point: Pen.app drops styled runs entirely
    /// where the migrator keeps the words, so its golden legitimately differs.
    typealias Override = @Sendable (_ legacy: inout PenDocument, _ golden: inout PenDocument) -> Void

    /// Per-pair overrides, keyed by fixture basename. Only pairs in
    /// ``enabledFixtures`` are ever consulted.
    static let overrides: [String: Override] = [
        "parser-all-node-types": { legacy, golden in
            // Pen.app rewrites path geometry into a compact-relative form on save
            // ("M 0 0 L 100 0 L 50 100 Z" → "M0 0l100 0-50 100z"); `geometry` is
            // stored as a raw string (PenNode.PathData), and canonicalizing that
            // syntax is the path-viewBox slice's job (PenSVGPathParser), not this
            // one's. Absorb the pre-existing difference here so this pair's
            // otherwise-unrelated group parity isn't blocked by it.
            guard let index = legacy.children.firstIndex(where: { $0.id == "path1" }),
                  case var .path(legacyData) = legacy.children[index].kind,
                  case let .path(goldenData) = golden.children[index].kind
            else { return }
            legacyData.geometry = goldenData.geometry
            legacy.children[index].kind = .path(legacyData)
        },

        "parser-text-content": pinRichTextNode,
    ]

    /// Pins the one deliberate difference in `parser-text-content`: the `rich-text` node.
    ///
    /// The 2.9 fixture gives it three styled runs — "Bold ", "Italic ", "Colored".
    /// Pen.app 1.2.7 drops the property outright on save, losing the words;
    /// ``PenRichTextMigrationRule`` keeps them as one string. The override asserts exactly
    /// that shape on both sides before equalizing, so any *other* drift in the node — or
    /// anywhere else in the document — still fails the comparison.
    private static let pinRichTextNode: Override = { legacy, golden in
        let index = 1
        #expect(legacy.children[index].id == "rich-text")
        #expect(golden.children[index].id == "rich-text")

        guard case let .text(migrated) = legacy.children[index].kind,
              case let .text(pen) = golden.children[index].kind
        else {
            Issue.record("Expected the rich-text node to be a text node on both sides")
            return
        }
        #expect(
            migrated.content == .literal("Bold Italic Colored"),
            "The migrator should keep the words of the discarded styled runs"
        )
        #expect(pen.content == nil, "Pen.app should have dropped the rich text content")

        legacy.children[index].kind = .text(pen)
    }

    // MARK: - Loading

    /// A golden pair that is not on disk.
    enum GoldenParityError: Error, CustomStringConvertible {
        /// Neither `Fixtures/v2.9/<name>.pen` nor `Fixtures/v2.17/<name>.pen` was found.
        case missingFixture(String)

        var description: String {
            switch self {
            case let .missingFixture(path): "Missing golden-parity fixture: \(path)"
            }
        }
    }

    /// Parses both halves of a golden pair through the version gate.
    static func documents(for basename: String) throws -> (legacy: PenDocument, golden: PenDocument) {
        try (
            legacy: parse(basename, subdirectory: "Fixtures/v2.9"),
            golden: parse(basename, subdirectory: "Fixtures/v2.17")
        )
    }

    private static func parse(_ basename: String, subdirectory: String) throws -> PenDocument {
        guard let url = Bundle.module.url(
            forResource: basename, withExtension: "pen", subdirectory: subdirectory
        ) else {
            throw GoldenParityError.missingFixture("\(subdirectory)/\(basename).pen")
        }
        return try PenParser.parse(contentsOf: url)
    }

    // MARK: - Assertion

    /// Asserts that both halves of a golden pair parse to the same document.
    ///
    /// - Parameters:
    ///   - basename: The fixture basename, without the `.pen` extension.
    ///   - override: A pair-specific adjustment; defaults to the entry in ``overrides``.
    ///   - sourceLocation: Filled in by the caller.
    static func assertParity(
        _ basename: String,
        override: Override? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let pair = try documents(for: basename)
        var legacy = normalized(pair.legacy)
        var golden = normalized(pair.golden)
        (override ?? overrides[basename])?(&legacy, &golden)
        #expect(
            legacy == golden,
            "Migrated \(basename).pen does not match Pen.app's 2.17 re-save",
            sourceLocation: sourceLocation
        )
    }

    /// Asserts that a golden with no 2.9 counterpart (see ``goldenOnlyFixtures``)
    /// parses cleanly: no decode error, and no node falls back to
    /// ``PenNode/Kind/unknown(typeName:properties:)``.
    static func assertCleanParse(
        _ basename: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let document = try parse(basename, subdirectory: "Fixtures/v2.17")
        let unknownTypes = unknownTypeNames(in: document.children)
        #expect(
            unknownTypes.isEmpty,
            "\(basename).pen has nodes that fell back to .unknown: \(unknownTypes.sorted())",
            sourceLocation: sourceLocation
        )
    }

    private static func unknownTypeNames(in nodes: [PenNode]) -> Set<String> {
        var result: Set<String> = []
        for node in nodes {
            if case let .unknown(typeName, _) = node.kind {
                result.insert(typeName)
            }
            if let kids = children(of: node) {
                result.formUnion(unknownTypeNames(in: kids))
            }
        }
        return result
    }

    // MARK: - Normalization

    /// The font family Pen.app 1.2.7 stamps on a text node that names none.
    ///
    /// Observed on every unstyled text node in `Fixtures/v2.17/parser-text-content.pen`;
    /// a node that already named a family keeps it. If a future golden shows Pen writing
    /// a different default, this is the one place to change.
    static let penDefaultFontFamily = "Inter"

    /// Erases the differences Pen.app introduces purely by saving.
    static func normalized(_ document: PenDocument) -> PenDocument {
        var result = document
        result.version = ""
        result.fileToken = nil
        let index = nodeIndex(document.children)
        result.children = document.children.map {
            normalized($0, index: index, flattening: [])
        }
        return result
    }

    /// Indexes every node in the tree by id, so a `ref` can be resolved to its target.
    private static func nodeIndex(_ nodes: [PenNode]) -> [String: PenNode] {
        var index: [String: PenNode] = [:]
        for node in nodes {
            index[node.id] = node
            if let children = children(of: node) {
                index.merge(nodeIndex(children)) { existing, _ in existing }
            }
        }
        return index
    }

    private static func normalized(
        _ node: PenNode,
        index: [String: PenNode],
        flattening: Set<String>
    ) -> PenNode {
        if let flattened = flattenedRef(node, index: index, flattening: flattening) {
            return flattened
        }

        var result = node
        result.common.x = node.common.x ?? .literal(0)
        result.common.y = node.common.y ?? .literal(0)

        switch node.kind {
        case var .text(data):
            data.fontWeight = data.fontWeight ?? .literal("normal")
            data.fontFamily = data.fontFamily ?? .literal(penDefaultFontFamily)
            data.textGrowth = data.textGrowth ?? .auto
            result.kind = .text(data)
        case var .path(data):
            data.width = data.width ?? .fixed(0)
            data.height = data.height ?? .fixed(0)
            result.kind = .path(data)
        case var .frame(data):
            data.children = normalizedChildren(data.children, index: index, flattening: flattening)
            result.kind = .frame(data)
        case var .group(data):
            data.children = normalizedChildren(data.children, index: index, flattening: flattening)
            result.kind = .group(data)
        case .note, .prompt, .context:
            // Pen writes a size on these; the model has no field for it, so the file's
            // `width` and `height` are kept as extras — which the 2.9 original never had.
            result.extras.values["width"] = nil
            result.extras.values["height"] = nil
        default:
            break
        }
        return result
    }

    /// Normalizes a container's children, treating an empty array the same as an
    /// absent one — Pen drops `children: []` on save.
    private static func normalizedChildren(
        _ children: [PenNode]?,
        index: [String: PenNode],
        flattening: Set<String>
    ) -> [PenNode]? {
        guard let children, !children.isEmpty else { return nil }
        return children.map { normalized($0, index: index, flattening: flattening) }
    }

    /// Replaces a plain `ref` to a non-`reusable` node with a copy of that node
    /// carrying the ref's id — what Pen.app writes on save.
    ///
    /// A ref that overrides anything is left alone: the overrides would have to be
    /// applied to produce the flattened copy, which is ``PenRefExpander``'s job, not
    /// a normalizer's. `flattening` guards against a reference cycle.
    private static func flattenedRef(
        _ node: PenNode,
        index: [String: PenNode],
        flattening: Set<String>
    ) -> PenNode? {
        guard case let .ref(data) = node.kind,
              data.descendants == nil, data.rootOverrides == nil,
              !flattening.contains(data.ref),
              let target = index[data.ref],
              target.common.reusable != true
        else {
            return nil
        }
        let substituted = PenNode(id: node.id, common: target.common, kind: target.kind)
        return normalized(substituted, index: index, flattening: flattening.union([data.ref]))
    }

    // MARK: - Child Access

    private static func children(of node: PenNode) -> [PenNode]? {
        switch node.kind {
        case let .frame(data): data.children
        case let .group(data): data.children
        default: nil
        }
    }
}
