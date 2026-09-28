import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import WoodcaseCommandCore

struct ImageExporterTests {
    /// Creates a simple 10×10 red test image.
    private func makeTestImage() -> CGImage {
        let width = 10
        let height = 10
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test("Writes a PNG file that can be read back")
    func writesPNG() throws {
        let image = makeTestImage()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try ImageExporter.writePNG(image, to: outputURL)

        let data = try Data(contentsOf: outputURL)
        #expect(data.count > 0)

        // Verify it's a valid PNG by reading it back
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        #expect(source != nil)
        let readBack = try CGImageSourceCreateImageAtIndex(#require(source), 0, nil)
        #expect(readBack != nil)
        #expect(readBack?.width == 10)
        #expect(readBack?.height == 10)
    }

    @Test("Creates intermediate directories if they don't exist")
    func createsDirectories() throws {
        let image = makeTestImage()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodcase-test-\(UUID().uuidString)")
            .appendingPathComponent("nested")
            .appendingPathComponent("output.png")
        defer {
            try? FileManager.default.removeItem(
                at: outputURL.deletingLastPathComponent().deletingLastPathComponent()
            )
        }

        try ImageExporter.writePNG(image, to: outputURL)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }
}
