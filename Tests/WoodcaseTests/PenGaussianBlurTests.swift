import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

struct PenGaussianBlurTests {
    /// A `width`×40 opaque image: red left of `edge`, blue from it on.
    private static func step(width: Int = 80, edge: Int = 40) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: edge, height: 40))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: edge, y: 0, width: width - edge, height: 40))
        return try #require(context.makeImage())
    }

    @Test("The kernel is odd, symmetric, normalised and reaches three sigmas")
    func kernelShape() throws {
        let weights = PenGaussianBlur.kernel(sigma: 4)
        try #require(weights.count == 25)
        #expect(abs(weights.reduce(0, +) - 1) < 1e-5)
        #expect(weights == Array(weights.reversed()))
        #expect(weights[12] == weights.max())
    }

    @Test("A blurred step fits the sigma it was blurred with, in encoded values")
    func stepFitsSigma() throws {
        let blurred = try #require(PenGaussianBlur.blur(Self.step(), sigma: 4, edges: .extend))
        let pixels = try #require(PixelGrid(blurred))
        let fit = try #require(EdgeSigmaFit(profile: pixels.row(20, from: 10, through: 70, channel: 0)))
        #expect(abs(fit.sigma - 4) < 0.2, "sigma \(fit.sigma)")
        #expect(abs(fit.center - 30) < 0.5, "centre \(fit.center)")
        // Encoded-value blending: half-way across the edge both channels are near 128,
        // where a linear-light blur would give about 188.
        let middle = pixels.pixel(40, 20)
        #expect((115 ... 140).contains(middle.r) && (115 ... 140).contains(middle.b), "\(middle)")
    }

    @Test("Extended edges keep an opaque image opaque to its corners")
    func extendedEdges() throws {
        let blurred = try #require(PenGaussianBlur.blur(Self.step(), sigma: 6, edges: .extend))
        let pixels = try #require(PixelGrid(blurred))
        #expect(pixels.pixel(0, 0) == PixelGrid.RGBA(r: 255, g: 0, b: 0, a: 255), "\(pixels.pixel(0, 0))")
        #expect(pixels.pixel(79, 39) == PixelGrid.RGBA(r: 0, g: 0, b: 255, a: 255), "\(pixels.pixel(79, 39))")
        #expect(pixels.pixel(40, 0).r > 60, "the edge is blurred right up to the border: \(pixels.pixel(40, 0))")
    }

    @Test("Transparent edges fade an image out at its borders")
    func transparentEdges() throws {
        let blurred = try #require(PenGaussianBlur.blur(Self.step(), sigma: 6, edges: .transparent))
        let corner = try #require(PixelGrid(blurred)).pixel(0, 0)
        #expect(corner.a < 128, "\(corner)")
    }

    @Test("A sigma too small to show returns the image untouched")
    func tinySigma() throws {
        let image = try Self.step()
        #expect(PenGaussianBlur.blur(image, sigma: 0.1, edges: .extend) === image)
    }
}
