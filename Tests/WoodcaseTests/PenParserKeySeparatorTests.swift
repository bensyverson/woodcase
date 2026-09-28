//
//  PenParserKeySeparatorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins the `"key": value` spelling ``PenParser/encodeForFile(_:)`` writes, over the keys
/// and values that could confuse the pass that rewrites Foundation's `"key" : value`: a
/// value spelling `" : "` itself, escaped quotes and backslashes in a key, and lines that
/// hold no key at all.
struct PenParserKeySeparatorTests {
    /// The file encoding of `value`, as a string.
    private func encoded(_ value: some Encodable) throws -> String {
        try String(decoding: PenParser.encodeForFile(value), as: UTF8.self)
    }

    @Test("a key's separator is tightened and a value's lookalike is not")
    func valueSpellingASeparator() throws {
        let text = try encoded(["a": "x\" : y", "b": "\" : \""])
        #expect(text == """
        {
          "a": "x\\" : y",
          "b": "\\" : \\""
        }

        """)
    }

    @Test("a key with an escaped quote or a trailing backslash is still one key")
    func escapedKeys() throws {
        let text = try encoded(["q\"k": 1, "back\\": 2, "": 3])
        #expect(text == """
        {
          "": 3,
          "back\\\\": 2,
          "q\\"k": 1
        }

        """)
    }

    @Test("nested objects and arrays keep every line that holds no key as it was")
    func nesting() throws {
        let text = try encoded(["outer": ["inner": [1, 2]], "list": [["k": "v"]]] as [String: AnyCodable])
        #expect(text == """
        {
          "list": [
            {
              "k": "v"
            }
          ],
          "outer": {
            "inner": [
              1,
              2
            ]
          }
        }

        """)
    }

    @Test("a value holding a newline and a lookalike stays on its own escaped line")
    func escapedNewline() throws {
        let text = try encoded(["a": "line\n\"k\" : v"])
        #expect(text == """
        {
          "a": "line\\n\\"k\\" : v"
        }

        """)
    }
}
