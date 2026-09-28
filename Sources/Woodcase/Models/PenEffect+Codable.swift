//
//  PenEffect+Codable.swift
//  Woodcase
//

import Foundation

/// An effect's wire form: an object whose `type` selects the payload.
extension PenEffect {
    /// Every effect `type` this build models, in the .pen file's spelling.
    enum EffectType: String, Codable, CaseIterable {
        case blur
        case backgroundBlur = "background_blur"
        case shadow
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    /// Decodes an effect object.
    ///
    /// Each modelled payload keeps the keys it does not claim in its `extras`. An
    /// unrecognised `type` becomes ``unknown(typeName:payload:)`` in
    /// ``PenDecodingMode/file`` and stays a decoding error in ``PenDecodingMode/authoring``,
    /// where it is almost always a misspelling.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` for a missing `type`, a payload of the wrong shape, or —
    ///   in authoring mode — an unknown `type` or key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard PenDecodingMode.of(decoder) == .file else {
            self = try Self.decode(container.decode(EffectType.self, forKey: .type), from: decoder)
            return
        }
        let typeName = try container.decode(String.self, forKey: .type)
        guard let type = EffectType(rawValue: typeName) else {
            self = try .unknown(
                typeName: typeName,
                payload: PenExtras.capture(from: decoder, claiming: [CodingKeys.type.stringValue], describing: "an effect")
            )
            return
        }
        self = try Self.decode(type, from: decoder)
    }

    /// Encodes the effect object, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .blur(effect):
            try effect.extras.encode(into: encoder)
            try container.encode(EffectType.blur, forKey: .type)
            try effect.encode(to: encoder)
        case let .backgroundBlur(effect):
            try effect.extras.encode(into: encoder)
            try container.encode(EffectType.backgroundBlur, forKey: .type)
            try effect.encode(to: encoder)
        case let .shadow(effect):
            try effect.extras.encode(into: encoder)
            try container.encode(EffectType.shadow, forKey: .type)
            try effect.encode(to: encoder)
        case let .unknown(typeName, payload):
            try payload.encode(into: encoder)
            try container.encode(typeName, forKey: .type)
        }
    }

    // MARK: - Private

    /// Decodes the payload a modelled `type` selects, with its extras.
    private static func decode(_ type: EffectType, from decoder: Decoder) throws -> PenEffect {
        switch type {
        case .blur:
            var effect = try PenBlurEffect(from: decoder)
            effect.extras = try capture(from: decoder, claiming: PenBlurEffect.CodingKeys.self, describing: "a blur effect")
            return .blur(effect)
        case .backgroundBlur:
            var effect = try PenBackgroundBlurEffect(from: decoder)
            effect.extras = try capture(
                from: decoder, claiming: PenBackgroundBlurEffect.CodingKeys.self, describing: "a background_blur effect"
            )
            return .backgroundBlur(effect)
        case .shadow:
            var effect = try PenShadowEffect(from: decoder)
            effect.extras = try capture(from: decoder, claiming: PenShadowEffect.CodingKeys.self, describing: "a shadow effect")
            return .shadow(effect)
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
