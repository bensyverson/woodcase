//
//  GoogleFontMetadata.swift
//  Woodcase
//

import Foundation

/// Parsed representation of a Google Fonts `METADATA.pb` file.
///
/// Only extracts the fields needed for font resolution: the family name, its license,
/// font entries (filename, weight, style), and whether the font is variable. Which entry
/// serves a face is ``entry(weight:style:)``.
public struct GoogleFontMetadata: Friendly {
    /// The display name of the font family (e.g. "Manrope").
    public let name: String

    /// The font file entries declared in the metadata.
    public let fonts: [FontEntry]

    /// The license the family ships under, as the metadata spells it (`"OFL"`,
    /// `"APACHE2"`, `"UFL"`), or `nil` when it names none.
    public let license: String?

    /// The google/fonts directory the family's files live under (`ofl`, `apache`,
    /// `ufl`), read from ``license``; `nil` when the license names none of them.
    public var licenseDirectory: String? {
        switch license?.uppercased() {
        case "OFL": "ofl"
        case "APACHE2": "apache"
        case "UFL": "ufl"
        default: nil
        }
    }

    /// A single font file entry from the metadata.
    public struct FontEntry: Friendly {
        /// The TTF filename (e.g. "Manrope[wght].ttf" or "Lato-Bold.ttf").
        public let filename: String

        /// The CSS weight value (e.g. 400, 700).
        public let weight: Int

        /// The style: "normal" or "italic".
        public let style: String
    }

    /// Whether this font family uses a variable font file.
    ///
    /// Detected by checking if any filename contains square brackets
    /// (e.g. `"Manrope[wght].ttf"`), which indicates variable font axes.
    public var isVariable: Bool {
        fonts.contains { $0.filename.contains("[") }
    }

    // MARK: - Parsing

    /// Parses a `METADATA.pb` protobuf text format file into a ``GoogleFontMetadata``.
    ///
    /// This is a lightweight line-by-line parser that extracts only the fields
    /// needed for font resolution. It handles the protobuf text format used by
    /// the [google/fonts](https://github.com/google/fonts) repository.
    ///
    /// - Parameter data: The raw bytes of the METADATA.pb file.
    /// - Returns: The parsed metadata.
    /// - Throws: ``GoogleFontError/metadataParseError(_:)`` if the data cannot be parsed.
    public static func parse(_ data: Data) throws -> GoogleFontMetadata {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw GoogleFontError.metadataParseError("Empty or invalid UTF-8 data")
        }

        var familyName: String?
        var license: String?
        var fontEntries: [FontEntry] = []

        // State for parsing inside a `fonts { ... }` block
        var inFontsBlock = false
        var currentFilename: String?
        var currentWeight: Int?
        var currentStyle: String?

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inFontsBlock {
                if trimmed == "}" {
                    // End of fonts block — emit entry if we have the required fields
                    if let filename = currentFilename,
                       let weight = currentWeight,
                       let style = currentStyle
                    {
                        fontEntries.append(FontEntry(
                            filename: filename,
                            weight: weight,
                            style: style
                        ))
                    }
                    inFontsBlock = false
                    currentFilename = nil
                    currentWeight = nil
                    currentStyle = nil
                } else if let value = extractQuotedValue(from: trimmed, key: "filename") {
                    currentFilename = value
                } else if let value = extractIntValue(from: trimmed, key: "weight") {
                    currentWeight = value
                } else if let value = extractQuotedValue(from: trimmed, key: "style") {
                    currentStyle = value
                }
            } else if trimmed.hasPrefix("fonts"), trimmed.hasSuffix("{") {
                inFontsBlock = true
            } else if familyName == nil, let value = extractQuotedValue(from: trimmed, key: "name") {
                familyName = value
            } else if license == nil, let value = extractQuotedValue(from: trimmed, key: "license") {
                license = value
            }
        }

        guard let name = familyName else {
            throw GoogleFontError.metadataParseError("Missing font family name")
        }

        return GoogleFontMetadata(name: name, fonts: fontEntries, license: license)
    }

    // MARK: - Private Helpers

    /// Extracts a quoted string value for a given key from a line like `key: "value"`.
    private static func extractQuotedValue(from line: String, key: String) -> String? {
        guard line.hasPrefix("\(key):") else { return nil }
        let afterColon = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        guard afterColon.hasPrefix("\""), afterColon.hasSuffix("\""), afterColon.count >= 2 else {
            return nil
        }
        return String(afterColon.dropFirst().dropLast())
    }

    /// Extracts an integer value for a given key from a line like `weight: 400`.
    private static func extractIntValue(from line: String, key: String) -> Int? {
        guard line.hasPrefix("\(key):") else { return nil }
        let afterColon = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        return Int(afterColon)
    }
}
