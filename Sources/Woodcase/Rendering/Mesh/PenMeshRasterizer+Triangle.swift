//
//  PenMeshRasterizer+Triangle.swift
//  Woodcase
//

import Foundation

extension PenMeshRasterizer {
    /// Sub-pixel steps per pixel. Positions snap to 1/256 px, so edge functions are exact
    /// integers and two triangles evaluate a shared edge identically.
    static let subpixelSteps: Int64 = 256

    /// How far outside the raster, in pixels, a position may lie before it is clamped.
    /// Keeps every edge-function product well inside `Int64`.
    static let coordinateLimit = 1_048_576.0

    /// One triangle corner: a snapped fixed-point position and a premultiplied color.
    struct Corner {
        /// Snaps a position and premultiplies its color, or fails for a non-finite
        /// position.
        init?(_ position: SIMD2<Double>, color: PenMeshColor) {
            guard position.x.isFinite, position.y.isFinite else { return nil }
            func snap(_ value: Double) -> Int64 {
                let clamped = min(max(value, -coordinateLimit), coordinateLimit)
                return Int64((clamped * Double(subpixelSteps)).rounded())
            }
            x = snap(position.x)
            y = snap(position.y)
            let alpha = min(max(color.alpha, 0), 1)
            func premultiply(_ channel: Double) -> Double {
                min(max(channel, 0), 1) * alpha
            }
            self.color = SIMD4(premultiply(color.red), premultiply(color.green), premultiply(color.blue), alpha)
        }

        /// The horizontal position, in sub-pixel steps.
        let x: Int64

        /// The vertical position, in sub-pixel steps, `y` down.
        let y: Int64

        /// The premultiplied color, RGBA.
        let color: SIMD4<Double>
    }

    /// Twice the signed area of `a b p`, in squared sub-pixel steps: positive when `p`
    /// is on the interior side of `a → b` for a positively wound triangle.
    static func edge(_ a: Corner, _ b: Corner, _ x: Int64, _ y: Int64) -> Int64 {
        (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x)
    }

    /// Whether `a → b` is a top or left edge of a positively wound triangle (`y` down):
    /// a pixel center exactly on such an edge is inside.
    static func isTopLeft(_ a: Corner, _ b: Corner) -> Bool {
        b.y < a.y || (b.y == a.y && b.x > a.x)
    }

    /// Gouraud-shades one triangle into the buffer, compositing source-over.
    static func fill(_ v0: Corner, _ v1: Corner, _ v2: Corner, into pixels: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int) {
        var v1 = v1
        var v2 = v2
        var area = edge(v0, v1, v2.x, v2.y)
        guard area != 0 else { return }
        if area < 0 {
            swap(&v1, &v2)
            area = -area
        }
        let half = subpixelSteps / 2
        let xStart = max(0, ceilDiv(min(v0.x, v1.x, v2.x) - half, subpixelSteps))
        let xEnd = min(Int64(width - 1), floorDiv(max(v0.x, v1.x, v2.x) - half, subpixelSteps))
        let yStart = max(0, ceilDiv(min(v0.y, v1.y, v2.y) - half, subpixelSteps))
        let yEnd = min(Int64(height - 1), floorDiv(max(v0.y, v1.y, v2.y) - half, subpixelSteps))
        guard xStart <= xEnd, yStart <= yEnd else { return }

        // Edge i is the one opposite vertex i; its value is that vertex's weight × area.
        let bias0: Int64 = isTopLeft(v1, v2) ? 1 : 0
        let bias1: Int64 = isTopLeft(v2, v0) ? 1 : 0
        let bias2: Int64 = isTopLeft(v0, v1) ? 1 : 0
        let step0 = -(v2.y - v1.y) * subpixelSteps
        let step1 = -(v0.y - v2.y) * subpixelSteps
        let step2 = -(v1.y - v0.y) * subpixelSteps
        let inverseArea = 1 / Double(area)
        // Interpolating as c₂ + w₀(c₀ − c₂) + w₁(c₁ − c₂) keeps the weights summing to
        // exactly one, so a uniform color stays exactly uniform.
        let delta0 = v0.color - v2.color
        let delta1 = v1.color - v2.color
        let firstX = xStart * subpixelSteps + half
        for y in yStart ... yEnd {
            let centerY = y * subpixelSteps + half
            var e0 = edge(v1, v2, firstX, centerY)
            var e1 = edge(v2, v0, firstX, centerY)
            var e2 = edge(v0, v1, firstX, centerY)
            var offset = (Int(y) * width + Int(xStart)) * 4
            for _ in xStart ... xEnd {
                if e0 + bias0 > 0, e1 + bias1 > 0, e2 + bias2 > 0 {
                    let source = v2.color + Double(e0) * inverseArea * delta0 + Double(e1) * inverseArea * delta1
                    composite(source, into: pixels, at: offset)
                }
                e0 += step0
                e1 += step1
                e2 += step2
                offset += 4
            }
        }
    }

    /// Source-over onto the 8-bit premultiplied buffer, rounding to the nearest step.
    private static func composite(_ source: SIMD4<Double>, into pixels: UnsafeMutableBufferPointer<UInt8>, at offset: Int) {
        let alpha = min(max(source.w, 0), 1)
        let clamped = SIMD4(
            min(max(source.x, 0), alpha),
            min(max(source.y, 0), alpha),
            min(max(source.z, 0), alpha),
            alpha
        ) * 255
        // Most pixels are covered once, onto transparent black: no blend needed.
        let blended: SIMD4<Double> = if pixels[offset + 3] == 0 {
            clamped
        } else {
            clamped + SIMD4(
                Double(pixels[offset]),
                Double(pixels[offset + 1]),
                Double(pixels[offset + 2]),
                Double(pixels[offset + 3])
            ) * (1 - alpha)
        }
        let rounded = blended.rounded(.toNearestOrAwayFromZero).clamped(lowerBound: SIMD4(repeating: 0), upperBound: SIMD4(repeating: 255))
        pixels[offset] = UInt8(rounded.x)
        pixels[offset + 1] = UInt8(rounded.y)
        pixels[offset + 2] = UInt8(rounded.z)
        pixels[offset + 3] = UInt8(rounded.w)
    }

    private static func floorDiv(_ value: Int64, _ divisor: Int64) -> Int64 {
        value >= 0 ? value / divisor : -((-value + divisor - 1) / divisor)
    }

    private static func ceilDiv(_ value: Int64, _ divisor: Int64) -> Int64 {
        -floorDiv(-value, divisor)
    }
}
