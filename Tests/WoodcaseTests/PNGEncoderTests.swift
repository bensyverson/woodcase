//
//  PNGEncoderTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Woodcase

struct PNGEncoderTests {
    /// A solid 12×8 image to encode.
    private func makeImage(width: Int = 12, height: Int = 8) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0, green: 0.4, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test("Encodes a CGImage to PNG bytes that decode back at the same size")
    func encodesToBytes() throws {
        let data = try PNGEncoder.encode(makeImage())

        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let readBack = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(readBack.width == 12)
        #expect(readBack.height == 8)
    }

    @Test("Writes a PNG file, creating intermediate directories")
    func writesFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("png-encoder-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/out.png")

        try PNGEncoder.write(makeImage(), to: url)

        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("A destination that cannot be created names the file it failed on")
    func reportsUnwritableDestination() throws {
        // A path whose parent is an existing *file* cannot be created as a directory.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("png-encoder-blocker-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        #expect(throws: (any Error).self) {
            try PNGEncoder.write(makeImage(), to: blocker.appendingPathComponent("out.png"))
        }
    }

    @Test("The encoding error describes the file it could not finalize")
    func errorDescribesFile() {
        let url = URL(fileURLWithPath: "/nowhere/out.png")
        let error = PNGEncoder.EncodingError.destinationUnavailable(url)
        #expect(error.description.contains("/nowhere/out.png"))
    }
}
