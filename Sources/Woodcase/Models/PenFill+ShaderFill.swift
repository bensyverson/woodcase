//
//  PenFill+ShaderFill.swift
//  Woodcase
//

import Foundation

public extension PenFill {
    /// A GPU fragment shader fill.
    ///
    /// Woodcase preserves shader fills losslessly but never executes them: the
    /// renderer treats a shader fill as fully transparent, and the React
    /// emitter emits no background for it.
    struct PenShaderFill: Friendly {
        public init(
            enabled: PenValue<Bool>? = nil,
            blendMode: PenBlendMode? = nil,
            opacity: PenValue<Double>? = nil,
            url: String,
            uniforms: [String: PenShaderUniform]? = nil,
            extras: PenExtras = PenExtras()
        ) {
            self.enabled = enabled
            self.blendMode = blendMode
            self.opacity = opacity
            self.url = url
            self.uniforms = uniforms
            self.extras = extras
        }

        public var enabled: PenValue<Bool>?
        public var blendMode: PenBlendMode?
        public var opacity: PenValue<Double>?
        /// The shader file's URL, relative to the .pen file (e.g. `"effect.glsl"`).
        public var url: String
        /// Named uniform values passed to the shader.
        public var uniforms: [String: PenShaderUniform]?

        /// Keys the file wrote on this fill that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys this payload claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case enabled, blendMode, opacity, url, uniforms
        }
    }
}

/// A single uniform value passed to a ``PenFill/PenShaderFill`` shader.
///
/// A shader uniform is whichever JSON scalar the .pen file wrote: a number, a
/// boolean, a hex color string (`"#RRGGBB"` or `"#RRGGBBAA"`), a 2–4 component
/// numeric vector, or a `$variable` reference.
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

// MARK: - Codable

public extension PenShaderUniform {
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
