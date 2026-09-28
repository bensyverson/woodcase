//
//  FillBox+MeshRaster.swift
//  Woodcase
//

extension FillBox {
    /// The raster size for a mesh baked for this box: the box at `scale` pixels per point,
    /// shrunk to ``ReactEmitter/meshRasterMaximumSide`` on its long side when larger, or a
    /// ``ReactEmitter/meshRasterLongSide`` square when either side is unknown (the browser
    /// stretches it to the box either way).
    ///
    /// - Parameter scale: Raster pixels per point.
    /// - Returns: The raster's width and height in pixels, each at least 1.
    func meshRasterSize(scale: Double) -> (width: Int, height: Int) {
        let square = ReactEmitter.meshRasterLongSide
        guard let width, let height, width > 0, height > 0, scale > 0 else { return (square, square) }
        let density = min(scale, Double(ReactEmitter.meshRasterMaximumSide) / max(width, height))
        let pixels = { (side: Double) in max(1, Int((side * density).rounded())) }
        return (pixels(width), pixels(height))
    }
}
