//
//  PenMeshPointMalformedTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Covers ``PenMeshPoint/malformed(_:)``: a vertex a file wrote in neither wire form.
///
/// A file decode keeps it verbatim; authoring input refuses it. How Pen places it —
/// ``PenMeshPoint/placement(gridPosition:defaults:)`` — was measured with the headless
/// `pen` CLI 0.3.9 on `render-mesh-malformed-points.pen` and two scratch probes
/// (`project/2026-09-26-what-pen-drops-from-a-file.md`, "Malformed points, measured").
struct PenMeshPointMalformedTests {
    typealias Vector = PenMeshPoint.Vector

    private func decoded(_ json: String) throws -> PenMeshPoint {
        try JSONDecoder().decode(PenMeshPoint.self, from: Data(json.utf8))
    }

    private func authored(_ json: String) throws -> PenMeshPoint {
        let decoder = JSONDecoder()
        decoder.userInfo[PenDecodingMode.userInfoKey] = PenDecodingMode.authoring
        return try decoder.decode(PenMeshPoint.self, from: Data(json.utf8))
    }

    private func encoded(_ point: PenMeshPoint) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try String(decoding: encoder.encode(point), as: UTF8.self)
    }

    /// Every malformed spelling the probes covered, as the file wrote it.
    static let malformedSpellings = [
        ##""oops""##, "null", "42", "true", "{}", "[]", "[1]", "[0.3,0.2,9]", "[0.3,null]",
        "[true,false]", ##"["0.3","0.2"]"##, "[[0.3],[0.2]]", ##"{"position":"oops"}"##,
        ##"{"position":null}"##, ##"{"position":[1]}"##, ##"{"leftHandle":[-0.3,0.2]}"##,
        ##"{"position":[0.3,0.2],"leftHandle":[1]}"##, ##"{"position":[0.3,0.2],"leftHandle":"oops"}"##,
        ##"{"position":[0.3,0.2],"leftHandle":{}}"##, ##"{"position":[0.3,0.2],"leftHandle":[-0.3,0.2,5]}"##,
    ]

    // MARK: - Decoding

    @Test("A file decode keeps a point written in neither form as malformed", arguments: malformedSpellings)
    func fileDecodeKeepsIt(json: String) throws {
        let point = try decoded(json)
        let raw = try JSONDecoder().decode(AnyCodable.self, from: Data(json.utf8))
        #expect(point == .malformed(raw))
    }

    @Test("A malformed point encodes back exactly as written", arguments: malformedSpellings)
    func roundTripsVerbatim(json: String) throws {
        let raw = try JSONDecoder().decode(AnyCodable.self, from: Data(json.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let expected = try String(decoding: encoder.encode(raw), as: UTF8.self)
        #expect(try encoded(decoded(json)) == expected)
    }

    @Test("Authoring input refuses a point written in neither form", arguments: malformedSpellings)
    func authoringRefusesIt(json: String) {
        #expect(throws: DecodingError.self) { try authored(json) }
    }

    @Test("Authoring input still takes both well-formed forms")
    func authoringTakesWellFormed() throws {
        #expect(try authored("[0.25,0.75]") == .bare(Vector(0.25, 0.75)))
        #expect(try authored(##"{"position":[0.5,0]}"##) == .object(PenMeshPoint.Object(position: Vector(0.5, 0))))
    }

    @Test("A malformed point has no position or handles of its own")
    func noPositionOrHandles() throws {
        let point = try decoded(##""oops""##)
        #expect(point.position == nil)
        #expect(point.handles(defaults: PenMeshPoint.Handles.defaults(columns: 2, rows: 2)) == nil)
    }

    @Test("Canonicalising leaves a malformed point as written")
    func canonicalLeavesIt() throws {
        let point = try decoded("[0.123456,0.2,9]")
        #expect(point.canonicalized(defaults: PenMeshPoint.Handles.defaults(columns: 2, rows: 2)) == point)
    }

    // MARK: - Grid position

    @Test("A vertex's grid position is its column and row over the grid's span")
    func gridPosition() {
        #expect(PenMeshPoint.gridPosition(column: 1, row: 0, columns: 3, rows: 2) == Vector(0.5, 0))
        #expect(PenMeshPoint.gridPosition(column: 1, row: 1, columns: 3, rows: 2) == Vector(0.5, 1))
        #expect(PenMeshPoint.gridPosition(column: 2, row: 2, columns: 5, rows: 3) == Vector(0.5, 1))
    }

    @Test("A grid of one column or row divides by one rather than zero")
    func gridPositionDegenerate() {
        #expect(PenMeshPoint.gridPosition(column: 0, row: 1, columns: 1, rows: 2) == Vector(0, 1))
    }

    // MARK: - Where Pen places it

    private static let grid = Vector(0.5, 0)
    private static let defaults = PenMeshPoint.Handles.defaults(columns: 3, rows: 2)

    private func placement(_ json: String) throws -> PenMeshPoint.Placement? {
        try decoded(json).placement(gridPosition: Self.grid, defaults: Self.defaults)
    }

    @Test("A well-formed point is placed where it says, with its handles resolved")
    func wellFormedPlacement() throws {
        var handles = Self.defaults
        handles.left = Vector(-0.3, 0.2)
        #expect(try placement(##"{"position":[0.3,0.2],"leftHandle":[-0.3,0.2]}"##)
            == PenMeshPoint.Placement(position: Vector(0.3, 0.2), handles: handles))
        #expect(try placement("[0.3,0.2]") == PenMeshPoint.Placement(position: Vector(0.3, 0.2), handles: Self.defaults))
    }

    @Test(
        "A point that is neither an array nor an object takes its grid position and default handles",
        arguments: [##""oops""##, "null", "42", "true"]
    )
    func scalarTakesGridPosition(json: String) throws {
        #expect(try placement(json) == PenMeshPoint.Placement(position: Self.grid, handles: Self.defaults))
    }

    @Test("An object whose position is missing or null takes its grid position and keeps its handles")
    func missingPositionTakesGridPosition() throws {
        #expect(try placement("{}") == PenMeshPoint.Placement(position: Self.grid, handles: Self.defaults))
        #expect(try placement(##"{"position":null}"##)
            == PenMeshPoint.Placement(position: Self.grid, handles: Self.defaults))
        var handles = Self.defaults
        handles.left = Vector(-0.3, 0.2)
        #expect(try placement(##"{"leftHandle":[-0.3,0.2]}"##)
            == PenMeshPoint.Placement(position: Self.grid, handles: handles))
    }

    @Test("Pen reads the first two numbers of a longer array")
    func longArrayIsTruncated() throws {
        #expect(try placement("[0.3,0.2,9]")
            == PenMeshPoint.Placement(position: Vector(0.3, 0.2), handles: Self.defaults))
        #expect(try placement(##"[0.3,0.2,"x"]"##)
            == PenMeshPoint.Placement(position: Vector(0.3, 0.2), handles: Self.defaults))
        #expect(try placement(##"{"position":[0.3,0.2,5]}"##)
            == PenMeshPoint.Placement(position: Vector(0.3, 0.2), handles: Self.defaults))
        var handles = Self.defaults
        handles.left = Vector(-0.3, 0.2)
        #expect(try placement(##"{"position":[0.3,0.2],"leftHandle":[-0.3,0.2,5]}"##)
            == PenMeshPoint.Placement(position: Vector(0.3, 0.2), handles: handles))
    }

    @Test("Pen reads null as 0 and a boolean as 0 or 1 inside an array")
    func arithmeticCoercions() throws {
        #expect(try placement("[0.3,null]") == PenMeshPoint.Placement(position: Vector(0.3, 0), handles: Self.defaults))
        #expect(try placement("[true,false]") == PenMeshPoint.Placement(position: Vector(1, 0), handles: Self.defaults))
    }

    @Test("A null handle takes its default")
    func nullHandleTakesDefault() throws {
        #expect(try placement(##"{"position":[0.3,0.2,1],"leftHandle":null}"##)
            == PenMeshPoint.Placement(position: Vector(0.3, 0.2), handles: Self.defaults))
    }

    @Test(
        "Pen cannot place a short array, a non-number entry, or a position or handle that is not an array",
        arguments: [
            "[]", "[1]", ##"["0.3","0.2"]"##, "[[0.3],[0.2]]", ##"[0.3,"x"]"##, ##"{"position":"oops"}"##,
            ##"{"position":[1]}"##, ##"{"position":[0.3,0.2],"leftHandle":[1]}"##,
            ##"{"position":[0.3,0.2],"leftHandle":"oops"}"##, ##"{"position":[0.3,0.2],"leftHandle":{}}"##,
        ]
    )
    func unplaceable(json: String) throws {
        #expect(try placement(json) == nil)
    }
}
