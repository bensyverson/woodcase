//
//  PenDocument+Codable.swift
//  Woodcase
//

import Foundation

/// The document root's wire form: the modeled keys, plus every other root key a file
/// wrote, kept in ``PenDocument/extras``.
public extension PenDocument {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, themes, imports, variables, fileToken, fonts, children
    }

    /// Every root key the model claims.
    internal static let claimedKeys: Set<String> = Set(CodingKeys.allCases.map(\.stringValue))

    /// Decodes a document root.
    ///
    /// - Parameter decoder: The decoder to read from. In ``PenDecodingMode/file`` an
    ///   unclaimed root key is kept in ``extras``; in ``PenDecodingMode/authoring`` it is
    ///   refused.
    /// - Throws: `DecodingError` if a modeled key has the wrong shape, or an unclaimed
    ///   key is refused.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        themes = try container.decodeIfPresent([String: [String]].self, forKey: .themes)
        imports = try container.decodeIfPresent([String: String].self, forKey: .imports)
        variables = try container.decodeIfPresent([String: PenVariable].self, forKey: .variables)
        fileToken = try container.decodeIfPresent(String.self, forKey: .fileToken)
        fonts = try container.decodeIfPresent([PenFontDeclaration].self, forKey: .fonts)
        children = try container.decode([PenNode].self, forKey: .children)
        extras = try PenExtras.capture(from: decoder, claiming: Self.claimedKeys, describing: "the document root")
    }

    /// Encodes the document root, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(themes, forKey: .themes)
        try container.encodeIfPresent(imports, forKey: .imports)
        try container.encodeIfPresent(variables, forKey: .variables)
        try container.encodeIfPresent(fileToken, forKey: .fileToken)
        try container.encodeIfPresent(fonts, forKey: .fonts)
        try container.encode(children, forKey: .children)
    }
}
