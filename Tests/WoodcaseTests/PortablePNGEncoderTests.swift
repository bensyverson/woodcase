//
//  PortablePNGEncoderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The Foundation-only PNG writer: premultiplied RGBA8 in, a PNG any decoder reads out.
struct PortablePNGEncoderTests {
    @Test("The file opens with the PNG signature and an IHDR naming its size")
    func signatureAndHeader() throws {
        let png = [UInt8](PortablePNGEncoder.encode(premultipliedRGBA: [255, 0, 0, 255], width: 1, height: 1))
        try #require(png.count > 40)
        #expect(Array(png.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(Array(png[12 ..< 16]) == Array("IHDR".utf8))
        #expect(Array(png[16 ..< 24]) == [0, 0, 0, 1, 0, 0, 0, 1])
        #expect(Array(png.suffix(12)) == [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    }

    @Test("An opaque image is written as RGB, a translucent one as RGBA")
    func colorTypeFollowsAlpha() throws {
        let opaque = [UInt8](PortablePNGEncoder.encode(premultipliedRGBA: [9, 9, 9, 255], width: 1, height: 1))
        let translucent = [UInt8](PortablePNGEncoder.encode(premultipliedRGBA: [9, 9, 9, 128], width: 1, height: 1))
        try #require(opaque.count > 26 && translucent.count > 26)
        // IHDR data: width(4) height(4) depth(1) color type(1) …
        #expect(opaque[25] == 2)
        #expect(translucent[25] == 6)
    }

    #if canImport(ImageIO)
        @Test("ImageIO decodes a gradient to the exact pixels written")
        func decodesOpaqueGradient() throws {
            let width = 37, height = 23
            var pixels: [UInt8] = []
            for y in 0 ..< height {
                for x in 0 ..< width {
                    pixels += [UInt8(x * 6), UInt8(y * 11), UInt8((x + y) % 256), 255]
                }
            }
            let png = PortablePNGEncoder.encode(premultipliedRGBA: pixels, width: width, height: height)
            let decoded = try #require(PNGTestDecoder(png))
            #expect(decoded.width == width)
            #expect(decoded.height == height)
            for (x, y) in [(0, 0), (36, 0), (0, 22), (36, 22), (18, 11)] {
                #expect(decoded.rgba(x: x, y: y) == [x * 6, y * 11, (x + y) % 256, 255])
            }
        }

        @Test("Premultiplied input is written with straight alpha")
        func unpremultiplies() throws {
            // Premultiplied (128, 0, 64, 128) is straight (255, 0, 128, 128);
            // fully transparent pixels carry no color.
            let pixels: [UInt8] = [128, 0, 64, 128, 0, 0, 0, 0]
            let png = PortablePNGEncoder.encode(premultipliedRGBA: pixels, width: 2, height: 1)
            let decoded = try #require(PNGTestDecoder(png))
            #expect(decoded.rgba(x: 0, y: 0) == [255, 0, 128, 128])
            #expect(decoded.rgba(x: 1, y: 0)[3] == 0)
        }
    #endif

    @Test("A mesh raster encodes to the same bytes as its pixels do")
    func meshRasterConvenience() {
        let raster = PenMeshRaster(width: 2, height: 1, pixels: [1, 2, 3, 255, 4, 5, 6, 255])
        #expect(raster.pngData() == PortablePNGEncoder.encode(premultipliedRGBA: raster.pixels, width: 2, height: 1))
    }
}
