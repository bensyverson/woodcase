//
//  PenMeshRaster+PNG.swift
//  Woodcase
//

import Foundation

public extension PenMeshRaster {
    /// The raster as a PNG file's bytes, encoded without CoreGraphics.
    ///
    /// See ``PortablePNGEncoder`` for the format choices; the bytes are deterministic.
    ///
    /// - Returns: The PNG file.
    func pngData() -> Data {
        PortablePNGEncoder.encode(premultipliedRGBA: pixels, width: width, height: height)
    }
}
