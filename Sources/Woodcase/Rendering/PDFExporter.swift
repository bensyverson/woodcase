//
//  PDFExporter.swift
//  Woodcase
//

import CoreGraphics
import Foundation

/// Draws pages into a PDF.
///
/// In the library rather than beside the `render` verb because it has two consumers:
/// `woodcase render --format pdf`, which writes a file, and the viewer's export
/// endpoint, which answers with the bytes. A second implementation on the viewer's side
/// would be a second answer to "what does a PDF of this artboard look like", and the two
/// would drift the first time one of them learned about a margin.
///
/// ```swift
/// let pages = frames.compactMap { frame in
///     PDFExporter.Page(frame: frame.id, of: document, layoutRects: rects)
/// }
/// let data = try PDFExporter.data(pages: pages)
/// ```
public enum PDFExporter {
    /// A single page to render into the PDF.
    ///
    /// The size is in points, which is what a PDF is measured in and what the layout
    /// engine already answers in — so a PDF page is the artboard at 1:1 and a scale
    /// factor means nothing here.
    public struct Page {
        /// Creates a page.
        ///
        /// - Parameters:
        ///   - width: The page's width in points.
        ///   - height: The page's height in points.
        ///   - render: What to draw into the page's context, whose origin this type has
        ///     already flipped to the top left.
        public init(width: CGFloat, height: CGFloat, render: @escaping (CGContext) -> Void) {
            self.width = width
            self.height = height
            self.render = render
        }

        /// The page's width in points.
        public let width: CGFloat
        /// The page's height in points.
        public let height: CGFloat
        /// What to draw into the page's context.
        public let render: (CGContext) -> Void
    }

    /// Something that went wrong producing a PDF.
    public enum ExportError: Error, CustomStringConvertible {
        /// CoreGraphics would not give us a PDF context.
        case failedToCreateContext(URL?)

        public var description: String {
            switch self {
            case let .failedToCreateContext(url):
                url.map { "Failed to create PDF context at \($0.path)" }
                    ?? "Failed to create an in-memory PDF context"
            }
        }
    }

    /// Renders pages into PDF bytes.
    ///
    /// - Parameter pages: The pages to draw, in order.
    /// - Returns: The document's bytes.
    /// - Throws: ``ExportError/failedToCreateContext(_:)`` when CoreGraphics refuses a
    ///   context.
    public static func data(pages: [Page]) throws -> Data {
        let buffer = NSMutableData()
        guard let consumer = CGDataConsumer(data: buffer as CFMutableData) else {
            throw ExportError.failedToCreateContext(nil)
        }

        // Each page sets its own box; this one becomes the page tree's inherited default,
        // so it must be a real page rather than zero.
        var mediaBox = pages.first.map { CGRect(x: 0, y: 0, width: $0.width, height: $0.height) } ?? .zero
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.failedToCreateContext(nil)
        }

        for page in pages {
            // The typed call: a `CGRect` bridged into a `beginPDFPage` dictionary is
            // silently ignored, leaving every page at the zero initial box.
            var pageBox = CGRect(x: 0, y: 0, width: page.width, height: page.height)
            context.beginPage(mediaBox: &pageBox)

            // Flip so the origin is top-left, matching the bitmap context the renderer
            // is written against.
            context.translateBy(x: 0, y: page.height)
            context.scaleBy(x: 1, y: -1)

            page.render(context)

            context.endPDFPage()
        }

        context.closePDF()
        return buffer as Data
    }

    /// Writes a multi-page PDF to disk, creating intermediate directories.
    ///
    /// - Parameters:
    ///   - pages: The pages to draw, in order.
    ///   - url: Where to write them.
    /// - Throws: ``ExportError/failedToCreateContext(_:)``, or whatever `FileManager`
    ///   and `Data.write(to:)` throw.
    public static func writePDF(pages: [Page], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data(pages: pages).write(to: url)
    }
}
