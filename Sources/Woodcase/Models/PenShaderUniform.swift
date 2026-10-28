//
//  PenShaderUniform.swift
//  Woodcase
//

import Foundation

/// A shader's uniform values, keyed by uniform name: the format's `ShaderUniforms` (2.21),
/// which a shader fill (``PenFill/PenShaderFill``) and a shader effect
/// (``PenEffect/PenShaderEffect``) both take.
///
/// Uniforms annotated `@resolution` or `@time` are bound by the runtime and never appear here.
public typealias PenShaderUniforms = [String: PenShaderUniform]

/// A single uniform value passed to a shader fill's or a shader effect's shader.
///
/// A shader uniform is whichever JSON scalar the .pen file wrote: a number, a
/// boolean, a hex color string (`"#RRGGBB"` or `"#RRGGBBAA"`), a 2–4 component
/// numeric vector, or a `$variable` reference.
///
/// - Note: Format 2.21 (pen CLI 0.3.13) also lets a `sampler2D` uniform take an image URL,
///   `"pencil:object"` or `"pencil:background"`. Those strings read as ``color(_:)`` and are
///   written back unchanged.
public enum PenShaderUniform: Friendly {
    /// A numeric literal.
    case number(Double)
    /// A boolean literal.
    case bool(Bool)
    /// A hex color string, e.g. `"#RRGGBB"` or `"#RRGGBBAA"`.
    case color(String)
    /// A 2–4 component numeric vector.
    case vector([Double])
    /// A reference to a named variable (without the `$` prefix).
    case variable(String)
}

// MARK: - Schema

public extension PenShaderUniform {
    /// The `uniforms` key of a shader fill's and a shader effect's key tables: one row for
    /// both, as the format's one `ShaderUniforms` type is.
    static let schemaField = PenNestedShape.Field(
        key: "uniforms",
        forms: [.open(PenValueForm.OpenShape(
            phrase: "an object of uniform names to numbers, colors, booleans or vectors",
            signature: "{name: number | color | boolean | [number, …] | $var}"
        ))]
    )
}

// MARK: - Codable

public extension PenShaderUniform {
    /// Decodes whichever JSON shape the file wrote; a string with a leading `$` is a variable.
    ///
    /// - Throws: `DecodingError` for an array outside 2–4 numbers, or any other shape.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            if string.hasPrefix("$") {
                self = .variable(String(string.dropFirst()))
            } else {
                self = .color(string)
            }
        } else {
            let array = try container.decode([Double].self)
            guard (2 ... 4).contains(array.count) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Shader uniform vector must have 2-4 components, got \(array.count)"
                )
            }
            self = .vector(array)
        }
    }

    /// Encodes the value in the shape it was read in, a variable with its `$`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .color(value):
            try container.encode(value)
        case let .variable(name):
            try container.encode("$\(name)")
        case let .vector(values):
            try container.encode(values)
        }
    }
}
