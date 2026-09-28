//
//  PenMeshPointTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Covers ``PenMeshPoint``: the two wire forms a mesh vertex takes, the default handles
/// Pen gives an omitted one, and the canonical form Pen's serialiser writes.
///
/// The canonical-form expectations here are single cases; the evidence that they are
/// *Pen's* rule is `PenMeshGradientFixtureTests`, which compares against Pen's own
/// re-save of `mesh-point-elision.pen`.
struct PenMeshPointTests {
    private let decoder = JSONDecoder()

    private func encoded(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try String(decoding: encoder.encode(value), as: UTF8.self)
    }

    private func decoded(_ json: String) throws -> PenMeshPoint {
        try decoder.decode(PenMeshPoint.self, from: Data(json.utf8))
    }

    // MARK: - The two wire forms

    @Test("A bare [x, y] decodes as a bare point")
    func bareDecodes() throws {
        #expect(try decoded("[0.25,0.75]") == .bare(PenMeshPoint.Vector(0.25, 0.75)))
    }

    @Test("An object decodes with exactly the handles it wrote")
    func objectDecodes() throws {
        let point = try decoded(##"{"position":[0.5,0],"bottomHandle":[0.25,0.4]}"##)
        #expect(point == .object(PenMeshPoint.Object(
            position: PenMeshPoint.Vector(0.5, 0),
            bottomHandle: PenMeshPoint.Vector(0.25, 0.4)
        )))
    }

    @Test("A bare point encodes back as a bare array")
    func bareRoundTrips() throws {
        #expect(try encoded(decoded("[0.25,0.75]")) == "[0.25,0.75]")
    }

    @Test("An object with no handles stays an object")
    func handlelessObjectRoundTrips() throws {
        #expect(try encoded(decoded(##"{"position":[1,0]}"##)) == ##"{"position":[1,0]}"##)
    }

    @Test("An object encodes only the handles it was written with")
    func objectRoundTrips() throws {
        let json = ##"{"leftHandle":[-0.1,-0.05],"position":[0.6,0.7],"rightHandle":[0.15,0.2]}"##
        #expect(try encoded(decoded(json)) == json)
    }

    /// Authoring input refuses what a file decode keeps as ``PenMeshPoint/malformed(_:)``;
    /// `PenMeshPointMalformedTests` covers the file side.
    private func authored(_ json: String) throws -> PenMeshPoint {
        let decoder = JSONDecoder()
        decoder.userInfo[PenDecodingMode.userInfoKey] = PenDecodingMode.authoring
        return try decoder.decode(PenMeshPoint.self, from: Data(json.utf8))
    }

    @Test("Authoring refuses a position that is not two numbers", arguments: ["[1]", "[1,2,3]", ##""#FF0000""##, "{}"])
    func malformedIsRefused(json: String) {
        #expect(throws: DecodingError.self) { try authored(json) }
    }

    @Test("Authoring refuses a handle that is not two numbers")
    func malformedHandleIsRefused() {
        #expect(throws: DecodingError.self) { try authored(##"{"position":[0,0],"topHandle":[1]}"##) }
    }

    @Test("position reads through either form")
    func positionReadsThroughEitherForm() throws {
        #expect(try decoded("[0.1,0.2]").position == PenMeshPoint.Vector(0.1, 0.2))
        #expect(try decoded(##"{"position":[0.3,0.4]}"##).position == PenMeshPoint.Vector(0.3, 0.4))
    }

    // MARK: - Default handles

    @Test("Default handles are a quarter of a cell on each axis")
    func defaultHandlesAreAQuarterCell() {
        let handles = PenMeshPoint.Handles.defaults(columns: 3, rows: 2)
        #expect(handles.left == PenMeshPoint.Vector(-0.125, 0))
        #expect(handles.right == PenMeshPoint.Vector(0.125, 0))
        #expect(handles.top == PenMeshPoint.Vector(0, -0.25))
        #expect(handles.bottom == PenMeshPoint.Vector(0, 0.25))
    }

    @Test("A single column or row divides by one, not zero")
    func degenerateGridDividesByOne() {
        let handles = PenMeshPoint.Handles.defaults(columns: 1, rows: 1)
        #expect(handles.right == PenMeshPoint.Vector(0.25, 0))
        #expect(handles.bottom == PenMeshPoint.Vector(0, 0.25))
    }

    @Test("A bare point takes every default handle")
    func bareTakesDefaults() throws {
        let defaults = PenMeshPoint.Handles.defaults(columns: 2, rows: 2)
        #expect(try decoded("[0,0]").handles(defaults: defaults) == defaults)
    }

    @Test("An object's missing handles fall back to the defaults, one by one")
    func objectFillsMissingHandles() throws {
        let defaults = PenMeshPoint.Handles.defaults(columns: 2, rows: 2)
        let point = try decoded(##"{"position":[0,0],"rightHandle":[1.2,0.6]}"##)
        let handles = try #require(point.handles(defaults: defaults))
        #expect(handles.right == PenMeshPoint.Vector(1.2, 0.6))
        #expect(handles.left == defaults.left)
        #expect(handles.top == defaults.top)
        #expect(handles.bottom == defaults.bottom)
    }

    // MARK: - Canonical form

    private let defaults3x2 = PenMeshPoint.Handles.defaults(columns: 3, rows: 2)

    @Test("Every handle at its default makes the point bare")
    func allDefaultsBecomeBare() throws {
        let point = try decoded(
            ##"{"position":[0,0],"leftHandle":[-0.125,0],"rightHandle":[0.125,0],"topHandle":[0,-0.25],"bottomHandle":[0,0.25]}"##
        )
        #expect(point.canonicalized(defaults: defaults3x2) == .bare(PenMeshPoint.Vector(0, 0)))
    }

    @Test("A handle within the tolerance of its default counts as the default")
    func nearDefaultIsDefault() throws {
        let point = try decoded(##"{"position":[0.5,0],"leftHandle":[-0.12509,0],"rightHandle":[0.125,0.00009]}"##)
        #expect(point.canonicalized(defaults: defaults3x2) == .bare(PenMeshPoint.Vector(0.5, 0)))
    }

    @Test("A handle past the tolerance is kept, and only the default ones are dropped")
    func farHandleIsKept() throws {
        let point = try decoded(
            ##"{"position":[1,0],"leftHandle":[-0.125,0],"rightHandle":[0.3,0.1],"topHandle":[0,-0.2502]}"##
        )
        #expect(point.canonicalized(defaults: defaults3x2) == .object(PenMeshPoint.Object(
            position: PenMeshPoint.Vector(1, 0),
            rightHandle: PenMeshPoint.Vector(0.3, 0.1),
            topHandle: PenMeshPoint.Vector(0, -0.2502)
        )))
    }

    @Test("The tolerance is judged on the value as written, before rounding")
    func toleranceIsJudgedBeforeRounding() throws {
        // 0.12514 rounds to 0.1251, which is within 1e-4 of 0.125; Pen keeps it anyway.
        let point = try decoded(##"{"position":[0,0],"rightHandle":[0.12514,0]}"##)
        #expect(point.canonicalized(defaults: defaults3x2) == .object(PenMeshPoint.Object(
            position: PenMeshPoint.Vector(0, 0),
            rightHandle: PenMeshPoint.Vector(0.1251, 0)
        )))
    }

    @Test("Positions and handles round to four decimal places")
    func valuesRound() throws {
        let point = try decoded(##"{"position":[0.123456789,0.987654321],"topHandle":[0.0123456,-0.3333333]}"##)
        #expect(point.canonicalized(defaults: defaults3x2) == .object(PenMeshPoint.Object(
            position: PenMeshPoint.Vector(0.1235, 0.9877),
            topHandle: PenMeshPoint.Vector(0.0123, -0.3333)
        )))
    }

    @Test("A value that rounds to zero is written as 0, never -0")
    func noNegativeZero() throws {
        let point = try decoded("[-0.00001,1]").canonicalized(defaults: defaults3x2)
        #expect(try encoded(point) == "[0,1]")
    }
}
