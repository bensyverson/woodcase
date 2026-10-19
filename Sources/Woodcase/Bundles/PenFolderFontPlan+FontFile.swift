//
//  PenFolderFontPlan+FontFile.swift
//  Woodcase
//

import Foundation

public extension PenFolderFontPlan {
    /// One font file a row would ship, with what it says about itself.
    struct FontFile: Friendly {
        /// The file.
        public var url: URL

        /// The family name inside the file — what its declaration must say, because
        /// Woodcase draws a declared file only under its real family name.
        public var familyName: String

        /// The style its declaration covers.
        public var style: PenFontDeclaration.Style

        /// The weight its declaration covers: its `wght` axis's range for a variable
        /// file, its weight for a static one.
        public var weight: PenFontDeclaration.Weight

        /// Its `fsType`, or `nil` when the file has none that could be read.
        public var embedding: PenFontEmbedding?

        /// The license it carries in its name table, or `nil` when it carries none.
        public var license: License?

        /// A file.
        ///
        /// - Parameters:
        ///   - url: The file.
        ///   - familyName: The family name inside it.
        ///   - style: The style it covers.
        ///   - weight: The weight or weights it covers.
        ///   - embedding: Its `fsType`, or `nil`.
        ///   - license: Its license, or `nil`.
        public init(
            url: URL,
            familyName: String,
            style: PenFontDeclaration.Style,
            weight: PenFontDeclaration.Weight,
            embedding: PenFontEmbedding?,
            license: License?
        ) {
            self.url = url
            self.familyName = familyName
            self.style = style
            self.weight = weight
            self.embedding = embedding
            self.license = license
        }
    }

    /// A font's own license, from its OpenType name table.
    struct License: Friendly {
        /// The License Description (name ID 13), or `nil`.
        public var description: String?

        /// The License Info URL (name ID 14), or `nil` when absent or not a URL.
        public var url: URL?

        /// A license.
        ///
        /// - Parameters:
        ///   - description: The description text, or `nil`.
        ///   - url: The license URL, or `nil`.
        public init(description: String?, url: URL?) {
            self.description = description
            self.url = url
        }
    }
}
