import CoreGraphics
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

struct PDFExporterTests {
    @Test("Writes a single-page PDF that is a valid PDF file")
    func writesSinglePagePDF() throws {
        let page = PDFExporter.Page(
            width: 100,
            height: 200,
            render: { context in
                context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            }
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try PDFExporter.writePDF(pages: [page], to: outputURL)

        let data = try Data(contentsOf: outputURL)
        // PDF files start with %PDF
        let header = String(data: data.prefix(4), encoding: .ascii)
        #expect(header == "%PDF")
    }

    @Test("Multi-page PDF has correct page count")
    func multiPagePDF() throws {
        let pages = (0 ..< 3).map { _ in
            PDFExporter.Page(width: 100, height: 100, render: { _ in })
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try PDFExporter.writePDF(pages: pages, to: outputURL)

        let data = try Data(contentsOf: outputURL)
        let provider = CGDataProvider(data: data as CFData)!
        let pdf = try #require(CGPDFDocument(provider))
        #expect(pdf.numberOfPages == 3)
    }

    @Test("Each page's media box is that page's own size")
    func mediaBoxMatchesEachPage() throws {
        let pages = [
            PDFExporter.Page(width: 1920, height: 1080, render: { _ in }),
            PDFExporter.Page(width: 402, height: 874, render: { _ in }),
        ]

        let pdf = try Self.document(PDFExporter.data(pages: pages))

        #expect(pdf.page(at: 1)?.getBoxRect(.mediaBox) == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(pdf.page(at: 2)?.getBoxRect(.mediaBox) == CGRect(x: 0, y: 0, width: 402, height: 874))
    }

    @Test("The page tree's default media box is the first page's, never zero")
    func pageTreeDefaultIsNotZero() throws {
        let pages = [
            PDFExporter.Page(width: 612, height: 792, render: { _ in }),
            PDFExporter.Page(width: 402, height: 874, render: { _ in }),
        ]

        let data = try PDFExporter.data(pages: pages)

        // Readers that trust the inherited default instead of the page's own box
        // would see a zero page.
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("/MediaBox [0 0 0 0]"))
        #expect(text.contains("/MediaBox [0 0 612 792]"))
    }

    @Test("A frame's page draws that frame, wherever it sits on the canvas")
    func framePageDrawsAtTheOrigin() throws {
        let document = try PenParser.parse("""
        {"version": "2.17", "children": [
          {"type": "frame", "id": "first", "x": 0, "y": 0, "width": 100, "height": 50, "fill": "#0000FF"},
          {"type": "frame", "id": "second", "x": 500, "y": 300, "width": 100, "height": 50, "fill": "#FF0000"}
        ]}
        """)
        let rects = PenLayoutEngine.layout(document)
        let page = try #require(PDFExporter.Page(frame: "second", of: document, layoutRects: rects))

        let pdf = try Self.document(PDFExporter.data(pages: [page]))
        let pdfPage = try #require(pdf.page(at: 1))
        #expect(pdfPage.getBoxRect(.mediaBox) == CGRect(x: 0, y: 0, width: 100, height: 50))

        let bitmap = try #require(CGContext(
            data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        bitmap.drawPDFPage(pdfPage)
        let bytes = try #require(bitmap.data).assumingMemoryBound(to: UInt8.self)
        let center = 25 * 400 + 50 * 4
        #expect(bytes[center] == 255, "red channel")
        #expect(bytes[center + 3] == 255, "the page is painted, not transparent")
    }

    @Test("A frame that has no layout rect has no page")
    func framePageNeedsARect() throws {
        let document = try PenParser.parse(#"{"version": "2.17", "children": []}"#)
        #expect(PDFExporter.Page(frame: "missing", of: document, layoutRects: [:]) == nil)
    }

    private static func document(_ data: Data) throws -> CGPDFDocument {
        let provider = try #require(CGDataProvider(data: data as CFData))
        return try #require(CGPDFDocument(provider))
    }

    @Test("Creates intermediate directories")
    func createsDirectories() throws {
        let page = PDFExporter.Page(width: 50, height: 50, render: { _ in })
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodcase-pdf-test-\(UUID().uuidString)")
            .appendingPathComponent("nested")
            .appendingPathComponent("output.pdf")
        defer {
            try? FileManager.default.removeItem(
                at: outputURL.deletingLastPathComponent().deletingLastPathComponent()
            )
        }

        try PDFExporter.writePDF(pages: [page], to: outputURL)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }
}
