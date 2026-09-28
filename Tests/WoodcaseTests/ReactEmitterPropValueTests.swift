//
//  ReactEmitterPropValueTests.swift
//  WoodcaseTests
//

import Testing
@testable import Woodcase

/// Pins how the React emitter writes each typed prop value as a JSX attribute value.
struct ReactEmitterPropValueTests {
    private static let cases: [(PropMapper.Value, String)] = [
        (.string("Custom Title"), "\"Custom Title\""),
        (.color(.literal("#FF5500")), "\"#FF5500\""),
        (.color(.variable("primary")), "\"var(--primary)\""),
        (.boolean(false), "{false}"),
        (.boolean(true), "{true}"),
        (.imageURL("./images/photo.png"), "\"./images/photo.png\""),
    ]

    @Test("Each typed prop value becomes the JSX attribute value React has always written", arguments: cases)
    func jsxAttributeValue(value: PropMapper.Value, expected: String) {
        #expect(ReactEmitter.jsxAttributeValue(value) == expected)
    }

    @Test("A string holding a double quote becomes a JS string expression, which JSX can escape")
    func quotedString() {
        #expect(ReactEmitter.jsxAttributeValue(.string(#"Say "hi" \ bye"#)) == #"{"Say \"hi\" \\ bye"}"#)
        #expect(ReactEmitter.jsxAttributeValue(.imageURL(#"a"b.png"#)) == #"{"a\"b.png"}"#)
    }
}
