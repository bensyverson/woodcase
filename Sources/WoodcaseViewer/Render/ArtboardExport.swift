//
//  ArtboardExport.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One artboard as a downloadable file: the bytes, what they are, and what to call them.
///
/// Every format here is one the CLI already writes — PNG and PDF from `render` and
/// `shot`, the rest from `generate react` — rendered on demand through the same
/// ``RenderCache`` the page's own image comes from, so an export at 2× and a render at
/// 2× are the same pixels.
public struct ArtboardExport: Sendable {
    /// Creates an export.
    ///
    /// - Parameters:
    ///   - data: The file's bytes.
    ///   - mediaType: Its content type.
    ///   - filename: What the browser should save it as.
    public init(data: Data, mediaType: String, filename: String) {
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
    }

    /// The file's bytes.
    public let data: Data

    /// Its content type.
    public let mediaType: String

    /// What the browser should save it as.
    public let filename: String

    /// How to size a raster export.
    ///
    /// Two ways of saying the same thing, because two different questions get asked: an
    /// agent wants *twice the design*, and a person pasting into a document wants *no
    /// wider than this*. A maximum edge decides when both are given — it is the more
    /// specific request, and the picker disables the scale when one is typed.
    public enum Size: Friendly {
        /// Pixels per layout point.
        case scale(Double)
        /// A cap on the longer side, in layout points.
        case maximumEdge(Int)

        /// The scale this size settles on for an artboard.
        ///
        /// - Parameter artboard: The artboard being exported.
        /// - Returns: Pixels per layout point.
        public func scale(for artboard: Artboard) -> Double {
            switch self {
            case let .scale(scale):
                scale
            case let .maximumEdge(edge):
                artboard.longestSide > 0 ? Double(edge) / artboard.longestSide : 1
            }
        }

        /// The `@2x` marker a filename carries, empty at 1×.
        ///
        /// - Parameter artboard: The artboard being exported.
        /// - Returns: The suffix, or an empty string.
        public func suffix(for artboard: Artboard) -> String {
            let scale = scale(for: artboard)
            guard scale != 1 else { return "" }
            return scale == scale.rounded()
                ? "@\(Int(scale))x"
                : "@\(String(format: "%.2f", scale))x"
        }
    }

    /// The name a downloaded file gets: the .pen file, the artboard, and the size.
    ///
    /// An artboard id can contain a slash — a top-level instance expands to
    /// `YGJ0d/nSNTs` — and a filename cannot, so every separator becomes a dash.
    ///
    /// - Parameters:
    ///   - file: The .pen file's name, without its extension.
    ///   - artboard: The artboard being exported.
    ///   - suffix: The size marker, `@2x` or empty.
    ///   - extension: The file extension, without its dot.
    /// - Returns: The filename.
    public static func filename(
        file: String,
        artboard: Artboard,
        suffix: String,
        extension fileExtension: String
    ) -> String {
        let name = (artboard.name ?? artboard.id)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return "\(file)-\(name)\(suffix).\(fileExtension)"
    }
}
