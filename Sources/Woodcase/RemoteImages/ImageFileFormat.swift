//
//  ImageFileFormat.swift
//  Woodcase
//

import Foundation

/// A raster image file format, as its leading bytes name it.
///
/// For naming a downloaded file whose URL says nothing of its type: a signed Figma image
/// URL, or a remote image fill without an extension.
public enum ImageFileFormat: String, Friendly, CaseIterable {
    /// PNG.
    case png
    /// JPEG.
    case jpeg
    /// GIF.
    case gif
    /// WebP.
    case webp

    /// The format whose signature `data` starts with, or `nil` when it is none of these.
    ///
    /// - Parameter data: The file's bytes; only the first twelve are read.
    public init?(sniffing data: Data) {
        let head = [UInt8](data.prefix(12))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            self = .png
        } else if head.starts(with: [0xFF, 0xD8, 0xFF]) {
            self = .jpeg
        } else if head.starts(with: Array("GIF8".utf8)) {
            self = .gif
        } else if head.count == 12, head.starts(with: Array("RIFF".utf8)), head[8 ..< 12].elementsEqual("WEBP".utf8) {
            // RIFF is a container; WAV and AVI start the same way, and only bytes 8–11 say WebP.
            self = .webp
        } else {
            return nil
        }
    }

    /// The usual file extension, without its dot.
    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .gif: "gif"
        case .webp: "webp"
        }
    }
}
