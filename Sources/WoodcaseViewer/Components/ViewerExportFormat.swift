//
//  ViewerExportFormat.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// What one artboard can be downloaded as — exactly what the CLI already writes, and
/// nothing more.
///
/// `render` and `shot` write PNG and PDF; `generate` writes the files
/// ``ViewerCodeTarget`` lists. A viewer that offered SVG or a Figma file would be
/// offering something no verb can produce, and the first agent to click it would find
/// out the hard way.
public enum ViewerExportFormat: Friendly, CaseIterable {
    /// A raster image, at a scale or a maximum edge.
    case png
    /// A vector document, always at the artboard's own size in points.
    case pdf
    /// One of the files `generate react` writes.
    case code(ViewerCodeTarget)

    /// Every format, images first — the order the picker lists them in.
    public static var allCases: [ViewerExportFormat] {
        [.png, .pdf] + ViewerCodeTarget.allCases.map(ViewerExportFormat.code)
    }

    /// How `?format=` spells this format.
    public var query: String {
        switch self {
        case .png: "png"
        case .pdf: "pdf"
        case let .code(target): target.rawValue
        }
    }

    /// The format a `?format=` value names.
    ///
    /// - Parameter query: The value as the query carries it.
    /// - Returns: The format, or `nil` when nothing writes that.
    public init?(query: String) {
        switch query {
        case "png": self = .png
        case "pdf": self = .pdf
        default:
            guard let target = ViewerCodeTarget(rawValue: query) else { return nil }
            self = .code(target)
        }
    }

    /// The word in the picker.
    public var label: String {
        switch self {
        case .png: "PNG image"
        case .pdf: "PDF document"
        case let .code(target): target.label
        }
    }

    /// Whether a scale or a maximum edge changes anything.
    ///
    /// Only a raster has a resolution. A PDF is drawn in points and generated code has
    /// no size at all, so the form disables the size controls rather than pretending.
    public var isScalable: Bool {
        self == .png
    }

    /// The content type the download is sent with.
    public var mediaType: String {
        switch self {
        case .png: "image/png"
        case .pdf: "application/pdf"
        case let .code(target): target.mediaType
        }
    }

    /// The code target this format names, or `nil` for an image.
    public var codeTarget: ViewerCodeTarget? {
        guard case let .code(target) = self else { return nil }
        return target
    }
}
