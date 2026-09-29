//
//  PenMeshRaster.swift
//  Woodcase
//

import Foundation

/// A rasterized mesh gradient: premultiplied RGBA, 8 bits a channel, sRGB-encoded.
///
/// Rows run top to bottom with no padding, so ``bytesPerRow`` is `width × 4`. Hand the
/// bytes to CoreGraphics as `premultipliedLast` in sRGB, or encode them as a PNG.
public struct PenMeshRaster: Friendly {
    /// Creates a raster.
    ///
    /// - Parameters:
    ///   - width: The width in pixels.
    ///   - height: The height in pixels.
    ///   - pixels: `width × height × 4` bytes, premultiplied RGBA, rows top to bottom.
    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The width in pixels.
    public let width: Int

    /// The height in pixels.
    public let height: Int

    /// Premultiplied RGBA bytes, rows top to bottom.
    public let pixels: [UInt8]

    /// The byte count of one row.
    public var bytesPerRow: Int {
        width * 4
    }

    /// The pixel at a position.
    ///
    /// - Parameters:
    ///   - x: The column, `0..<width`, from the left.
    ///   - y: The row, `0..<height`, from the top.
    /// - Returns: The premultiplied channels.
    public func pixel(x: Int, y: Int) -> Pixel {
        let offset = y * bytesPerRow + x * 4
        return Pixel(red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2], alpha: pixels[offset + 3])
    }

    /// One premultiplied RGBA8 pixel.
    public struct Pixel: Friendly {
        /// Creates a pixel.
        ///
        /// - Parameters:
        ///   - red: Premultiplied red.
        ///   - green: Premultiplied green.
        ///   - blue: Premultiplied blue.
        ///   - alpha: Alpha.
        public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        /// Premultiplied red.
        public var red: UInt8

        /// Premultiplied green.
        public var green: UInt8

        /// Premultiplied blue.
        public var blue: UInt8

        /// Alpha.
        public var alpha: UInt8
    }
}
