//
//  PenParser.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// Stateless parser for the .pen scene graph format.
///
/// `PenParser` decodes and encodes ``PenDocument`` values, dispatching on the
/// document's declared `version` on the way in:
///
/// | Declared version | Handling |
/// | --- | --- |
/// | 2.8 – 2.10 | ``PenLegacyMigrator`` rewrites the JSON tree, then the current decoder runs |
/// | below 2.8 | migrated as legacy, with a warning |
/// | 2.11 – 2.18 | ``PenLegacyMigrator/modernRules`` rewrite the tree (shadows), then the current decoder; a warning for a version never observed in the wild |
/// | 2.19 | current decoder |
/// | newer 2.x | current decoder, with a notice; the declared version is kept |
/// | any other major | read-only if it passes the structural probe, with a warning; otherwise ``PenParserError/differentMajor(url:version:reason:)`` |
/// | unparsable | ``PenParserError/unsupportedVersion(url:version:)`` |
/// | absent | migrated as legacy, with a warning |
///
/// A document older than the model reports ``PenDocument/currentFormatVersion``; one
/// newer or of another major reports the version it declared, so ``encode(_:)`` never
/// downgrades it. There is one in-memory model either way. See <doc:PenEngine>.
///
/// ```swift
/// let diagnostics = PenDiagnosticCollector()
/// let document = try PenParser.parse(jsonData, diagnostics: diagnostics)
/// let roundTripped = try PenParser.encode(document)
/// ```
public enum PenParser {
    // MARK: - Parsing

    /// Parses raw JSON data into a ``PenDocument``.
    ///
    /// - Parameters:
    ///   - data: UTF-8 encoded JSON data in the .pen format.
    ///   - diagnostics: Optional collector notified about version handling and
    ///     any data a legacy migration discards.
    /// - Returns: A fully decoded ``PenDocument``, reporting ``PenDocument/currentFormatVersion``
    ///   unless it declared a newer or a different major version.
    /// - Throws: ``PenParserError/unsupportedVersion(url:version:)`` if the declared version is
    ///   unreadable, ``PenParserError/differentMajor(url:version:reason:)`` if it is another major
    ///   that fails the structural probe, or ``PenParserError/decodingFailed(url:underlying:)`` if the JSON is invalid or
    ///   does not conform to the expected .pen structure. Neither names a file: these
    ///   are bytes, and ``PenParserError/url`` is `nil`.
    public static func parse(_ data: Data, diagnostics: PenDiagnosticCollector? = nil) throws -> PenDocument {
        try parse(data, from: nil, diagnostics: diagnostics)
    }

    /// Parses raw JSON data known to have come from a particular file.
    ///
    /// This is the one entry point that fills ``PenParserError/url`` in, so that a
    /// caller holding the bytes rather than the path — ``PenFileTransaction``, which
    /// reads them under its lock — still fails with an error naming the file.
    ///
    /// - Parameters:
    ///   - data: UTF-8 encoded JSON data in the .pen format.
    ///   - url: The file the bytes were read from, or `nil` if they came from memory.
    ///   - diagnostics: Optional collector notified about version handling and
    ///     any data a legacy migration discards.
    /// - Returns: A fully decoded ``PenDocument``.
    /// - Throws: ``PenParserError``, naming `url`.
    static func parse(
        _ data: Data,
        from url: URL?,
        diagnostics: PenDiagnosticCollector? = nil
    ) throws -> PenDocument {
        do {
            let probe: VersionProbe
            do {
                probe = try JSONDecoder().decode(VersionProbe.self, from: data)
            } catch {
                throw PenParserError.decodingFailed(url: nil, underlying: error)
            }

            switch try route(declaredVersion: probe.version, diagnostics: diagnostics) {
            case let .decodeAsIs(relation):
                var document = try decode(data)
                // Upgrading an older minor is what the model's output is; downgrading a
                // newer one is how a newer Pen's data gets migrated away behind our back.
                if relation != .newerMinor {
                    document.version = PenDocument.currentFormatVersion
                }
                return document
            case let .migrate(version):
                var document: PenDocument
                if let version, version > PenFormatVersion.newestLegacy, !PenShadowMigrationRule.mayApply(to: data) {
                    // Nothing in these bytes for a 2.11 – 2.18 rule to rewrite: skip the
                    // tree round trip, which would cost a second full decode.
                    document = try decode(data)
                } else {
                    let rules = PenLegacyMigrator.rules(upgrading: version)
                    let migrated = try PenLegacyMigrator.migrate(tree(from: data), rules: rules, diagnostics: diagnostics)
                    document = try decode(reencode(migrated))
                }
                document.version = PenDocument.currentFormatVersion
                return document
            case let .probeDifferentMajor(version):
                let document = try StructuralProbe.decode(data, declaring: version)
                warnReadOnly(version, diagnostics: diagnostics)
                return document
            }
        } catch let error as PenParserError {
            throw error.attaching(url)
        }
    }

    /// Parses a JSON string into a ``PenDocument``.
    ///
    /// - Parameters:
    ///   - string: A JSON string in the .pen format.
    ///   - diagnostics: Optional collector notified about version handling and
    ///     any data a legacy migration discards.
    /// - Returns: A fully decoded ``PenDocument``.
    /// - Throws: ``PenParserError/invalidString`` if the string cannot be converted to UTF-8,
    ///   or the errors thrown when decoding the data.
    public static func parse(_ string: String, diagnostics: PenDiagnosticCollector? = nil) throws -> PenDocument {
        guard let data = string.data(using: .utf8) else {
            throw PenParserError.invalidString
        }
        return try parse(data, diagnostics: diagnostics)
    }

