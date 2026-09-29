import CoreGraphics
import Foundation

extension PenFillRenderer {
    /// Draws an angular gradient as a bitmap computed per device pixel.
    ///
    /// Each pixel's center is taken back into gradient space through `frame`; its angle
    /// there, measured clockwise on screen from straight up, is the stop position. The
    /// bitmap covers `bounds` — the paint domain, grown to take in the clip where the clip
    /// reaches past it — at the context's device resolution, so the seam and the color
    /// ramp are as sharp at 2x as at 1x.
    static func drawAngularGradient(
        _ gradient: PenFill.PenGradientFill,
        frame: CGAffineTransform,
        bounds: CGRect,
        in context: CGContext
    ) {
        guard let stops = gradient.colors, stops.count >= 2 else { return }

        var parsedStops: [(color: CGColor, position: CGFloat)] = []
        for stop in stops {
            guard let hex = stop.color.literalValue,
                  let color = PenColorParser.parse(hex)
            else { continue }
            parsedStops.append((color, CGFloat(stop.position.literalValue ?? 0)))
        }
        guard parsedStops.count >= 2 else { return }

        let device = context.userSpaceToDeviceSpaceTransform
        let pixelsPerPoint = max(hypot(device.a, device.b), hypot(device.c, device.d), 1)
        let w = Int(ceil(bounds.width * pixelsPerPoint))
        let h = Int(ceil(bounds.height * pixelsPerPoint))
        guard w > 0, h > 0 else { return }
        let stepX = bounds.width / CGFloat(w)
        let stepY = bounds.height / CGFloat(h)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        let stopData: [(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat, pos: CGFloat)] =
            parsedStops.map { stop in
                let comps = stop.color.components ?? [0, 0, 0, 1]
                let count = stop.color.numberOfComponents
                let r = comps[0]
                let g = count >= 3 ? comps[1] : comps[0]
                let b = count >= 3 ? comps[2] : comps[0]
                let a = count >= 4 ? comps[3] : (count >= 2 ? comps[1] : 1)
                return (r, g, b, a, stop.position)
            }

        let toGradient = frame.inverted()
        let fullTurn = 2 * CGFloat.pi

        for py in 0 ..< h {
            let userY = bounds.minY + (CGFloat(py) + 0.5) * stepY
            for px in 0 ..< w {
                let userX = bounds.minX + (CGFloat(px) + 0.5) * stepX
                let q = CGPoint(x: userX, y: userY).applying(toGradient)

                // Zero points straight up; y grows downward, so increasing angle is clockwise.
                var angle = atan2(q.y, q.x) + .pi / 2
                angle = angle.truncatingRemainder(dividingBy: fullTurn)
                if angle < 0 { angle += fullTurn }

                let (r, g, b, a) = interpolateRGBA(at: angle / fullTurn, stops: stopData)

                let offset = (py * w + px) * 4
                pixels[offset] = UInt8(clamping: Int((r * a * 255).rounded()))
                pixels[offset + 1] = UInt8(clamping: Int((g * a * 255).rounded()))
                pixels[offset + 2] = UInt8(clamping: Int((b * a * 255).rounded()))
                pixels[offset + 3] = UInt8(clamping: Int((a * 255).rounded()))
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: w, height: h,
                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                  space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                  provider: provider,
                  decode: nil, shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else { return }

        // Row 0 of the bitmap is the top of `bounds`; CG draws images bottom-up.
        context.saveGState()
        context.translateBy(x: bounds.minX, y: bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: bounds.size))
        context.restoreGState()
    }

    /// RGBA at position `t` between pre-extracted stops, padding with the end colors
    /// outside the first and last stop, as Pen does.
    static func interpolateRGBA(
        at t: CGFloat,
        stops: [(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat, pos: CGFloat)]
    ) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let first = stops[0]
        let last = stops[stops.count - 1]
        if t <= first.pos { return (first.r, first.g, first.b, first.a) }
        if t >= last.pos { return (last.r, last.g, last.b, last.a) }

        var lower = first
        var upper = last
        for i in 0 ..< stops.count - 1 where t >= stops[i].pos && t <= stops[i + 1].pos {
            lower = stops[i]
            upper = stops[i + 1]
            break
        }

        let range = upper.pos - lower.pos
        let localT: CGFloat = range > 0 ? (t - lower.pos) / range : 0

        return (
            lower.r + (upper.r - lower.r) * localT,
            lower.g + (upper.g - lower.g) * localT,
            lower.b + (upper.b - lower.b) * localT,
            lower.a + (upper.a - lower.a) * localT
        )
    }
}
