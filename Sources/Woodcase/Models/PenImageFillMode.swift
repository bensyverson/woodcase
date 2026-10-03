//
//  PenImageFillMode.swift
//  Woodcase
//

import Foundation

/// How an image paint is sized into its node: the .pen `mode` key of an image fill.
///
/// Format 2.20 spells the modes `cover`, `contain` and `stretch`. Reading a file is lenient in
/// every version: 2.19's `fill` and `fit` read as ``cover`` and ``contain`` and re-encode in
/// their 2.20 spelling, and any other string is kept as ``unknown(_:)``, written back unchanged
/// and placed as ``cover``, the 2.20 default, so a mode never fails to read. An agent's write
/// (``PenDecodingMode/authoring``) still takes `fill` and `fit`, but refuses any other string
/// with the three modes it could have written.
///
/// What a paint actually draws with is ``placement`` — or, with a missing mode taken into
/// account, ``PenFill/PenImageFill/placement``.
public enum PenImageFillMode: Friendly, CaseIterable {
    /// Fills the node's bounds exactly, ignoring the image's aspect ratio.
    case stretch
    /// Scales the image uniformly to cover the node's bounds, centered; 2.19 wrote `fill`.
    case cover
    /// Scales the image uniformly to fit inside the node's bounds, centered; 2.19 wrote `fit`.
    case contain
    /// A spelling this build does not know, kept as written.
    case unknown(String)

    /// The three modes the format defines; ``unknown(_:)`` is not one of them.
    public static let allCases: [PenImageFillMode] = [.stretch, .cover, .contain]

    /// The mode as the file writes it: the 2.20 spelling, or an unknown value as it was read.
    public var rawString: String {
        switch self {
        case .stretch: "stretch"
        case .cover: "cover"
        case .contain: "contain"
        case let .unknown(value): value
        }
    }

    /// Reads a written mode, accepting 2.19's `fill` and `fit` and keeping any other string.
    ///
    /// - Parameter rawString: The `mode` value as the file writes it.
    public init(rawString: String) {
        switch rawString {
        case "stretch": self = .stretch
        case "cover", "fill": self = .cover
        case "contain", "fit": self = .contain
        default: self = .unknown(rawString)
        }
    }

    /// How an image with this mode is placed: an unknown mode is placed as ``Placement/cover``.
    public var placement: Placement {
        switch self {
        case .stretch: .stretch
        case .cover, .unknown: .cover
        case .contain: .contain
        }
    }

    /// The placement a renderer draws with: the three modes and nothing else, so a switch
    /// over it needs no arm for a spelling the build does not know.
    public enum Placement: String, Friendly, CaseIterable {
        /// Fills the node's bounds exactly, ignoring the image's aspect ratio.
        case stretch
        /// Scales uniformly to cover the node's bounds, centered, overflowing on one axis.
        case cover
        /// Scales uniformly to fit inside the node's bounds, centered, leaving bands on one axis.
        case contain
    }
}

// MARK: - Codable

public extension PenImageFillMode {
    /// Decodes a mode from its string; see ``init(rawString:)``.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` when the value is not a string, or, in
    ///   ``PenDecodingMode/authoring``, a spelling this build does not know.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.init(rawString: raw)
        if case .unknown = self, PenDecodingMode.of(decoder) == .authoring {
            let modes = Self.allCases.map { "\"\($0.rawString)\"" }.joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "\"\(raw)\" is not an accepted spelling; an image mode is one of \(modes)"
            )
        }
    }

    /// Encodes the mode as ``rawString``.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawString)
    }
}
