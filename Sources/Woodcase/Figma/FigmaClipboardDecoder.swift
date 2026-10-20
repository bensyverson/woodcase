//
//  FigmaClipboardDecoder.swift
//  Woodcase
//

import Foundation

/// Decodes a Figma clipboard payload, from its HTML to its Kiwi schema and message.
///
/// The steps: extract the two sections (``FigmaClipboardPayload``), frame the binary
/// (``FigKiwiContainer``), inflate chunk 0 with ``DeflateDecoder`` and decode it as a
/// binary ``KiwiSchema``, zstd-decode chunk 1 with ``ZstdDecoder`` and decode it as the
/// schema's ``rootType``. Pure: bytes in, values out, on every platform Woodcase builds for.
///
/// Each decompressor has a cap, so a hostile payload costs at most the cap in memory, and
/// every step's failure is a ``FigmaDecodeError`` naming the step.
///
/// ```swift
/// let clipboard = try FigmaClipboardDecoder().decode(html: html)
/// clipboard.message.typeName // "Message"
/// ```
public struct FigmaClipboardDecoder: Friendly {
    /// The default cap on the inflated schema: 16 MiB. Every capture so far carries a
    /// 76,411-byte schema.
    public static let defaultMaxSchemaSize = 16 << 20

    /// The default cap on the decompressed message: 256 MiB.
    public static let defaultMaxMessageSize = 256 << 20

    /// The definition a clipboard message decodes as. Kiwi records no root type; Figma's
    /// clipboard message is its schema's `Message`.
    public static let rootType = "Message"

    /// The most bytes the schema chunk may inflate to.
    public var maxSchemaSize: Int
    /// The most bytes the message chunk may decompress to.
    public var maxMessageSize: Int

    /// Creates a decoder with the given caps.
    ///
    /// - Precondition: neither cap is negative.
    public init(
        maxSchemaSize: Int = FigmaClipboardDecoder.defaultMaxSchemaSize,
        maxMessageSize: Int = FigmaClipboardDecoder.defaultMaxMessageSize
    ) {
        precondition(maxSchemaSize >= 0 && maxMessageSize >= 0, "FigmaClipboardDecoder's caps cannot be negative")
        self.maxSchemaSize = maxSchemaSize
        self.maxMessageSize = maxMessageSize
    }

    /// Decodes the clipboard's HTML, as UTF-8 bytes.
    ///
    /// - Throws: ``FigmaDecodeError`` from whichever step refused the payload.
    public func decode(html: Data) throws(FigmaDecodeError) -> FigmaClipboard {
        try decode(FigmaClipboardPayload(html: html))
    }

    /// Decodes an extracted payload's binary.
    ///
    /// Chunks after the second are ignored; no capture has had one.
    ///
    /// - Throws: ``FigmaDecodeError`` from whichever step refused the payload.
    public func decode(_ payload: FigmaClipboardPayload) throws(FigmaDecodeError) -> FigmaClipboard {
        let container = try FigKiwiContainer(payload.buffer)
        guard container.chunks.count >= 2 else { throw .missingChunks(found: container.chunks.count) }
        let schemaData: Data
        do {
            schemaData = try DeflateDecoder(maxDecodedSize: maxSchemaSize).decode(container.chunks[0])
        } catch { throw .schemaDecompression(error) }
        let messageData: Data
        do {
            messageData = try ZstdDecoder(maxDecodedSize: maxMessageSize).decode(container.chunks[1])
        } catch { throw .messageDecompression(error) }
        let schema: KiwiSchema
        do {
            schema = try KiwiSchema(binary: schemaData)
        } catch { throw .schemaDecoding(error) }
        let message: KiwiRecord
        do {
            message = try schema.decode(messageData, as: Self.rootType)
        } catch { throw .messageDecoding(error) }
        return FigmaClipboard(
            metadata: payload.metadata,
            container: container,
            schemaData: schemaData,
            messageData: messageData,
            schema: schema,
            message: message
        )
    }
}
