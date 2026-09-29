//
//  ReactEmitter+PropValue.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    /// A typed prop value as a JSX attribute value: a quoted string, a color as its
    /// literal or `var(--name)`, a boolean in braces.
    static func jsxAttributeValue(_ value: PropMapper.Value) -> String {
        switch value {
        case let .string(text): jsxString(text)
        case let .color(color): emitPenValue(color)
        case let .boolean(flag): "{\(flag)}"
        case let .imageURL(url): jsxString(url)
        }
    }

    /// A string as a JSX attribute value: `"text"`, or `{"te\"xt"}` when it holds a double
    /// quote — a JSX attribute string has no escapes, so only a JS expression can carry one.
    private static func jsxString(_ text: String) -> String {
        guard text.contains("\"") else { return "\"\(text)\"" }
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "{\"\(escaped)\"}"
    }
}
