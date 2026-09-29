//
//  NodePropertyCoercionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A number written where a string-or-`$variable` property is expected is stored as
/// the string it spells; every other mismatch is still refused.
@MainActor
struct NodePropertyCoercionTests {
    // MARK: - Helpers

    private func text() -> PenNode {
        PenNode(
            id: "t1",
            common: PenNodeCommon(name: "Title"),
            kind: .text(PenNode.TextData(content: .literal("Hello")))
        )
    }

    private func value(_ path: String, of node: PenNode) throws -> AnyCodable {
        try NodePropertyCodec.value(at: path, of: node)
    }

    // MARK: - Coercion

    @Test("An integer written to kind.content is stored as its string")
    func integerBecomesString() throws {
        let patched = try NodePropertyCodec.setting(.int(3), at: "kind.content", on: text())
        #expect(try value("kind.content", of: patched) == .string("3"))
    }

    @Test("A fractional number keeps its decimals; an integral one loses its point")
    func doublesSpellThemselves() throws {
        let fraction = try NodePropertyCodec.setting(.double(0.5), at: "kind.content", on: text())
        #expect(try value("kind.content", of: fraction) == .string("0.5"))

        let whole = try NodePropertyCodec.setting(.double(3.0), at: "kind.content", on: text())
        #expect(try value("kind.content", of: whole) == .string("3"))
    }

    @Test("A negative number keeps its sign")
    func negativeNumbers() throws {
        let patched = try NodePropertyCodec.setting(.int(-12), at: "kind.content", on: text())
        #expect(try value("kind.content", of: patched) == .string("-12"))
    }

    @Test("Every string-or-$variable field coerces, not kind.content alone")
    func otherStringFieldsCoerce() throws {
        let family = try NodePropertyCodec.setting(.int(2), at: "kind.fontFamily", on: text())
        #expect(try value("kind.fontFamily", of: family) == .string("2"))

        let weight = try NodePropertyCodec.setting(.int(700), at: "kind.fontWeight", on: text())
        #expect(try value("kind.fontWeight", of: weight) == .string("700"))
    }

    @Test("A $variable reference is untouched by the coercion")
    func variableReferenceSurvives() throws {
        let patched = try NodePropertyCodec.setting(.string("$headline"), at: "kind.content", on: text())
        #expect(try value("kind.content", of: patched) == .string("$headline"))
    }

    // MARK: - What is still refused

    @Test("A string where a number belongs is still refused")
    func stringForNumberIsRefused() throws {
        #expect(throws: EditingError.self) {
            try NodePropertyCodec.setting(.string("big"), at: "kind.fontSize", on: text())
        }
    }

    @Test("An object where content belongs is still refused")
    func objectForContentIsRefused() throws {
        #expect(throws: EditingError.self) {
            try NodePropertyCodec.setting(.dictionary(["text": .string("Hi")]), at: "kind.content", on: text())
        }
    }

    @Test("A boolean where content belongs is still refused — only numbers coerce")
    func booleanForContentIsRefused() throws {
        #expect(throws: EditingError.self) {
            try NodePropertyCodec.setting(.bool(true), at: "kind.content", on: text())
        }
    }

    @Test("A number written to a property that is not string-or-$variable is left alone")
    func numberForNumberStaysANumber() throws {
        let patched = try NodePropertyCodec.setting(.int(18), at: "kind.fontSize", on: text())
        #expect(try value("kind.fontSize", of: patched) == .int(18))
    }

    @Test("A node of an unrecognized type keeps the number it was given")
    func unknownKindKeepsTheNumber() throws {
        let node = PenNode(
            id: "u1",
            common: PenNodeCommon(name: "Odd"),
            kind: .unknown(typeName: "widget", properties: [:])
        )
        let patched = try NodePropertyCodec.setting(.int(3), at: "kind.content", on: node)
        #expect(try value("kind.content", of: patched) == .int(3))
    }

    @Test("Clearing a string property with null still clears it")
    func nullStillClears() throws {
        let patched = try NodePropertyCodec.setting(.null, at: "kind.content", on: text())
        #expect(try value("kind.content", of: patched) == .null)
    }
}
