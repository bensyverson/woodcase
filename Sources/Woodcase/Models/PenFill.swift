//
//  PenFill.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// A fill applied to a .pen node.
///
/// The .pen format supports several fill types:
/// - **Shorthand:** A bare color string (`"#FF0000"`) or variable (`"$primary"`)
/// - **Color:** An object with `type: "color"` and explicit color/blendMode/enabled
/// - **Gradient:** Linear, radial, or angular gradient with color stops
/// - **Image:** An image fill referencing a file URL
/// - **Mesh gradient:** A grid of colored vertices joined by Bézier patches (see ``PenMeshGradientFill``
///   and ``PenMeshPoint``); rasterized by the mesh core, and baked to a PNG by the React emitter
/// - **Shader:** A GPU fragment shader effect (unsupported in renderer, preserved in model; see ``PenShaderFill``)
public enum PenFill: Friendly {
    case shorthand(String)
    case color(PenColorFill)
    case gradient(PenGradientFill)
    case image(PenImageFill)
    case meshGradient(PenMeshGradientFill)
    case shader(PenShaderFill)

    /// A fill whose `type` this build does not recognize, kept verbatim.
    ///
    /// Only a file decode produces it; authoring input with an unknown `type` is refused.
    /// The renderer paints nothing for it and the React emitter emits nothing: it is
    /// written back exactly as read.
    ///
    /// - Parameters:
    ///   - typeName: The `type` the file wrote.
    ///   - payload: Every other key of the fill object.
    case unknown(typeName: String, payload: PenExtras)

    public struct PenColorFill: Friendly {
        public init(
            enabled: PenValue<Bool>? = nil,
            blendMode: PenBlendMode? = nil,
            color: PenValue<String>,
            extras: PenExtras = PenExtras()
        ) {
            self.enabled = enabled
            self.blendMode = blendMode
            self.color = color
            self.extras = extras
        }

        public var enabled: PenValue<Bool>?
        public var blendMode: PenBlendMode?
        public var color: PenValue<String>

