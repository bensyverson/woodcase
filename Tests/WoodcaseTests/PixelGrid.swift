import CoreGraphics
import Foundation

/// A rendered image's pixels as sRGB 8-bit RGBA, un-premultiplied, for reading single
/// pixels and whole rows in effect-fidelity tests.
struct PixelGrid {
    /// One pixel's channels, 0…255.
    struct RGBA: Equatable {
        let r: Int
        let g: Int
        let b: Int
        let a: Int

        /// The channel named by `index`: 0 red, 1 green, 2 blue, 3 alpha.
        subscript(index: Int) -> Int {
            [r, g, b, a][index]
        }
    }

    let width: Int
    let height: Int
    private let bytes: [UInt8]

    /// Draws `image` into an sRGB premultiplied RGBA buffer of its own size.
    init?(_ image: CGImage) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        bytes = pixels
    }

    /// The pixel at column `x`, row `y` (row 0 at the top), un-premultiplied.
    func pixel(_ x: Int, _ y: Int) -> RGBA {
        let offset = (y * width + x) * 4
        let alpha = Int(bytes[offset + 3])
        func channel(_ index: Int) -> Int {
            let value = Int(bytes[offset + index])
            guard alpha > 0, alpha < 255 else { return value }
            return min(255, Int((Double(value) * 255 / Double(alpha)).rounded()))
        }
        return RGBA(r: channel(0), g: channel(1), b: channel(2), a: alpha)
    }

    /// One channel of row `y`, columns `x1…x2` inclusive, as 0…1 values.
    func row(_ y: Int, from x1: Int, through x2: Int, channel: Int) -> [Double] {
        (x1 ... x2).map { Double(pixel($0, y)[channel]) / 255 }
    }
}