    /// Parses a .pen file at the given URL into a ``PenDocument``.
    ///
    /// - Parameters:
    ///   - url: A file URL pointing to a .pen JSON file.
    ///   - diagnostics: Optional collector notified about version handling and
    ///     any data a legacy migration discards.
    /// - Returns: A fully decoded ``PenDocument``.
    /// - Throws: ``PenParserError/fileReadFailed(url:underlying:)`` if the file cannot be read,
    ///   or the errors thrown when decoding the data — every one of them naming `url`.
    public static func parse(contentsOf url: URL, diagnostics: PenDiagnosticCollector? = nil) throws -> PenDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PenParserError.fileReadFailed(url: url, underlying: error)
        }
        return try parse(data, from: url, diagnostics: diagnostics)
    }

    // MARK: - Decoding

    private static func decode(_ data: Data) throws -> PenDocument {
        do {
            return try JSONDecoder().decode(PenDocument.self, from: data)
        } catch {
            throw PenParserError.decodingFailed(url: nil, underlying: error)
        }
    }

    private static func tree(from data: Data) throws -> [String: AnyCodable] {
        do {
            return try JSONDecoder().decode([String: AnyCodable].self, from: data)
        } catch {
            throw PenParserError.decodingFailed(url: nil, underlying: error)
        }
    }

    private static func reencode(_ tree: [String: AnyCodable]) throws -> Data {
        do {
            return try JSONEncoder().encode(tree)
        } catch {
            throw PenParserError.decodingFailed(url: nil, underlying: error)
        }
    }

    // MARK: - Encoding

    /// Encodes a ``PenDocument`` to JSON data.
    ///
    /// - Parameter document: The document to encode.
    /// - Returns: UTF-8 encoded JSON data.
    public static func encode(_ document: PenDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    /// Encodes a ``PenDocument`` to a JSON string.
    ///
    /// - Parameter document: The document to encode.
    /// - Returns: A JSON string representation.
    public static func encodeToString(_ document: PenDocument) throws -> String {
        let data = try encode(document)
        return String(decoding: data, as: UTF8.self)
    }

    /// Encodes a value the way a .pen file is written on disk: sorted keys, two-space
    /// indentation, unescaped slashes in URLs, and a trailing newline.
    ///
    /// ``encode(_:)`` stays compact — it is what round-trip comparisons and the
    /// editing layer want. This is what ``PenFileMigrator`` writes, so a migrated
    /// fixture reads and diffs like the hand-written ones it replaces.
    ///
    /// A whole ``PenDocument`` is the usual argument, but anything `Encodable` is
    /// accepted so that a fragment of one — a single ``PenNode`` printed by
    /// `woodcase get`, say — comes out in the same canonical form as the file it was
    /// read from, rather than in a second, subtly different one.
    ///
    /// - Parameter value: The document, or the fragment of one, to encode.
    /// - Returns: UTF-8 encoded JSON data, ending in a newline.
    public static func encodeForFile(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let pretty = try String(decoding: encoder.encode(value), as: UTF8.self)
        return Data((tightenKeySeparators(in: pretty) + "\n").utf8)
    }

    /// Rewrites Foundation's `"key" : value` pretty-printing as the conventional
    /// `"key": value`.
    ///
    /// A line is rewritten when it opens, after its indentation, with a string followed
    /// by ` : ` — which, in pretty-printed JSON, only a key can: JSON escapes newlines
    /// inside strings, so a *value* containing `" : "` is always preceded on its line by
    /// its own key and never matches. The string ends at its first quote not escaped by a
    /// backslash.
    ///
    /// It scans bytes rather than matching a `Regex` per line: the `Regex` was about a
    /// sixth of a `woodcase set` on `woodcase-app.pen` (see <doc:WoodcasePerformance>).
    private static func tightenKeySeparators(in json: String) -> String {
        let bytes = Array(json.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var lineStart = 0
        while lineStart <= bytes.count {
            let lineEnd = bytes[lineStart...].firstIndex(of: UInt8(ascii: "\n")) ?? bytes.count
            if let keyEnd = keyEnd(in: bytes, from: lineStart, to: lineEnd) {
                output.append(contentsOf: bytes[lineStart ..< keyEnd])
                output.append(contentsOf: [UInt8(ascii: ":"), UInt8(ascii: " ")])
                output.append(contentsOf: bytes[(keyEnd + 3) ..< lineEnd])
            } else {
                output.append(contentsOf: bytes[lineStart ..< lineEnd])
            }
            if lineEnd < bytes.count { output.append(UInt8(ascii: "\n")) }
            lineStart = lineEnd + 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// Where a line's leading key string ends, when ` : ` follows it.
    ///
    /// - Parameters:
    ///   - bytes: The whole text.
    ///   - start: The line's first byte.
    ///   - end: One past its last.
    /// - Returns: The index just past the key's closing quote, or `nil` when the line
    ///   does not open with a string followed by ` : `.
    private static func keyEnd(in bytes: [UInt8], from start: Int, to end: Int) -> Int? {
        var index = start
        while index < end, bytes[index] == UInt8(ascii: " ") || (9 ... 13).contains(bytes[index]) {
            index += 1
        }
        guard index < end, bytes[index] == UInt8(ascii: "\"") else { return nil }
        index += 1
        while index < end {
            switch bytes[index] {
            case UInt8(ascii: "\\"):
                index += 2
            case UInt8(ascii: "\""):
                let separator = index + 1
                guard separator + 3 <= end,
                      bytes[separator] == UInt8(ascii: " "),
                      bytes[separator + 1] == UInt8(ascii: ":"),
                      bytes[separator + 2] == UInt8(ascii: " ")
                else { return nil }
                return separator
            default:
                index += 1
            }
        }
        return nil
    }
}
