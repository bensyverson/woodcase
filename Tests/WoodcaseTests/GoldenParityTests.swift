//
//  GoldenParityTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

/// Asserts that a 2.9 fixture and Pen.app's own 2.17 re-save of it parse to the same document.
///
/// Each feature slice of the 2.17 migration appends the basenames it completes to the
/// enabled list. The tests below prove the helper itself works.
struct GoldenParityTests {
    // MARK: - The enabled pairs

    @Test("Every enabled golden pair parses to the same document", arguments: GoldenParity.enabledFixtures)
    func enabledPairsMatch(basename: String) throws {
        try GoldenParity.assertParity(basename)
    }

    @Test("Both halves of every enabled pair exist on disk", arguments: GoldenParity.enabledFixtures)
    func enabledPairsExist(basename: String) throws {
        _ = try GoldenParity.documents(for: basename)
    }

    // MARK: - The golden-only fixtures (no 2.9 original)

    @Test("Every golden-only fixture parses cleanly", arguments: GoldenParity.goldenOnlyFixtures)
    func goldenOnlyFixturesParseCleanly(basename: String) throws {
        try GoldenParity.assertCleanParse(basename)
    }

    // MARK: - The helper itself

    /// A 2.9-shaped document: no explicit origins, no default font weight, a live `ref`.
    private var legacyShaped: PenDocument {
        PenDocument(
            version: "2.9",
            children: [
                PenNode(
                    id: "frame1",
                    common: PenNodeCommon(name: "Container"),
                    kind: .frame(PenNode.FrameData(width: .fixed(400), height: .fixed(300)))
                ),
                PenNode(
                    id: "text1",
                    common: PenNodeCommon(),
                    kind: .text(PenNode.TextData(content: .literal("Hello")))
                ),
                PenNode(
                    id: "path1",
                    common: PenNodeCommon(),
                    kind: .path(PenNode.PathData(geometry: "M0 0l10 0z"))
                ),
                PenNode(
                    id: "ref1",
                    common: PenNodeCommon(),
                    kind: .ref(PenNode.RefData(ref: "frame1"))
                ),
            ]
        )
    }

    /// The same document as Pen.app 1.2.7 writes it: explicit zeros, a stamped font weight,
    /// a `fileToken`, and the non-reusable `ref` flattened into a copy of its target.
    private var goldenShaped: PenDocument {
        PenDocument(
            version: "2.17",
            fileToken: "00325dad-0320-4615-8272-39807ffa9dcd",
            children: [
                PenNode(
                    id: "frame1",
                    common: PenNodeCommon(name: "Container", x: .literal(0), y: .literal(0)),
                    kind: .frame(PenNode.FrameData(width: .fixed(400), height: .fixed(300)))
                ),
                PenNode(
                    id: "text1",
                    common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                    kind: .text(PenNode.TextData(
                        content: .literal("Hello"),
                        fontWeight: .literal("normal")
                    ))
                ),
                PenNode(
                    id: "path1",
                    common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                    kind: .path(PenNode.PathData(
                        width: .fixed(0),
                        height: .fixed(0),
                        geometry: "M0 0l10 0z"
                    ))
                ),
                PenNode(
                    id: "ref1",
                    common: PenNodeCommon(name: "Container", x: .literal(0), y: .literal(0)),
                    kind: .frame(PenNode.FrameData(width: .fixed(400), height: .fixed(300)))
                ),
            ]
        )
    }

    @Test("Normalization absorbs every known on-save difference")
    func normalizationAbsorbsSaveDifferences() {
        #expect(legacyShaped != goldenShaped)
        #expect(GoldenParity.normalized(legacyShaped) == GoldenParity.normalized(goldenShaped))
    }

    @Test("Normalization is idempotent")
    func normalizationIsIdempotent() {
        let once = GoldenParity.normalized(legacyShaped)
        #expect(GoldenParity.normalized(once) == once)
    }

    @Test("Normalization does not hide a real difference")
    func realDifferencesSurvive() {
        var altered = goldenShaped
        altered.children[1] = PenNode(
            id: "text1",
            common: PenNodeCommon(x: .literal(0), y: .literal(0)),
            kind: .text(PenNode.TextData(
                content: .literal("Goodbye"),
                fontWeight: .literal("normal")
            ))
        )
        #expect(GoldenParity.normalized(legacyShaped) != GoldenParity.normalized(altered))
    }

    @Test("Nested children are normalized too")
    func nestedChildrenAreNormalized() {
        let legacy = PenDocument(version: "2.9", children: [
            PenNode(id: "frame1", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(children: [
                PenNode(id: "t", common: PenNodeCommon(), kind: .text(PenNode.TextData())),
            ]))),
        ])
        let golden = PenDocument(version: "2.17", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                kind: .frame(PenNode.FrameData(children: [
                    PenNode(
                        id: "t",
                        common: PenNodeCommon(x: .literal(0), y: .literal(0)),
                        kind: .text(PenNode.TextData(fontWeight: .literal("normal")))
                    ),
                ]))
            ),
        ])
        #expect(GoldenParity.normalized(legacy) == GoldenParity.normalized(golden))
    }

    @Test("A reusable ref is left alone")
    func reusableRefIsNotFlattened() {
        let legacy = PenDocument(version: "2.9", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(reusable: true),
                kind: .frame(PenNode.FrameData(width: .fixed(10), height: .fixed(10)))
            ),
            PenNode(id: "ref1", common: PenNodeCommon(), kind: .ref(PenNode.RefData(ref: "frame1"))),
        ])
        let normalized = GoldenParity.normalized(legacy)
        guard case .ref = normalized.children[1].kind else {
            Issue.record("Expected the ref to a reusable frame to stay a ref")
            return
        }
    }

    // MARK: - The per-pair override hook

    @Test("A per-pair override can absorb one deliberate difference")
    func overrideHookAbsorbsDeliberateDifference() {
        var legacy = legacyShaped
        legacy.children[1] = PenNode(
            id: "text1",
            common: PenNodeCommon(),
            kind: .text(PenNode.TextData(content: .literal("Bold Italic Colored")))
        )
        // Pen.app drops rich text entirely; the migrator keeps the words, so the golden differs.
        var golden = goldenShaped
        golden.children[1] = PenNode(
            id: "text1",
            common: PenNodeCommon(x: .literal(0), y: .literal(0)),
            kind: .text(PenNode.TextData(fontWeight: .literal("normal")))
        )

        #expect(GoldenParity.normalized(legacy) != GoldenParity.normalized(golden))

        let override: GoldenParity.Override = { left, right in
            left.children[1] = right.children[1]
        }
        var left = GoldenParity.normalized(legacy)
        var right = GoldenParity.normalized(golden)
        override(&left, &right)
        #expect(left == right)
    }

    @Test("Every override is keyed by an enabled basename")
    func registrationPointsExist() {
        #expect(GoldenParity.overrides.keys.allSatisfy { GoldenParity.enabledFixtures.contains($0) })
    }
}
