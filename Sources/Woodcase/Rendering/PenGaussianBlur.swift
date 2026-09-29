import Accelerate
import CoreGraphics

/// A Gaussian blur of an 8-bit RGBA image on the CPU, in the image's own encoding.
///
/// Pen blurs — layer blur and background blur alike — with a Gaussian of sigma `radius / 2`
/// points applied to the **encoded** pixel values, not to linear light. Convolving the
/// premultiplied 8-bit bytes directly does exactly that, so a red/blue edge meets in the
/// same darkened middle Pen's does.
///
/// This used to be Core Image's `CIGaussianBlur`. Core Image renders through Metal even
/// when asked for its software renderer, so wherever no GPU is reachable — the Claude Code
/// Bash sandbox, a headless VM — `createCGImage` returns `nil` and the blur silently did
/// nothing. A separable convolution through Accelerate needs no device and gives the same
/// pixels everywhere.
enum PenGaussianBlur {
    /// What the kernel reads past the image's edges.
    enum Edges: Friendly {
        /// The edge pixels repeat outward, as Pen's backdrop blur clamps.
        case extend
        /// Beyond the edges is fully transparent, as for a layer blurred with its padding.
        case transparent
    }

    /// Sigmas below this many pixels change nothing an 8-bit image can show.
    static let minimumSigma: CGFloat = 0.25

    /// The weights of a normalized Gaussian of `sigma` pixels, reaching three sigmas each way.
    ///
    /// - Parameter sigma: The standard deviation, in pixels; positive.
    /// - Returns: An odd number of weights summing to 1, symmetric about the middle one.
    static func kernel(sigma: CGFloat) -> [Float] {
        let reach = max(1, Int((3 * sigma).rounded(.up)))
        let weights = (-reach ... reach).map { offset -> Float in
            Float(exp(-Double(offset * offset) / (2 * Double(sigma * sigma))))
        }
        let total = weights.reduce(0, +)
        return weights.map { $0 / total }
    }

    /// Blurs `image` by a Gaussian of `sigma` pixels.
    ///
    /// - Parameters:
    ///   - image: An image to blur; it is redrawn as premultiplied 8-bit RGBA in its own
    ///     color space (sRGB when it has none).
    ///   - sigma: The standard deviation, in pixels. Below ``minimumSigma`` the image comes
    ///     back as it is.
    ///   - edges: What the kernel reads past the image's edges.
    /// - Returns: The blurred image, the same size as `image`, or `nil` when a buffer could
    ///   not be made.
    static func blur(_ image: CGImage, sigma: CGFloat, edges: Edges) -> CGImage? {
        guard sigma >= minimumSigma else { return image }
        let width = image.width
        let height = image.height
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let source = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: bitmapInfo
        ), let target = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: bitmapInfo
        ), let sourceData = source.data, let targetData = target.data
        else { return nil }
        source.setBlendMode(.copy)
        source.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var input = vImage_Buffer(
            data: sourceData, height: vImagePixelCount(height), width: vImagePixelCount(width),
            rowBytes: source.bytesPerRow
        )
        var output = vImage_Buffer(
            data: targetData, height: vImagePixelCount(height), width: vImagePixelCount(width),
            rowBytes: target.bytesPerRow
        )
        let weights = kernel(sigma: sigma)
        let background: [UInt8] = [0, 0, 0, 0]
        let flags = vImage_Flags(edges == .extend ? kvImageEdgeExtend : kvImageBackgroundColorFill)
        let error = weights.withUnsafeBufferPointer { kernel in
            vImageSepConvolve_ARGB8888(
                &input, &output, nil, 0, 0,
                kernel.baseAddress!, UInt32(kernel.count),
                kernel.baseAddress!, UInt32(kernel.count),
                0, background, flags
            )
        }
        guard error == kvImageNoError else { return nil }
        return target.makeImage()
    }
}
