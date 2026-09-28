//
//  PenVariable.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// A variable definition in a .pen document.
///
/// Variables provide named, typed values that can be referenced throughout the document
/// via `$variableName`. Values can be simple or theme-conditional.
public struct PenVariable: Friendly {
    /// Creates a variable definition.
    ///
    /// - Parameters:
    ///   - type: The variable's type.
    ///   - value: Its value, simple or themed.
    ///   - extras: Keys a file wrote on the definition that the model does not claim.
    public init(
        type: PenVariableType,
        value: PenVariableValue,
        extras: PenExtras = PenExtras()
    ) {
        self.type = type
        self.value = value
        self.extras = extras
    }

    public var type: PenVariableType
    public var value: PenVariableValue

    /// Keys the file wrote on this definition that the model does not claim. See ``PenExtras``.
    public var extras = PenExtras()

    /// The keys a definition claims; any other key of its object is an extra.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case type, value
    }
}

/// The type of a .pen variable.
public enum PenVariableType: String, Friendly, CaseIterable {
    case boolean
    case color
    case number
    case string
}

/// The value of a .pen variable — either a simple value or an array of themed values.
public enum PenVariableValue: Friendly {
    case simple(AnyCodable)
    case themed([PenThemedValue])

    /// Decodes a simple value, or an array of themed values.
    ///
    /// In ``PenDecodingMode/authoring`` an array is decoded as themed values or refused,
    /// so a themed value with a key it does not claim is reported rather than quietly
    /// kept as a simple array. A file keeps the lenient fallback.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if the value is not JSON, or — authoring — for a
    ///   malformed themed value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if PenDecodingMode.of(decoder) == .authoring, (try? container.decode([AnyCodable].self)) != nil {
            self = try .themed(container.decode([PenThemedValue].self))
            return
        }
        // Try themed array first (array of objects with "value" and optional "theme")
        if let themed = try? container.decode([PenThemedValue].self) {
            self = .themed(themed)
        } else {
            // Simple value
            let value = try container.decode(AnyCodable.self)
            self = .simple(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .simple(value):
            try container.encode(value)
        case let .themed(values):
            try container.encode(values)
        }
    }
}

/// A theme-conditional variable value.
///
/// The value is used when the active theme satisfies all conditions in the `theme` dictionary.
/// The last matching themed value wins during evaluation.
public struct PenThemedValue: Friendly {
    /// Creates a themed value.
    ///
    /// - Parameters:
    ///   - value: The value used when the theme matches.
    ///   - theme: The axis → option conditions, or `nil` for the unconditional default.
    ///   - extras: Keys a file wrote on the object that the model does not claim.
    public init(
        value: AnyCodable,
        theme: [String: String]? = nil,
        extras: PenExtras = PenExtras()
    ) {
        self.value = value
        self.theme = theme
        self.extras = extras
    }

    public var value: AnyCodable
    public var theme: [String: String]?

    /// Keys the file wrote on this themed value that the model does not claim. See ``PenExtras``.
    public var extras = PenExtras()

    /// The keys a themed value claims; any other key of its object is an extra.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case value, theme
    }
}
