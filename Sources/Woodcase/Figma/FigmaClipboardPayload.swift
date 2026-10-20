//
//  FigmaClipboardPayload.swift
//  Woodcase
//

import Foundation

/// The two sections of the HTML Figma writes to the clipboard, extracted and
/// base64-decoded but not yet interpreted.
///
/// Figma puts each section in a `<span>` attribute, wrapped in an HTML comment:
///
/// ```html
/// <span data-metadata="<!--(figmeta)BASE64(/figmeta)-->"></span>
/// <span data-buffer="<!--(figma)BASE64(/figma)-->"></span>
/// ```
///
/// The desktop app and Chromium browsers write the attribute values raw; Safari
/// re-serializes the fragment, so its values arrive entity-escaped
/// (`&lt;!--(figmeta)…(/figmeta)--&gt;`) beside inline `style` attributes. The reader
/// finds each attribute, decodes its character references, then takes the base64 between
/// the markers, so every one of those wrappers reads the same.
public struct FigmaClipboardPayload: Friendly {
    /// The `(figmeta)` section's decoded bytes: JSON.
    public var metadataJSON: Data
    /// ``metadataJSON``, decoded.
    public var metadata: FigmaClipboardMetadata
    /// The `(figma)` section's decoded bytes: a ``FigKiwiContainer``.
    public var buffer: Data

    /// Creates a payload from its parts.
    public init(metadataJSON: Data, metadata: FigmaClipboardMetadata, buffer: Data) {
        self.metadataJSON = metadataJSON
        self.metadata = metadata
        self.buffer = buffer
    }

    /// Extracts the payload from the clipboard's HTML, as UTF-8 bytes.
    ///
    /// - Throws: ``FigmaDecodeError/missingSection(_:)`` when an attribute or its markers
    ///   are absent, ``FigmaDecodeError/invalidBase64(_:)`` when the text between the
    ///   markers is not base64, and ``FigmaDecodeError/invalidMetadata`` when the metadata
    ///   is not a JSON object of the expected shape.
    public init(html: Data) throws(FigmaDecodeError) {
        let bytes = [UInt8](html)
        let metadataJSON = try Self.section(.metadata, in: bytes)
        let buffer = try Self.section(.buffer, in: bytes)
        let metadata: FigmaClipboardMetadata
        do {
            metadata = try JSONDecoder().decode(FigmaClipboardMetadata.self, from: metadataJSON)
        } catch { throw .invalidMetadata }
        self.init(metadataJSON: metadataJSON, metadata: metadata, buffer: buffer)
    }
}