        /// Keys the file wrote on this fill that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys this payload claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case enabled, blendMode, color
        }
    }

    public struct PenGradientFill: Friendly {
        public init(
            enabled: PenValue<Bool>? = nil,
            blendMode: PenBlendMode? = nil,
            gradientType: PenGradientType? = nil,
            opacity: PenValue<Double>? = nil,
            center: PenFill.PenFillPosition? = nil,
            size: PenFill.PenFillSize? = nil,
            rotation: PenValue<Double>? = nil,
            colors: [PenFill.PenGradientStop]? = nil,
            extras: PenExtras = PenExtras()
        ) {
            self.enabled = enabled
            self.blendMode = blendMode
            self.gradientType = gradientType
            self.opacity = opacity
            self.center = center
            self.size = size
            self.rotation = rotation
            self.colors = colors
            self.extras = extras
        }

        public var enabled: PenValue<Bool>?
        public var blendMode: PenBlendMode?
        public var gradientType: PenGradientType?
        public var opacity: PenValue<Double>?
        public var center: PenFillPosition?
        public var size: PenFillSize?
        public var rotation: PenValue<Double>?
        public var colors: [PenGradientStop]?

        /// Keys the file wrote on this fill that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys this payload claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case enabled, blendMode, gradientType, opacity, center, size, rotation, colors
        }
    }

    /// One color stop of a gradient.
    public struct PenGradientStop: Friendly {
        /// Creates a stop.
        ///
        /// - Parameters:
        ///   - color: The stop's color.
        ///   - position: Where along the gradient it sits, from 0 to 1.
        ///   - extras: Keys a file wrote on the stop that the model does not claim.
        public init(
            color: PenValue<String>,
            position: PenValue<Double>,
            extras: PenExtras = PenExtras()
        ) {
            self.color = color
            self.position = position
            self.extras = extras
        }

        public var color: PenValue<String>
        public var position: PenValue<Double>

        /// Keys the file wrote on this stop that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys a stop claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case color, position
        }
    }

    /// A gradient's center, in the node's unit space.
    public struct PenFillPosition: Friendly {
        /// Creates a center.
        ///
        /// - Parameters:
        ///   - x: The horizontal position, as a fraction of the node's width.
        ///   - y: The vertical position, as a fraction of the node's height.
        ///   - extras: Keys a file wrote on the object that the model does not claim.
        public init(x: Double? = nil, y: Double? = nil, extras: PenExtras = PenExtras()) {
            self.x = x
            self.y = y
            self.extras = extras
        }

        public var x: Double?
        public var y: Double?

        /// Keys the file wrote on this object that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys a center claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case x, y
        }
    }

    /// A gradient's size, in the node's unit space.
    public struct PenFillSize: Friendly {
        /// Creates a size.
        ///
        /// - Parameters:
        ///   - width: The width, as a fraction of the node's width.
        ///   - height: The height, as a fraction of the node's height.
        ///   - extras: Keys a file wrote on the object that the model does not claim.
        public init(width: PenValue<Double>? = nil, height: PenValue<Double>? = nil, extras: PenExtras = PenExtras()) {
            self.width = width
            self.height = height
            self.extras = extras
        }

        public var width: PenValue<Double>?
        public var height: PenValue<Double>?

        /// Keys the file wrote on this object that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys a size claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case width, height
        }
    }

    public struct PenImageFill: Friendly {
        public init(
            enabled: PenValue<Bool>? = nil,
            blendMode: PenBlendMode? = nil,
            opacity: PenValue<Double>? = nil,
            url: String? = nil,
            mode: PenImageFillMode? = nil,
            extras: PenExtras = PenExtras()
        ) {
            self.enabled = enabled
            self.blendMode = blendMode
            self.opacity = opacity
            self.url = url
            self.mode = mode
            self.extras = extras
        }

        public var enabled: PenValue<Bool>?
        public var blendMode: PenBlendMode?
        public var opacity: PenValue<Double>?
        /// The image's URL: either a path relative to the .pen file, or an `http(s)`
        /// URL that ``RemoteImageResolver`` downloads before rendering. Absent when the
        /// fill has not had an image assigned yet.
        public var url: String?
        public var mode: PenImageFillMode?

        /// Keys the file wrote on this fill that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys this payload claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case enabled, blendMode, opacity, url, mode
        }
    }
}

// MARK: - Vocabulary

public extension PenFill {
    /// Every spelling the `type` key of a fill object accepts, in the .pen file's words.
    ///
    /// Read off the decoder's own enumeration, so an error message or a piece of
    /// help built from this can neither name a spelling the decoder refuses nor
    /// miss one it takes. `"solid"` is not among them; a solid color is
    /// `{"type":"color","color":"#FFD166"}`, or just the color string.
    static var fillTypeNames: [String] {
        FillType.allCases.map(\.rawValue)
    }
}

/// One or more fills. The .pen format accepts a single fill or an array.
public enum PenFills: Friendly {
    case single(PenFill)
    case multiple([PenFill])

    public var all: [PenFill] {
        switch self {
        case let .single(fill): [fill]
        case let .multiple(fills): fills
        }
    }

    /// Decodes one fill or an array of them.
    ///
    /// The array is tried by *shape* rather than by success: a JSON array is decoded
    /// as `[PenFill]` and any failure inside it is raised as it stands. Falling back
    /// to the single-fill decode instead — which was what happened here — throws
    /// away "element 0's type is misspelled" and reports "this is not an object",
    /// which is both useless and untrue of an accepted form.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: The `DecodingError` the fill, or the element of the array, raised.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if (try? container.decode([AnyCodable].self)) != nil {
            self = try .multiple(container.decode([PenFill].self))
        } else {
            self = try .single(container.decode(PenFill.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .single(fill):
            try container.encode(fill)
        case let .multiple(fills):
            try container.encode(fills)
        }
    }
}
