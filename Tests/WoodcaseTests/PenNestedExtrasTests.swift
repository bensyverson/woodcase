//
//  PenNestedExtrasTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Covers ``PenExtras`` below the payload level: every nested .pen object the model
/// decodes into a struct of its own — a gradient stop, a gradient's center and size, a
/// shadow's offset, a variable definition and each of its themed values, a mesh vertex
/// written as an object, and a connection's endpoints — keeps the keys it does not
/// claim through a file round trip, and refuses them in authoring input.
struct PenNestedExtrasTests {
    // MARK: - Helpers

    /// Decodes `json` as a file is decoded, encodes it back, and returns both sides as
    /// JSON objects for a semantic comparison.
    private static func roundTrip<T: Codable>(
        _ type: T.Type,
        _ json: String
    ) throws -> (decoded: T, original: NSDictionary, written: NSDictionary) {
        let decoded = try PenExtrasDecodingTests.filed(type, json)
        let written = try JSONEncoder().encode(decoded)
        return try (
            decoded,
            PenExtrasDecodingTests.object(Data(json.utf8)),
            PenExtrasDecodingTests.object(written)
        )
    }

    // MARK: - Fixtures

    static let gradient = #"""
    {"type":"gradient","gradientType":"radial",
     "center":{"x":0.5,"y":0.5,"futureCenterKey":"c"},
     "size":{"width":1,"height":1,"futureSizeKey":true},
     "colors":[{"color":"#FF0000","position":0,"futureStopKey":1},{"color":"#0000FF","position":1}]}
    """#

    static let shadow = #"""
    {"type":"shadow","blur":4,"offset":{"x":1,"y":2,"futureOffsetKey":3}}
    """#

    static let simpleVariable = ##"{"type":"color","value":"#FFFFFF","futureVariableKey":1}"##

    static let themedVariable = #"""
    {"type":"color","value":[{"value":"#FFFFFF"},{"value":"#000000","theme":{"mode":"dark"},"futureThemedKey":2}]}
    """#

    static let meshPoint = #"{"position":[0.5,0.5],"leftHandle":[-0.2,0],"futurePointKey":"p"}"#

    static let connection = #"""
    {"id":"C","type":"connection",
     "source":{"path":"A","anchor":"right","futureEndpointKey":[1]},
     "target":{"path":"B","anchor":"left"}}
    """#

    static let perSideStrokeWidth = #"{"top":1,"right":2,"bottom":3,"left":4,"futureSideKey":5}"#

    // MARK: - Round trips

    @Test("A gradient stop keeps a key it does not claim")
    func gradientStop() throws {
        let trip = try Self.roundTrip(PenFill.self, Self.gradient)
        #expect(trip.written == trip.original)
        guard case let .gradient(fill) = trip.decoded else {
            Issue.record("not a gradient: \(trip.decoded)")
            return
        }
        #expect(fill.colors?.first?.extras.values == ["futureStopKey": 1])
        #expect(fill.colors?.last?.extras.isEmpty == true)
    }

    @Test("A gradient's center keeps a key it does not claim")
    func gradientCenter() throws {
        let trip = try Self.roundTrip(PenFill.self, Self.gradient)
        let written = trip.written["center"] as? NSDictionary
        #expect(written == trip.original["center"] as? NSDictionary)
        guard case let .gradient(fill) = trip.decoded else { return }
        #expect(fill.center?.extras.values == ["futureCenterKey": "c"])
    }

    @Test("A gradient's size keeps a key it does not claim")
    func gradientSize() throws {
        let trip = try Self.roundTrip(PenFill.self, Self.gradient)
        let written = trip.written["size"] as? NSDictionary
        #expect(written == trip.original["size"] as? NSDictionary)
        guard case let .gradient(fill) = trip.decoded else { return }
        #expect(fill.size?.extras.values == ["futureSizeKey": true])
    }

    @Test("A shadow's offset keeps a key it does not claim")
    func shadowOffset() throws {
        let trip = try Self.roundTrip(PenEffect.self, Self.shadow)
        #expect(trip.written == trip.original)
        guard case let .shadow(shadow) = trip.decoded else {
            Issue.record("not a shadow: \(trip.decoded)")
            return
        }
        #expect(shadow.offset?.extras.values == ["futureOffsetKey": 3])
    }

    @Test("A variable definition keeps a key it does not claim")
    func variableDefinition() throws {
        let trip = try Self.roundTrip(PenVariable.self, Self.simpleVariable)
        #expect(trip.written == trip.original)
        #expect(trip.decoded.extras.values == ["futureVariableKey": 1])
    }

    @Test("A themed variable value keeps a key it does not claim")
    func themedValue() throws {
        let trip = try Self.roundTrip(PenVariable.self, Self.themedVariable)
        #expect(trip.written == trip.original)
        guard case let .themed(values) = trip.decoded.value else {
            Issue.record("not themed: \(trip.decoded.value)")
            return
        }
        #expect(values.map(\.extras.values) == [[:], ["futureThemedKey": 2]])
    }

    @Test("A mesh vertex written as an object keeps a key it does not claim")
    func meshPointObject() throws {
        let trip = try Self.roundTrip(PenMeshPoint.self, Self.meshPoint)
        #expect(trip.written == trip.original)
        guard case let .object(point) = trip.decoded else {
            Issue.record("not an object point: \(trip.decoded)")
            return
        }
        #expect(point.extras.values == ["futurePointKey": "p"])
    }

    @Test("Canonicalizing a mesh vertex keeps its extras, even with every handle at its default")
    func meshPointCanonicalKeepsExtras() throws {
        let point = try PenExtrasDecodingTests.filed(PenMeshPoint.self, #"{"position":[0.5,0.5],"futurePointKey":"p"}"#)
        let canonical = point.canonicalized(defaults: .defaults(columns: 2, rows: 2))
        guard case let .object(object) = canonical else {
            Issue.record("the vertex lost its object form, and its extras with it: \(canonical)")
            return
        }
        #expect(object.extras.values == ["futurePointKey": "p"])
    }

    @Test("A connection's endpoint keeps a key it does not claim")
    func connectionEndpoint() throws {
        let trip = try Self.roundTrip(PenNode.self, Self.connection)
        #expect(trip.written == trip.original)
        guard case let .connection(data) = trip.decoded.kind else {
            Issue.record("not a connection: \(trip.decoded.kind)")
            return
        }
        #expect(data.source.extras.values == ["futureEndpointKey": [1]])
        #expect(data.target.extras.isEmpty)
    }

    @Test("A per-side strokeWidth object keeps a key it does not claim")
    func perSideStrokeWidth() throws {
        let trip = try Self.roundTrip(PenStrokeWidth.self, Self.perSideStrokeWidth)
        #expect(trip.written == trip.original)
        guard case let .perSide(sides) = trip.decoded else {
            Issue.record("not per-side: \(trip.decoded)")
            return
        }
        #expect(sides.extras.values == ["futureSideKey": 5])
    }

    @Test("The theme and import maps are data, so every key already survives")
    func themeAndImportMaps() throws {
        let json = #"""
        {"version":"2.19","themes":{"mode":["light","dark"],"futureAxis":["x"]},
         "imports":{"kit":"kit.pen","future":"f.pen"},"children":[]}
        """#
        let trip = try Self.roundTrip(PenDocument.self, json)
        #expect(trip.written == trip.original)
    }

    // MARK: - Authoring

    /// Every nested fixture, with the unknown key the authoring decode must name.
    static let authoredCases: [(name: String, json: String, key: String)] = [
        ("gradient", gradient, "futureCenterKey"),
        ("shadow", shadow, "futureOffsetKey"),
        ("variable", simpleVariable, "futureVariableKey"),
        ("themed variable", themedVariable, "futureThemedKey"),
        ("mesh point", meshPoint, "futurePointKey"),
        ("connection", connection, "futureEndpointKey"),
        ("per-side stroke width", perSideStrokeWidth, "futureSideKey"),
    ]

    @Test("Authoring input with an unknown nested key is refused, naming the key", arguments: authoredCases)
    func authoringRefuses(_ testCase: (name: String, json: String, key: String)) throws {
        let refusal: (any Error)? = switch testCase.name {
        case "gradient": Self.failure { try PenExtrasDecodingTests.authored(PenFill.self, testCase.json) }
        case "shadow": Self.failure { try PenExtrasDecodingTests.authored(PenEffect.self, testCase.json) }
        case "variable", "themed variable":
            Self.failure { try PenExtrasDecodingTests.authored(PenVariable.self, testCase.json) }
        case "mesh point": Self.failure { try PenExtrasDecodingTests.authored(PenMeshPoint.self, testCase.json) }
        case "per-side stroke width":
            Self.failure { try PenExtrasDecodingTests.authored(PenStrokeWidth.self, testCase.json) }
        default: Self.failure { try PenExtrasDecodingTests.authored(PenNode.self, testCase.json) }
        }
        let error = try #require(refusal, "\(testCase.name) was accepted")
        #expect(String(describing: error).contains(testCase.key), "\(error)")
    }

    @Test("Each unknown gradient key is refused in authoring input on its own")
    func authoringRefusesEachGradientKey() {
        let cases = [
            "futureStopKey": ##"{"type":"gradient","colors":[{"color":"#FF0000","position":0,"futureStopKey":1}]}"##,
            "futureSizeKey": ##"{"type":"gradient","size":{"width":1,"height":1,"futureSizeKey":true}}"##,
        ]
        for (key, json) in cases {
            let refusal = Self.failure { try PenExtrasDecodingTests.authored(PenFill.self, json) }
            #expect(refusal.map { String(describing: $0).contains(key) } == true, "\(key): \(String(describing: refusal))")
        }
    }

    /// The error `body` throws, or `nil` when it succeeds.
    private static func failure(_ body: () throws -> some Any) -> (any Error)? {
        do {
            _ = try body()
            return nil
        } catch {
            return error
        }
    }
}
