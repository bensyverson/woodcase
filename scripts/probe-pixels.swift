#!/usr/bin/env swift

// Extracts RGBA pixel values from a PNG at given coordinates.
//
// Usage:
//   scripts/probe-pixels.swift <image.png> <x1,y1> [x2,y2] ...
//
// Example:
//   scripts/probe-pixels.swift Tests/WoodcaseTests/Fixtures/render-shapes-and-fills.png 160,160 420,160
//
// Output:
//   (160, 160) → RGBA(255, 0, 0, 255)
//   (420, 160) → RGBA(0, 102, 255, 255)
//
// Note: The image is read in the sRGB color space to match CoreGraphics rendering defaults.
// Coordinates are in pixels (not points). For @2x exports, multiply logical coordinates by 2.

import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: probe-pixels.swift <image.png> <x,y> [x,y] ...\n", stderr)
    exit(1)
}

let imagePath = CommandLine.arguments[1]
let coordinates = CommandLine.arguments.dropFirst(2)

/// Load the image via NSImage → CGImage
let url = URL(fileURLWithPath: imagePath)
guard let nsImage = NSImage(contentsOf: url),
      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    fputs("Error: Could not load image at \(imagePath)\n", stderr)
    exit(1)
}

let width = cgImage.width
let height = cgImage.height

fputs("Image: \(imagePath) (\(width)×\(height) pixels)\n", stderr)

// Create a bitmap context in sRGB so we get consistent color values
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

guard let context = CGContext(
    data: &pixelData,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fputs("Error: Could not create bitmap context\n", stderr)
    exit(1)
}

context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

// Probe each coordinate
for coord in coordinates {
    let parts = coord.split(separator: ",")
    guard parts.count == 2,
          let x = Int(parts[0]),
          let y = Int(parts[1])
    else {
        fputs("Error: Invalid coordinate '\(coord)' — expected x,y\n", stderr)
        continue
    }

    guard x >= 0, x < width, y >= 0, y < height else {
        fputs("Error: (\(x), \(y)) is out of bounds (image is \(width)×\(height))\n", stderr)
        continue
    }

    let offset = (y * bytesPerRow) + (x * bytesPerPixel)
    let r = pixelData[offset]
    let g = pixelData[offset + 1]
    let b = pixelData[offset + 2]
    let a = pixelData[offset + 3]

    // Un-premultiply if alpha < 255 and > 0
    if a > 0, a < 255 {
        let alpha = Double(a)
        let ur = UInt8(min(255, round(Double(r) * 255.0 / alpha)))
        let ug = UInt8(min(255, round(Double(g) * 255.0 / alpha)))
        let ub = UInt8(min(255, round(Double(b) * 255.0 / alpha)))
        print("(\(x), \(y)) → RGBA(\(ur), \(ug), \(ub), \(a))  [pre-multiplied raw: \(r), \(g), \(b), \(a)]")
    } else {
        print("(\(x), \(y)) → RGBA(\(r), \(g), \(b), \(a))")
    }
}
