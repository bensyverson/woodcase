//
//  PenMeshGradientFixtureTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Holds the typed mesh model to Pen's own output.
///
/// Two fixture pairs, each a hand-written `.pen` beside Pen's canonical re-save of it
/// (`scripts/pen-oracle <fixture> --out <dir>`, sandbox off, `pen` CLI 0.3.9, which
/// writes format 2.19):
///
/// - `render-mesh-gradients.pen` — the eight-artboard probe from
///   `project/2026-09-26-mesh-gradients.md`, Appendix A.
/// - `mesh-point-elision.pen` — points written with default, near-default and
///   unrounded handles, to pin which ones Pen's serialiser drops.
///
/// Tests only read these files; they never run `pen`.
struct PenMeshGradientFixtureTests {
    private static let tolerance = 1e-4

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// The same JSON with its keys sorted and its whitespace fixed, so two documents
    /// that differ only in key order compare equal byte for byte.
    ///
    /// `version` is dropped: ``PenParser`` stamps ``PenDocument/currentFormatVersion``
    /// on every document it reads, so Pen's `"2.19"` comes back as Woodcase's own
    /// version by construction, not by any loss in the mesh model.
    private func sortedBytes(_ data: Data) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "version")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// Every mesh fill in the document, keyed by the id of the node that carries it.
    ///
    /// The fixtures hold only frames and one ellipse, so those are the kinds walked.
    private func meshFills(_ document: PenDocument) -> [String: PenFill.PenMeshGradientFill] {
        var result: [String: PenFill.PenMeshGradientFill] = [:]
        func visit(_ node: PenNode) {
            let (fills, children): (PenFills?, [PenNode]) = switch node.kind {
            case let .frame(data): (data.fills, data.children ?? [])
            case let .ellipse(data): (data.fills, [])
            default: (nil, [])
            }
            for fill in fills?.all ?? [] {
                if case let .meshGradient(mesh) = fill { result[node.id] = mesh }
            }
            children.forEach(visit)
        }
        document.children.forEach(visit)
        return result
    }

    /// Whether two points have the same wire form, the same handles present, and
    /// values within Pen's serialisation precision.
    private func sameCanonicalPoint(_ lhs: PenMeshPoint, _ rhs: PenMeshPoint) -> Bool {
        func close(_ a: PenMeshPoint.Vector?, _ b: PenMeshPoint.Vector?) -> Bool {
            switch (a, b) {
            case (nil, nil): true
            case let (a?, b?): abs(a.x - b.x) <= Self.tolerance && abs(a.y - b.y) <= Self.tolerance
            default: false
            }
        }
        switch (lhs, rhs) {
        case let (.bare(a), .bare(b)):
            return close(a, b)
        case let (.object(a), .object(b)):
            return close(a.position, b.position) && close(a.leftHandle, b.leftHandle)
                && close(a.rightHandle, b.rightHandle) && close(a.topHandle, b.topHandle)
                && close(a.bottomHandle, b.bottomHandle)
        default:
            return false
        }
    }

    // MARK: - Round trip

    @Test("Pen's re-save of the probe round-trips byte-equal through Woodcase, modulo key order")
    func goldenRoundTripsByteEqual() throws {
        let golden = try fixture("render-mesh-gradients.pen-saved.pen")
        let reencoded = try PenParser.encodeForFile(PenParser.parse(golden))
        #expect(try sortedBytes(reencoded) == sortedBytes(golden))
    }

    @Test("Pen's re-save of the elision probe round-trips byte-equal through Woodcase, modulo key order")
    func elisionGoldenRoundTripsByteEqual() throws {
        let golden = try fixture("mesh-point-elision.pen-saved.pen")
        let reencoded = try PenParser.encodeForFile(PenParser.parse(golden))
        #expect(try sortedBytes(reencoded) == sortedBytes(golden))
    }

    @Test("The hand-written probe round-trips in the form it was written")
    func probeRoundTripsAsWritten() throws {
        let original = try fixture("mesh-point-elision.pen")
        let reencoded = try PenParser.encodeForFile(PenParser.parse(original))
        #expect(try sortedBytes(reencoded) == sortedBytes(original))
    }

    // MARK: - Typed decoding

    @Test("The probe's points decode typed, in the form each was written")
    func probeDecodesTyped() throws {
        let fills = try meshFills(PenParser.parse(fixture("render-mesh-gradients.pen")))
        #expect(fills.count == 8)

        let warp = try #require(fills["mCwarp"]?.points)
        #expect(warp.count == 9)
        #expect(warp[0] == .bare(PenMeshPoint.Vector(0, 0)))
        #expect(warp[4] == .object(PenMeshPoint.Object(
            position: PenMeshPoint.Vector(0.3, 0.7),
            leftHandle: PenMeshPoint.Vector(-0.2, 0.1),
            rightHandle: PenMeshPoint.Vector(0.2, -0.1),
            topHandle: PenMeshPoint.Vector(0.05, -0.3),
            bottomHandle: PenMeshPoint.Vector(-0.05, 0.3)
        )))

        let fold = try #require(fills["mHfld"]?.points)
        #expect(fold[3] == .object(PenMeshPoint.Object(
            position: PenMeshPoint.Vector(1, 1),
            leftHandle: PenMeshPoint.Vector(-1.2, -0.6)
        )))
    }

    // MARK: - Pen's canonical form

    @Test(
        "Canonicalising a fixture's points reproduces Pen's re-save to 1e-4",
        arguments: ["render-mesh-gradients", "mesh-point-elision"]
    )
    func canonicalPointsMatchPen(fixtureName: String) throws {
        let ours = try meshFills(PenParser.parse(fixture("\(fixtureName).pen")))
        let pens = try meshFills(PenParser.parse(fixture("\(fixtureName).pen-saved.pen")))
        #expect(Set(ours.keys) == Set(pens.keys))

        for (id, fill) in ours {
            let expected = try #require(pens[id]?.points, "Pen's save of \(id) has no points")
            let actual = try #require(fill.canonicalized().points, "\(id) has no points")
            #expect(actual.count == expected.count, "\(id): point count")
            for (index, pair) in zip(actual, expected).enumerated() {
                #expect(sameCanonicalPoint(pair.0, pair.1), "\(id) point \(index): ours \(pair.0), Pen's \(pair.1)")
            }
        }
    }
}
