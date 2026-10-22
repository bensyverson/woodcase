//
//  PenImageLoadingPlaceholderTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Testing
@testable import Woodcase

/// An image fill whose image is not to hand — still downloading, or missing — draws
/// ``PenImageLoadingPlaceholder/color`` through its clip, so the layer's shape shows while
/// the image loads.
struct PenImageLoadingPlaceholderTests {
    private static let size = 10

    /// Paints `fills` through a 10×10 square onto white and returns the center pixel's
    /// RGBA, or onto a clear context when `white` is false.
    private func centerPixel(_ fills: PenFills, onWhite white: Bool = true) throws -> SIMD4<Int> {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: Self.size * Self.size * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: Self.size, height: Self.size,
                bitsPerComponent: 8, bytesPerRow: Self.size * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            let square = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
            if white {
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                context.fill(square)
            }
            let path = CGPath(rect: square, transform: nil)
            PenFillRenderer.renderFills(
                fills, clip: path, fillRule: .winding, domain: square, in: context,
                imageProvider: { _ in nil }
            )
        }
        let offset = (Self.size / 2 * Self.size + Self.size / 2) * 4
        return SIMD4(Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]), Int(pixels[offset + 3]))
    }

    private func imageFill(opacity: Double? = nil, enabled: Bool? = nil) -> PenFills {
        .single(.image(PenFill.PenImageFill(
            enabled: enabled.map { .literal($0) },
            opacity: opacity.map { .literal($0) },
            url: "./images/photo"
        )))
    }

    /// `color` composited over white at `alpha`.
    private func overWhite(_ color: PenHexColor, alpha: Double) -> SIMD4<Int> {
        func channel(_ value: UInt8) -> Int {
            Int((Double(value) * alpha + 255 * (1 - alpha)).rounded())
        }
        return SIMD4(channel(color.red), channel(color.green), channel(color.blue), 255)
    }

    private func isClose(_ a: SIMD4<Int>, _ b: SIMD4<Int>, tolerance: Int = 2) -> Bool {
        (0 ..< 4).allSatisfy { abs(a[$0] - b[$0]) <= tolerance }
    }

    @Test
    func `A missing image draws the loading gray through its clip`() throws {
        let color = PenImageLoadingPlaceholder.color
        let pixel = try centerPixel(imageFill())

        #expect(isClose(pixel, overWhite(color, alpha: Double(color.alpha) / 255)))
    }

    @Test
    func `The loading gray takes the fill's opacity`() throws {
        let color = PenImageLoadingPlaceholder.color
        let pixel = try centerPixel(imageFill(opacity: 0.5), onWhite: false)

        #expect(abs(pixel.w - Int((Double(color.alpha) * 0.5).rounded())) <= 2)
    }

    @Test
    func `A disabled image fill draws no loading gray`() throws {
        #expect(try centerPixel(imageFill(enabled: false), onWhite: false) == .zero)
    }

    @Test
    func `The loading gray is lighter on white than the failed-download placeholder`() throws {
        let failed = try #require(PenHexColor(FigmaImagePlaceholder.gray))
        let loading = try centerPixel(imageFill())

        #expect(loading.x > Int(failed.red))
        #expect(loading.x < 255)
    }
}
