//
//  PenEffect.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// A visual effect applied to a .pen node.
///
/// The .pen format supports three effect types: blur, background blur, and shadow.
/// A node can have multiple effects (applied sequentially).
public enum PenEffect: Friendly {
    case blur(PenBlurEffect)

    /// A backdrop blur effect, blurring pixels already drawn behind the node.
    case backgroundBlur(PenBackgroundBlurEffect)

    case shadow(PenShadowEffect)

    /// An effect whose `type` this build does not recognize, kept verbatim.
    ///
    /// Only a file decode produces it; authoring input with an unknown `type` is refused.
    /// Nothing draws it or emits code for it: it is written back exactly as read.
    ///
    /// - Parameters:
    ///   - typeName: The `type` the file wrote.
    ///   - payload: Every other key of the effect object.
    case unknown(typeName: String, payload: PenExtras)

    public struct PenBlurEffect: Friendly {
        public init(
            enabled: PenValue<Bool>? = nil,
            radius: PenValue<Double>? = nil,
            extras: PenExtras = PenExtras()
        ) {
            self.enabled = enabled
            self.radius = radius
            self.extras = extras
        }

        public var enabled: PenValue<Bool>?
        public var radius: PenValue<Double>?

        /// Keys the file wrote on this effect that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys this payload claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case enabled, radius
        }
    }

    /// A background blur effect that blurs whatever has already been drawn behind a node.
    ///
    /// The renderer captures the current framebuffer, applies a Gaussian blur
    /// with the specified ``radius``, and composites the result clipped to the
    /// node's shape, beneath the node's own fills and strokes.
    ///
    /// - Note: Only supported on bitmap-backed contexts. On non-bitmap contexts
    ///   (PDF, window), the effect gracefully no-ops and the node draws without blur.
    public struct PenBackgroundBlurEffect: Friendly {
        public init(
            enabled: PenValue<Bool>? = nil,
            radius: PenValue<Double>? = nil,
            extras: PenExtras = PenExtras()
        ) {
            self.enabled = enabled
            self.radius = radius
            self.extras = extras
        }

        public var enabled: PenValue<Bool>?
        public var radius: PenValue<Double>?

        /// Keys the file wrote on this effect that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys this payload claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case enabled, radius
        }
    }

    /// A drop shadow cast outside the node's shape, or an inner shadow cast inside it.
    ///
    /// Format 2.19 has no `spread`: Pen dropped the key, and a file older than 2.19 loses
    /// it on the way in, with a diagnostic (see ``PenShadowMigrationRule``). Pen 1.2.14 is
    /// the first Pen to draw ``ShadowType/inner`` as an inner shadow; every earlier one
    /// drew it outside, which is why the same rule turns a pre-2.19 inner shadow into an
    /// outer one.
    public struct PenShadowEffect: Friendly {
        /// Creates a shadow; every key is optional, as in the file.
        public init(
            enabled: PenValue<Bool>? = nil,
            shadowType: PenEffect.PenShadowEffect.ShadowType? = nil,
            offset: PenEffect.PenOffset? = nil,
            blur: PenValue<Double>? = nil,
            color: PenValue<String>? = nil,
            blendMode: PenBlendMode? = nil,
            extras: PenExtras = PenExtras()
        ) {
            self.enabled = enabled
            self.shadowType = shadowType
            self.offset = offset
            self.blur = blur
            self.color = color
            self.blendMode = blendMode
            self.extras = extras
        }

        /// Whether the shadow is drawn. Absent means it is.
        public var enabled: PenValue<Bool>?
        /// Outside or inside the shape. Absent means outside.
        public var shadowType: ShadowType?
        /// How far the shadow is displaced from the shape, in points.
        public var offset: PenOffset?
        /// The blur radius, in points; the Gaussian's sigma is half of it.
        public var blur: PenValue<Double>?
        /// The shadow's color.
        public var color: PenValue<String>?
        /// How the shadow composites with what is below it.
        public var blendMode: PenBlendMode?

        /// Keys the file wrote on this shadow that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys this payload claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case enabled, shadowType, offset, blur, color, blendMode
        }

        /// Which side of the shape a shadow is cast on.
        public enum ShadowType: String, Friendly, CaseIterable {
            /// Inside the shape, from its edge inward.
            case inner
            /// Outside the shape: a drop shadow.
            case outer
        }
    }

    /// How far a shadow is displaced from its shape, in points.
    public struct PenOffset: Friendly {
        /// Creates an offset.
        ///
        /// - Parameters:
        ///   - x: The horizontal displacement.
        ///   - y: The vertical displacement.
        ///   - extras: Keys a file wrote on the object that the model does not claim.
        public init(x: PenValue<Double>, y: PenValue<Double>, extras: PenExtras = PenExtras()) {
            self.x = x
            self.y = y
            self.extras = extras
        }

        public var x: PenValue<Double>
        public var y: PenValue<Double>

        /// Keys the file wrote on this offset that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys an offset claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case x, y
        }
    }
}

// MARK: - Vocabulary

public extension PenEffect {
    /// Every spelling the `type` key of an effect object accepts, in the .pen file's words.
    ///
    /// Read off the decoder's own enumeration, so help text and error messages built
    /// from this cannot name a spelling the decoder refuses, or miss one it takes.
    static var effectTypeNames: [String] {
        EffectType.allCases.map(\.rawValue)
    }
}

/// One or more effects. The .pen format accepts a single effect or an array.
public enum PenEffects: Friendly {
    case single(PenEffect)
    case multiple([PenEffect])

    public var all: [PenEffect] {
        switch self {
        case let .single(effect): [effect]
        case let .multiple(effects): effects
        }
    }

    /// Decodes one effect or an array of them.
    ///
    /// The array is tried by *shape* rather than by success, so a misspelled `type`
    /// inside element 0 is reported as exactly that rather than being discarded in
    /// favor of "this is not an object" from the single-effect decode.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: The `DecodingError` the effect, or the element of the array, raised.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if (try? container.decode([AnyCodable].self)) != nil {
            self = try .multiple(container.decode([PenEffect].self))
        } else {
            self = try .single(container.decode(PenEffect.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .single(effect):
            try container.encode(effect)
        case let .multiple(effects):
            try container.encode(effects)
        }
    }
}
