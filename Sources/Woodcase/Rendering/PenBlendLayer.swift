//
//  PenBlendLayer.swift
//  Woodcase
//

import CoreGraphics

/// An isolated layer composited onto a bitmap context pixel by pixel, by W3C's formula
/// (``PenBlendMode/composite(source:over:)``), for the blend modes Core Graphics draws
/// inexactly (``PenBlendMode/Compositing/perPixel``).
///
/// Starting the layer copies the bitmap under the region it may touch — the current clip,
/// narrowed by an optional rectangle — and clears it; whatever is drawn next lands on that
/// transparent region, at the normal blend, as an isolated group; ``composite(in:)`` then
/// blends it over the copy and writes the result back.
///
/// It reads the bitmap through `CGContext.data`, so it needs an 8-bit RGB bitmap with
/// premultiplied alpha, and no Core Graphics transparency layer may be open around it —
/// one draws to a hidden buffer the bitmap does not show. The renderer keeps that promise
/// by opening its own layers per pixel wherever a per-pixel blend lies inside
/// (``PenRenderer``); anywhere else ``init(mode:opacity:in:within:)`` returns `nil` and the
/// caller falls back to ``PenBlendMode/cgBlendMode``. Exactness costs a copy and a pass over
/// the region, which is why only the per-pixel modes take this path.
final class PenBlendLayer {
    /// The byte offsets of each channel within a pixel.
    private struct Channels {
        let red: Int
        let green: Int
        let blue: Int
        let alpha: Int

        /// The layout of `context`'s pixels, or `nil` when the layer cannot read them.
        init?(_ context: CGContext) {
            guard context.bitsPerComponent == 8, context.bitsPerPixel == 32,
                  context.colorSpace?.model == .rgb
            else { return nil }
            let order = context.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
            let little = order == CGBitmapInfo.byteOrder32Little.rawValue
            guard little || order == 0 || order == CGBitmapInfo.byteOrder32Big.rawValue else { return nil }
            switch context.alphaInfo {
            case .premultipliedLast:
                // RGBA, or ABGR in a little-endian word.
                (red, green, blue, alpha) = little ? (3, 2, 1, 0) : (0, 1, 2, 3)
            case .premultipliedFirst:
                // ARGB, or BGRA in a little-endian word.
                (red, green, blue, alpha) = little ? (2, 1, 0, 3) : (1, 2, 3, 0)
            default:
                return nil
            }
        }
    }

    /// The pixels the layer covers: columns `x ..< x + width`, rows `y ..< y + height`, row 0
    /// at the top of the bitmap.
    private struct Region {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    /// The mode the layer blends with.
    let mode: PenBlendMode
    /// The alpha the layer is drawn at, `0…1`.
    let opacity: Double
    private let channels: Channels
    private let region: Region
    private let bytesPerRow: Int
    /// The bitmap under ``region`` before the layer cleared it, row by row.
    private let backdrop: [UInt8]

    /// Starts a layer on `context`: copies the bitmap under the region and clears it.
    ///
    /// - Parameters:
    ///   - mode: The blend mode the layer composites with.
    ///   - opacity: The alpha the layer is drawn at.
    ///   - context: The bitmap context; `nil` is returned for one the layer cannot read.
    ///   - rect: A user-space rectangle every drawing in the layer stays inside, narrowing
    ///     the region from the whole clip; `nil` for the clip alone.
    init?(mode: PenBlendMode, opacity: Double, in context: CGContext, within rect: CGRect? = nil) {
        guard let data = context.data, let channels = Channels(context) else { return nil }
        var user = context.boundingBoxOfClipPath
        if let rect {
            user = user.intersection(rect)
        }
        let height = context.height
        // The CTM's base space, not `convertToDeviceSpace`: a bitmap's "device space" is
        // flipped against it, and the base space is what `PenEffectRenderer` crops by too.
        let device = user.applying(context.ctm).insetBy(dx: -1, dy: -1)
            .intersection(CGRect(x: 0, y: 0, width: context.width, height: height))
        guard !device.isNull, !device.isEmpty else { return nil }
        let x0 = Int(device.minX.rounded(.down))
        let x1 = Int(device.maxX.rounded(.up))
        // The base space runs up from the bitmap's bottom; its rows run down from the top.
        let top = height - Int(device.maxY.rounded(.up))
        let bottom = height - Int(device.minY.rounded(.down))
        let region = Region(x: x0, y: top, width: x1 - x0, height: bottom - top)
        let bytesPerRow = context.bytesPerRow

        context.flush()
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let rowBytes = region.width * 4
        var copy = [UInt8](repeating: 0, count: rowBytes * region.height)
        copy.withUnsafeMutableBufferPointer { buffer in
            for row in 0 ..< region.height {
                let start = bytes + (region.y + row) * bytesPerRow + region.x * 4
                (buffer.baseAddress! + row * rowBytes).update(from: start, count: rowBytes)
                start.update(repeating: 0, count: rowBytes)
            }
        }
        self.mode = mode
        self.opacity = opacity
        self.channels = channels
        self.region = region
        self.bytesPerRow = bytesPerRow
        backdrop = copy
    }

    /// Blends what was drawn since the layer started over the bitmap it replaced, and writes
    /// the result back to `context` — the same context the layer started on.
    func composite(in context: CGContext) {
        guard let data = context.data else { return }
        context.flush()
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let rowBytes = region.width * 4
        let c = channels
        backdrop.withUnsafeBufferPointer { under in
            for row in 0 ..< region.height {
                let line = bytes + (region.y + row) * bytesPerRow + region.x * 4
                for column in 0 ..< region.width {
                    let pixel = line + column * 4
                    let b = under.baseAddress! + row * rowBytes + column * 4
                    guard pixel[c.alpha] > 0, opacity > 0 else {
                        pixel.update(from: b, count: 4)
                        continue
                    }
                    let source = SIMD4(
                        Double(pixel[c.red]), Double(pixel[c.green]), Double(pixel[c.blue]), Double(pixel[c.alpha])
                    ) * (opacity / 255)
                    let backdrop = SIMD4(Double(b[c.red]), Double(b[c.green]), Double(b[c.blue]), Double(b[c.alpha])) / 255
                    let out = mode.composite(source: source, over: backdrop)
                    pixel[c.red] = Self.byte(out.x)
                    pixel[c.green] = Self.byte(out.y)
                    pixel[c.blue] = Self.byte(out.z)
                    pixel[c.alpha] = Self.byte(out.w)
                }
            }
        }
    }

    /// Draws `body` blended by `mode`: per pixel when the mode needs it and `context` allows,
    /// otherwise at the mode's Core Graphics blend. `nil` draws `body` as it is.
    ///
    /// - Parameter rect: A user-space rectangle `body` stays inside, if one is known.
    static func draw(_ mode: PenBlendMode?, in context: CGContext, within rect: CGRect? = nil, _ body: () -> Void) {
        guard let mode else {
            body()
            return
        }
        if mode.compositing == .perPixel,
           let layer = PenBlendLayer(mode: mode, opacity: 1, in: context, within: rect)
        {
            body()
            layer.composite(in: context)
            return
        }
        context.saveGState()
        context.setBlendMode(mode.cgBlendMode)
        body()
        context.restoreGState()
    }

    /// A `0…1` channel as a byte, rounded and clamped.
    private static func byte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }
}
