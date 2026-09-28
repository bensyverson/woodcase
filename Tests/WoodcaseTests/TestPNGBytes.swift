//
//  TestPNGBytes.swift
//  Woodcase
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Real PNG bytes for tests that need something `CGImageSource` will actually decode.
///
/// Fabricated bytes are fine for a cache round-trip, which only compares `Data`, but a
/// decode test that fed them would pass for the wrong reason — it would prove only that
/// decoding failed. These are encoded by ImageIO, so what comes back out is a genuine
/// `CGImage` of the size asked for.
enum TestPNGBytes {
    /// PNG bytes for a solid blue image of the given pixel size.
    ///
    /// - Parameters:
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    /// - Returns: The encoded PNG data.
    static func solid(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0, green: 0.5, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }
}
