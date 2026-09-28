//
//  PortablePNGEncoder.swift
//  Woodcase
//

import Foundation

/// Encodes an RGBA8 bitmap as PNG bytes using Foundation alone, so it builds on Linux.
///
/// ``PNGEncoder`` goes through ImageIO and needs a `CGImage`; this one takes raw
/// premultiplied pixels — the form ``PenMeshRaster`` produces — and writes the file
/// itself, compressing with ``ZlibEncoder``. It exists for code that must not depend on
/// CoreGraphics, first of all the React emitter, which bakes mesh gradients into
/// `data:` URIs.
///
/// PNG stores straight alpha, so each pixel is un-premultiplied on the way out. A fully
/// opaque image is written as 8-bit RGB (colour type 2), anything else as 8-bit RGBA
/// (colour type 6). Each row takes whichever of the five PNG filters leaves the smallest
/// residuals, the usual heuristic. The output is deterministic.
///
/// ```swift
/// let png = PortablePNGEncoder.encode(premultipliedRGBA: raster.pixels,
///                                     width: raster.width, height: raster.height)
/// ```
public enum PortablePNGEncoder {
    /// Encodes premultiplied RGBA8 pixels as a PNG file's bytes.
    ///
    /// - Parameters:
    ///   - pixels: `width × height × 4` bytes, premultiplied RGBA, rows top to bottom
    ///     with no padding, colour already in sRGB.
    ///   - width: The width in pixels.
    ///   - height: The height in pixels.
    /// - Returns: The PNG file.
    public static func encode(premultipliedRGBA pixels: [UInt8], width: Int, height: Int) -> Data {
        let pixelCount = width * height
        let isOpaque = stride(from: 3, to: pixelCount * 4, by: 4).allSatisfy { pixels[$0] == 255 }
        let channels = isOpaque ? 3 : 4
        let straight = straightAlpha(pixels, pixelCount: pixelCount, channels: channels)
        let filtered = filterRows(straight, width: width, height: height, channels: channels)

        var header: [UInt8] = []
        header += bigEndian(UInt32(width))
        header += bigEndian(UInt32(height))
        // Bit depth 8; colour type; deflate compression; adaptive filtering; no interlace.
        header += [8, isOpaque ? 2 : 6, 0, 0, 0]

        var file: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        file += chunk("IHDR", header)
        file += chunk("IDAT", ZlibEncoder.compress(filtered))
        file += chunk("IEND", [])
        return Data(file)
    }

    // MARK: - Pixels

    /// Un-premultiplies, dropping the alpha channel when `channels` is 3.
    private static func straightAlpha(_ pixels: [UInt8], pixelCount: Int, channels: Int) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: pixelCount * channels)
        for index in 0 ..< pixelCount {
            let source = index * 4
            let target = index * channels
            let alpha = Int(pixels[source + 3])
            for channel in 0 ..< 3 {
                let value = Int(pixels[source + channel])
                output[target + channel] = switch alpha {
                case 0: 0
                case 255: UInt8(value)
                default: UInt8(min(255, (value * 255 + alpha / 2) / alpha))
                }
            }
            if channels == 4 {
                output[target + 3] = UInt8(alpha)
            }
        }
        return output
    }

    // MARK: - Filtering

    /// Prefixes each row with the filter type that minimises its residuals, and filters it.
    private static func filterRows(_ bytes: [UInt8], width: Int, height: Int, channels: Int) -> [UInt8] {
        let rowLength = width * channels
        var output: [UInt8] = []
        output.reserveCapacity((rowLength + 1) * height)
        let zeroRow = [UInt8](repeating: 0, count: rowLength)
        for y in 0 ..< height {
            let row = Array(bytes[y * rowLength ..< (y + 1) * rowLength])
            let above = y == 0 ? zeroRow : Array(bytes[(y - 1) * rowLength ..< y * rowLength])
            let candidates = (0 ... 4).map { filter(UInt8($0), row: row, above: above, channels: channels) }
            let best = candidates.indices.min { cost(candidates[$0]) < cost(candidates[$1]) } ?? 0
            output.append(UInt8(best))
            output += candidates[best]
        }
        return output
    }

    /// One row filtered with PNG filter `type` (0 none, 1 sub, 2 up, 3 average, 4 Paeth).
    private static func filter(_ type: UInt8, row: [UInt8], above: [UInt8], channels: Int) -> [UInt8] {
        row.indices.map { index in
            let left = index >= channels ? Int(row[index - channels]) : 0
            let up = Int(above[index])
            let upLeft = index >= channels ? Int(above[index - channels]) : 0
            let predictor = switch type {
            case 1: left
            case 2: up
            case 3: (left + up) / 2
            case 4: paeth(left: left, up: up, upLeft: upLeft)
            default: 0
            }
            return UInt8(truncatingIfNeeded: Int(row[index]) - predictor)
        }
    }

    /// The Paeth predictor: whichever neighbour is closest to `left + up − upLeft`.
    private static func paeth(left: Int, up: Int, upLeft: Int) -> Int {
        let estimate = left + up - upLeft
        let distanceLeft = abs(estimate - left)
        let distanceUp = abs(estimate - up)
        let distanceUpLeft = abs(estimate - upLeft)
        if distanceLeft <= distanceUp, distanceLeft <= distanceUpLeft { return left }
        if distanceUp <= distanceUpLeft { return up }
        return upLeft
    }

    /// The sum of a filtered row's residuals read as signed bytes.
    private static func cost(_ row: [UInt8]) -> Int {
        row.reduce(0) { $0 + abs(Int(Int8(bitPattern: $1))) }
    }

    // MARK: - Chunks

    /// A PNG chunk: length, type, data and the CRC-32 of type and data.
    private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let typed = Array(type.utf8) + data
        return bigEndian(UInt32(data.count)) + typed + bigEndian(crc32(typed))
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }
    }

    /// The CRC-32 (ISO 3309, reflected polynomial `0xEDB88320`) PNG chunks carry.
    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }
}
