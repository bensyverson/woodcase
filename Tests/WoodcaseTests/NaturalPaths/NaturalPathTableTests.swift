//
//  NaturalPathTableTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// One table maps each Woodcase-owned key to the natural path a caller reads and writes it
/// at (leaf 9Sw8C0; `project/2026-10-20-natural-paths-for-woodcase-properties.md`).
struct NaturalPathTableTests {
    /// Every key with a natural path, and the path.
    private static let table: [PenMetadata.WoodcaseKey: String] = [
        .blendMode: "kind.blendMode",
        .strokeDash: "kind.strokeDash",
        .strokeDashOffset: "kind.strokeDashOffset",
        .strokeMiterLimit: "kind.strokeMiterLimit",
        .locked: "common.locked",
        .defaultTextStyle: "kind.defaultTextStyle",
        .spans: "kind.spans",
    ]

    /// `woodcaseFields` rows still at their storage path, each waiting on a named leaf.
    /// A row that is neither here nor at a natural path fails `everyFieldRowIsNatural`.
    private static let pendingRows: Set<String> = [
        PenMetadata.WoodcaseKey.shadowSpread.path, // oNeklc: spread becomes a field of the shadow
    ]

    @Test("Each Woodcase-owned key names its natural path, and only those keys do")
    func tableIsExact() {
        let named = Dictionary(uniqueKeysWithValues: PenMetadata.WoodcaseKey.allCases.compactMap { key in
            key.naturalPath.map { (key, $0) }
        })
        #expect(named == Self.table)
    }

    @Test("A natural path names its key back")
    func roundTrips() {
        for (key, path) in Self.table {
            #expect(PenMetadata.WoodcaseKey(naturalPath: path) == key)
        }
        #expect(PenMetadata.WoodcaseKey(naturalPath: "common.metadata.woodcase.strokeDash") == nil)
    }

    @Test("A key's property path is its natural path, or its storage path for a key with none")
    func propertyPath() {
        #expect(PenMetadata.WoodcaseKey.strokeDash.propertyPath == "kind.strokeDash")
        #expect(PenMetadata.WoodcaseKey.locked.propertyPath == "common.locked")
        #expect(PenMetadata.WoodcaseKey.tint.propertyPath == PenMetadata.WoodcaseKey.tint.path)
    }

    @Test("Every woodcaseFields row of every type is at a natural path, but the pending ones")
    func everyFieldRowIsNatural() {
        for type in PenNode.NodeType.allCases {
            for row in PenSchema.woodcaseFields(for: type) where !Self.pendingRows.contains(row.path) {
                #expect(PenMetadata.WoodcaseKey(naturalPath: row.path) != nil, "\(type): \(row.path)")
            }
        }
    }

    @Test("The natural paths are in each type's vocabulary exactly where the field rows are")
    func vocabularyMatchesRows() {
        for type in PenNode.NodeType.allCases {
            let rows = Set(PenSchema.woodcaseFields(for: type).map(\.path)).subtracting(Self.pendingRows)
            let vocabulary = PropertyDiff.allKindKeys(type).union(NodePropertyCodec.naturalCommonPaths)
            let natural = vocabulary.filter { PenMetadata.WoodcaseKey(naturalPath: $0) != nil && $0 != "kind.blendMode" }
            #expect(natural == rows, "\(type)")
        }
    }

    @Test("Which types take which natural path")
    func typesTakingEachPath() {
        #expect(PropertyDiff.allKindKeys(.frame).isSuperset(of: ["kind.strokeDash", "kind.strokeDashOffset", "kind.strokeMiterLimit"]))
        #expect(PropertyDiff.allKindKeys(.line).contains("kind.strokeDash"))
        #expect(!PropertyDiff.allKindKeys(.line).contains("kind.strokeMiterLimit"))
        #expect(PropertyDiff.allKindKeys(.text).isSuperset(of: ["kind.spans", "kind.defaultTextStyle"]))
        #expect(!PropertyDiff.allKindKeys(.rectangle).contains("kind.spans"))
        #expect(!PropertyDiff.allKindKeys(.text).contains("kind.strokeDash"))
        #expect(NodePropertyCodec.naturalCommonPaths == ["common.locked"])
    }

    @Test("paths(for:) lists the natural paths a node takes")
    func pathsListThem() throws {
        let card = try NaturalPathFixture.node("Crd01")
        let paths = NodePropertyCodec.paths(for: card)
        #expect(paths.contains("kind.strokeDash"))
        #expect(paths.contains("common.locked"))
        #expect(paths.contains("kind.blendMode"))
        #expect(paths == paths.sorted())
    }

    // MARK: - Schema

    @Test("The schema lists each natural path with the metadata key the file stores it under")
    func schemaRows() {
        let cases: [(String, PenNode.NodeType)] = [
            ("kind.strokeDash", .frame), ("kind.strokeDashOffset", .rectangle), ("kind.strokeMiterLimit", .polygon),
            ("kind.defaultTextStyle", .text), ("kind.spans", .text), ("kind.blendMode", .group),
        ]
        for (path, type) in cases {
            let row = PenSchema.table(for: type).properties.first { $0.path == path }
            let key = PenMetadata.WoodcaseKey(naturalPath: path)?.rawValue ?? "?"
            #expect(row?.key == .key("metadata.woodcase.\(key)"), "\(path) on \(type)")
        }
        let locked = PenSchema.common.properties.first { $0.path == "common.locked" }
        #expect(locked?.key == .key("metadata.woodcase.locked"))
        #expect(locked?.default == .boolean(false))
    }

    @Test("A natural row keeps its field's shape, constraint and default")
    func schemaRowDetail() {
        let dash = PenSchema.field("kind.strokeDash", for: .rectangle)
        #expect(dash?.shape.example == "[8, 4]")
        #expect(dash?.default == .numbers([]))
        let miter = PenSchema.field("kind.strokeMiterLimit", for: .frame)
        #expect(miter?.constraint == PenNode.miterLimitConstraint)
        #expect(PenSchema.field("common.locked", for: .ref) != nil)
    }
}
