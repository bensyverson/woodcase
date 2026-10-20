//
//  FigmaClipboard.swift
//  Woodcase
//

import Foundation

/// A decoded Figma clipboard payload: its metadata, its container, and the schema and
/// message its two chunks hold.
///
/// ``FigmaClipboardDecoder`` makes one. The message is generic Kiwi; mapping it to Figma
/// nodes is a separate step.
public struct FigmaClipboard: Friendly {
    /// The `(figmeta)` metadata.
    public var metadata: FigmaClipboardMetadata
    /// The fig-kiwi container: its prelude, version and compressed chunks.
    public var container: FigKiwiContainer
    /// The schema chunk, inflated: a binary Kiwi schema.
    public var schemaData: Data
    /// The message chunk, zstd-decoded: a Kiwi message in ``schema``.
    public var messageData: Data
    /// The embedded schema, decoded.
    public var schema: KiwiSchema
    /// The message, decoded as the schema's ``FigmaClipboardDecoder/rootType``.
    public var message: KiwiRecord

    /// Creates a decoded payload from its parts.
    public init(
        metadata: FigmaClipboardMetadata,
        container: FigKiwiContainer,
        schemaData: Data,
        messageData: Data,
        schema: KiwiSchema,
        message: KiwiRecord
    ) {
        self.metadata = metadata
        self.container = container
        self.schemaData = schemaData
        self.messageData = messageData
        self.schema = schema
        self.message = message
    }
}
