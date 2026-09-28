import CoreGraphics

extension PenShapeOutline {
    /// The outline as a CoreGraphics path, one CoreGraphics call per element.
    var cgPath: CGPath {
        let path = CGMutablePath()
        for element in elements {
            path.add(element)
        }
        return path
    }
}
