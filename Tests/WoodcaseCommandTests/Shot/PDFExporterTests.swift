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
