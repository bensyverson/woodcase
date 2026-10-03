//
//  PenImageTransform+CoreGraphics.swift
//  Woodcase
//

#if canImport(CoreGraphics)
    import CoreGraphics

    public extension PenImageTransform {
        /// The same map as a Core Graphics transform, which shares its coefficients and
        /// its convention: a point maps to `(a·x + c·y + tx, b·x + d·y + ty)`.
        var cgAffineTransform: CGAffineTransform {
            planeTransform.cgAffineTransform
        }
    }
#endif
