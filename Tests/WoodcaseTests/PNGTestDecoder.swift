//
//  PNGTestDecoder.swift
//  WoodcaseTests
//

#if canImport(ImageIO)
    import CoreGraphics
    import Foundation
    import ImageIO

    /// Decodes PNG bytes with ImageIO, a decoder independent of the one under test.
    ///
    /// Reads the decoded image's own backing bytes rather than drawing it into a context,
    /// so the channels come back exactly as the PNG stored them: straight (not
    /// premultiplied) alpha, no colour conversion.
    struct PNGTestDecoder {
        /// The decoded width in pixels.
        let width: Int
        /// The decoded height in pixels.
        let height: Int
        private let bytes: [UInt8]
        private let bytesPerRow: Int
        private let channels: Int

        /// Decodes `data`, or returns `nil` when ImageIO rejects it.
        init?(_ data: Data) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetStatus(source) == .statusComplete,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  image.bitsPerComponent == 8,
                  let provided = image.dataProvider?.data
            else { return nil }
            width = image.width
            height = image.height
            bytesPerRow = image.bytesPerRow
            channels = image.bitsPerPixel / 8
            bytes = [UInt8](provided as Data)
        }

        /// Decodes a `data:image/png;base64,…` URI.
        init?(dataURI: String) {
            let prefix = "data:image/png;base64,"
            guard dataURI.hasPrefix(prefix),
                  let data = Data(base64Encoded: String(dataURI.dropFirst(prefix.count)))
            else { return nil }
            self.init(data)
        }

        /// The straight-alpha RGBA of one pixel; alpha is 255 for an RGB image.
        func rgba(x: Int, y: Int) -> [Int] {
            let offset = y * bytesPerRow + x * channels
            let rgb = (0 ..< 3).map { Int(bytes[offset + $0]) }
            return rgb + [channels == 4 ? Int(bytes[offset + 3]) : 255]
        }
    }
#endif
