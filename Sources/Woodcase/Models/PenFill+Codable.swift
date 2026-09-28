//
//  PenFill+Codable.swift
//  Woodcase
//

import Foundation

/// A fill's wire form: a bare colour string, or an object whose `type` selects the payload.
extension PenFill {
    /// Every fill `type` this build models, in the .pen file's spelling.
    enum FillType: String, Codable, CaseIterable {
        case color
        case gradient
        case image
        case meshGradient = "mesh_gradient"
        case shader
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    /// Decodes a fill: a colour string, or a fill object.
    ///
    /// Each modelled payload keeps the keys it does not claim in its `extras`. An
    /// unrecognised `type` becomes ``unknown(typeName:payload:)`` in
    /// ``PenDecodingMode/file`` and stays a decoding error in ``PenDecodingMode/authoring``,
    /// where `"solid"` for `"color"` is the usual mistake.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for a missing `type`, a payload of the wrong shape, or —
    ///   in authoring mode — an unknown `type` or key.
    public init(from decoder: Decoder) throws {
        // First try as a bare string (shorthand color or variable)
        if let container = try? decoder.singleValueContainer(),
           let string = try? container.decode(String.self)
        {
            self = .shorthand(string)
            return
        }

        // Otherwise it's an object with a "type" field
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard PenDecodingMode.of(decoder) == .file else {
            self = try Self.decode(container.decode(FillType.self, forKey: .type), from: decoder)
            return
        }
        let typeName = try container.decode(String.self, forKey: .type)
        guard let type = FillType(rawValue: typeName) else {
            self = try .unknown(
                typeName: typeName,
                payload: PenExtras.capture(from: decoder, claiming: [CodingKeys.type.stringValue], describing: "a fill")
            )
            return
        }
        self = try Self.decode(type, from: decoder)
    }

    /// Encodes the fill, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .shorthand(string):
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case let .color(fill):
            try encode(fill, as: .color, extras: fill.extras, to: encoder)
        case let .gradient(fill):
            try encode(fill, as: .gradient, extras: fill.extras, to: encoder)
        case let .image(fill):
            try encode(fill, as: .image, extras: fill.extras, to: encoder)
        case let .meshGradient(fill):
            try encode(fill, as: .meshGradient, extras: fill.extras, to: encoder)
        case let .shader(fill):
            try encode(fill, as: .shader, extras: fill.extras, to: encoder)
        case let .unknown(typeName, payload):
            try payload.encode(into: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeName, forKey: .type)
        }
    }

    // MARK: - Private

    /// Writes one modelled payload as a fill object: its extras, its `type`, its keys.
    private func encode(_ payload: some Encodable, as type: FillType, extras: PenExtras, to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try payload.encode(to: encoder)
    }

    /// Decodes the payload a modelled `type` selects, with its extras.
    private static func decode(_ type: FillType, from decoder: Decoder) throws -> PenFill {
        switch type {
        case .color:
            var fill = try PenColorFill(from: decoder)
            fill.extras = try capture(from: decoder, claiming: PenColorFill.CodingKeys.self, describing: "a color fill")
            return .color(fill)
        case .gradient:
            var fill = try PenGradientFill(from: decoder)
            fill.extras = try capture(from: decoder, claiming: PenGradientFill.CodingKeys.self, describing: "a gradient fill")
            return .gradient(fill)
        case .image:
            var fill = try PenImageFill(from: decoder)
            fill.extras = try capture(from: decoder, claiming: PenImageFill.CodingKeys.self, describing: "an image fill")
            return .image(fill)
        case .meshGradient:
            var fill = try PenMeshGradientFill(from: decoder)
            fill.extras = try capture(
                from: decoder, claiming: PenMeshGradientFill.CodingKeys.self, describing: "a mesh_gradient fill"
            )
            return .meshGradient(fill)
        case .shader:
            var fill = try PenShaderFill(from: decoder)
            fill.extras = try capture(from: decoder, claiming: PenShaderFill.CodingKeys.self, describing: "a shader fill")
            return .shader(fill)
        }
    }

    /// The keys of a payload's object that neither the payload nor `type` claims.
    private static func capture<Keys: CodingKey & CaseIterable>(
        from decoder: Decoder,
        claiming _: Keys.Type,
        describing owner: String
    ) throws -> PenExtras {
        let claimed = Set(Keys.allCases.map(\.stringValue)).union([CodingKeys.type.stringValue])
        return try PenExtras.capture(from: decoder, claiming: claimed, describing: owner)
    }
}
