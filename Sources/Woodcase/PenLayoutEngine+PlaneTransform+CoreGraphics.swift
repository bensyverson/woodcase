//
//  PenLayoutEngine+PlaneTransform+CoreGraphics.swift
//  Woodcase
//

#if canImport(CoreGraphics)
    import CoreGraphics

    public extension PenLayoutEngine.PlaneTransform {
        /// The same map as a Core Graphics transform, which shares its coefficients and
        /// its convention: a point maps to `(a·x + c·y + tx, b·x + d·y + ty)`.
        var cgAffineTransform: CGAffineTransform {
            CGAffineTransform(
                a: CGFloat(a), b: CGFloat(b), c: CGFloat(c), d: CGFloat(d), tx: CGFloat(tx), ty: CGFloat(ty)
            )
        }
    }
#endif
