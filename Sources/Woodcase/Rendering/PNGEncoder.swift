//
//  PNGEncoder.swift
//  Woodcase
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a rendered `CGImage` into PNG bytes, or a PNG file.
///
/// The last step of the render pipeline — `Parse → Resolve → Expand → Layout → Render
/// → **Encode**` — and the one every consumer needs: `woodcase render` and `shot` write
/// a file, the viewer serves the bytes over HTTP without ever touching the disk. Both
/// go through here so there is one PNG writer, not one per caller.
///
/// ```swift
/// let image = PenRenderer.render(document, layoutRects: rects, size: size)!
/// let bytes = try PNGEncoder.encode(image)      // for a response body
/// try PNGEncoder.write(image, to: outputURL)    // for a file
/// ```
public enum PNGEncoder {
    /// Why a PNG could not be produced.
    ///
    /// Each case names the file — or says that there was none — so a caller can print
    /// the failure without holding onto the URL itself.
    public enum EncodingError: Error, CustomStringConvertible, Equatable, Sendable {
        /// ImageIO would not open a destination at this URL, usually because its
        /// parent directory could not be created.
        case destinationUnavailable(URL)
        /// ImageIO accepted the image but failed to finish writing this file.
        case finalizeFailed(URL)
        /// ImageIO failed to encode the image into memory.
        case encodingFailed

        public var description: String {
            switch self {
            case let .destinationUnavailable(url):
                "Cannot write a PNG at \(url.path): the destination could not be created."
            case let .finalizeFailed(url):
                "Failed to finish writing the PNG at \(url.path)."
            case .encodingFailed:
                "Failed to encode the image as PNG."
            }
        }
    }

    /// Encodes an image as PNG bytes.
    ///
    /// - Parameter image: The image to encode.
    /// - Returns: The PNG file's bytes, ready to write or to serve.
    /// - Throws: ``EncodingError/encodingFailed`` if ImageIO refuses the image.
    public static func encode(_ image: CGImage) throws -> Data {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw EncodingError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw EncodingError.encodingFailed
        }
        return buffer as Data
    }

    /// Writes an image as a PNG file, creating intermediate directories.
    ///
    /// - Parameters:
    ///   - image: The image to write.
    ///   - url: Where to write it.
    /// - Throws: ``EncodingError`` naming `url`, or whatever `FileManager` throws while
    ///   creating the enclosing directory.
    public static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw EncodingError.destinationUnavailable(url)
        }
        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw EncodingError.finalizeFailed(url)
        }
    }
}
