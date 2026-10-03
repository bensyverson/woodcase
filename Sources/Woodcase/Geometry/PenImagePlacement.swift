//
//  PenImagePlacement.swift
//  Woodcase
//

import Foundation

/// Where an image paint lands in its node: the crop box, the map that draws the image, and
/// the clip — the placement Pen 1.2.15 (format 2.20) gives a `mode` and a `transform`.
///
/// Every renderer and emitter places an image through this one type, so they agree with each
/// other and with Pen's own exports (`render-image-crops.pen`). It is pure geometry,
/// Foundation-only, in whatever space the `bounds` are given in — y down.
///
/// The crop (``PenImageTransform``) maps the image's unit square to the crop box's unit
/// square. The crop box is placed in the bounds by the ``PenImageFillMode/Placement``:
///
/// - **stretch:** the crop box is the bounds.
/// - **cover / contain:** the crop box takes the aspect of the *cropped* image — its sides are
///   the lengths, in image pixels, of the crop square's two axes mapped back into the image
///   (``cropBoxSize(imageSize:crop:)``) — and is scaled uniformly to cover or to fit the
///   bounds, centered.
///
/// The image is then drawn through the crop into the crop box (``imageTransform``). Only
/// contain clips to the crop box (``clipRect``); stretch and cover draw the whole image, and
/// the node's shape clips it as usual — which is how a cover crop shows image outside the crop
/// in an outer stroke. Cover first keeps the crop window inside the image
/// (``keptInsideImage(_:)``), so a cover paint never shows past the image's edge; stretch and
/// contain show nothing there.
public struct PenImagePlacement: Friendly {
    /// The crop box, in the bounds' space: the rect the crop's unit square is drawn into.
    public var cropBox: PenRect

    /// The map from the image's unit square — (0, 0) its top-left corner, (1, 1) its
    /// bottom-right — into the bounds' space: the crop box after ``crop``.
    public var imageTransform: PenLayoutEngine.PlaneTransform

    /// The rect drawing is clipped to on top of the node's own shape: the crop box for
    /// contain, `nil` for stretch and cover, which clip to nothing more.
    public var clipRect: PenRect?

    /// The crop the image is drawn through: the paint's transform (the identity when it has
    /// none), after cover's ``keptInsideImage(_:)``.
    public var crop: PenImageTransform

    /// Places an image of `imageSize` pixels in `bounds`.
    ///
    /// - Parameters:
    ///   - bounds: The rect the paint is laid out over — the node's box — in any space.
    ///   - imageSize: The image's size in pixels; only its aspect ratio matters.
    ///   - placement: How the crop box is sized into the bounds.
    ///   - transform: The crop; `nil` is no crop.
    /// - Returns: `nil` when nothing can be drawn: empty bounds, an empty image, or a crop that
    ///   collapses the image onto a line (a singular transform) or holds a non-finite number.
    public init?(
        bounds: PenRect,
        imageSize: PenSize,
        placement: PenImageFillMode.Placement,
        transform: PenImageTransform?
    ) {
        guard bounds.width > 0, bounds.height > 0, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let written = transform ?? .identity
        guard [written.a, written.b, written.c, written.d, written.tx, written.ty].allSatisfy(\.isFinite) else { return nil }
        let crop: PenImageTransform
        switch placement {
        case .stretch, .contain:
            crop = written
        case .cover:
            guard let kept = Self.keptInsideImage(written) else { return nil }
            crop = kept
        }
        guard crop.planeTransform.inverted() != nil else { return nil }

        let box: PenRect
        switch placement {
        case .stretch:
            box = PenRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
        case .cover, .contain:
            guard let size = Self.cropBoxSize(imageSize: imageSize, crop: crop) else { return nil }
            let scaleX = bounds.width / size.width, scaleY = bounds.height / size.height
            let scale = placement == .cover ? max(scaleX, scaleY) : min(scaleX, scaleY)
            let width = size.width * scale, height = size.height * scale
            box = PenRect(
                x: bounds.x + (bounds.width - width) / 2, y: bounds.y + (bounds.height - height) / 2,
                width: width, height: height
            )
        }
        cropBox = box
        imageTransform = PenLayoutEngine.PlaneTransform(a: box.width, d: box.height, tx: box.x, ty: box.y)
            .concatenating(crop.planeTransform)
        clipRect = placement == .contain ? box : nil
        self.crop = crop
    }

    /// Places an image paint of `imageSize` pixels in `bounds` by its own
    /// ``PenFill/PenImageFill/placement`` — cover when it has no mode — and transform.
    ///
    /// - Parameters:
    ///   - bounds: The rect the paint is laid out over — the node's box — in any space.
    ///   - imageSize: The image's size in pixels.
    ///   - fill: The image paint.
    /// - Returns: `nil` when nothing can be drawn; see
    ///   ``init(bounds:imageSize:placement:transform:)``.
    public init?(bounds: PenRect, imageSize: PenSize, fill: PenFill.PenImageFill) {
        self.init(bounds: bounds, imageSize: imageSize, placement: fill.placement, transform: fill.transform)
    }

    /// Cover's adjustment: `crop` with its window — the crop square mapped back into the
    /// image — kept inside the image.
    ///
    /// When the window's axis-aligned bounds are larger than the image on either axis, the
    /// window is shrunk about its center, uniformly, until its larger side fits. Its center is
    /// then moved as little as possible to bring the bounds inside the image. A window
    /// already inside the image is left alone; the result's shear and turn are the crop's.
    /// The adjustment is in the image's unit square, so it does not depend on the image's
    /// size.
    ///
    /// - Parameter crop: The paint's crop.
    /// - Returns: The adjusted crop, or `nil` when `crop` is singular or not finite.
    public static func keptInsideImage(_ crop: PenImageTransform) -> PenImageTransform? {
        let map = crop.planeTransform
        guard let inverse = map.inverted() else { return nil }
        let window = inverse.bounds(of: PenRect(x: 0, y: 0, width: 1, height: 1))
        let center = PenPoint(x: window.x + window.width / 2, y: window.y + window.height / 2)
        let shrink = 1 / max(1, window.width, window.height)
        let halfWidth = window.width * shrink / 2, halfHeight = window.height * shrink / 2
        let moved = PenPoint(
            x: min(max(center.x, halfWidth), 1 - halfWidth),
            y: min(max(center.y, halfHeight), 1 - halfHeight)
        )
        // The new window is the old one scaled by `shrink` about `center`, then moved to
        // `moved`; the crop maps an image point q back to where it sat in the old window.
        let adjusted = map
            .concatenating(PenLayoutEngine.PlaneTransform.translation(x: center.x, y: center.y))
            .concatenating(PenLayoutEngine.PlaneTransform(a: 1 / shrink, d: 1 / shrink))
            .concatenating(PenLayoutEngine.PlaneTransform.translation(x: -moved.x, y: -moved.y))
        return PenImageTransform(
            a: adjusted.a, b: adjusted.b, c: adjusted.c, d: adjusted.d, tx: adjusted.tx, ty: adjusted.ty
        )
    }

    /// The crop box's size before it is scaled into the bounds: the lengths, in image pixels,
    /// of the crop square's x and y axes mapped back into the image.
    ///
    /// For a crop that only scales, that is the image's size over the crop's scale on each
    /// axis — `[2, 0, 0, 1, …]` halves the width; a quarter turn swaps the sides; a shear
    /// lengthens the sheared axis. Cover and contain scale this size uniformly, so only its
    /// aspect ratio decides the crop box's shape.
    ///
    /// - Parameters:
    ///   - imageSize: The image's size in pixels.
    ///   - crop: The crop.
    /// - Returns: The size, or `nil` when `crop` is singular or the size is empty.
    public static func cropBoxSize(imageSize: PenSize, crop: PenImageTransform) -> PenSize? {
        guard let inverse = crop.planeTransform.inverted() else { return nil }
        let width = hypot(inverse.a * imageSize.width, inverse.b * imageSize.height)
        let height = hypot(inverse.c * imageSize.width, inverse.d * imageSize.height)
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
        return PenSize(width: width, height: height)
    }
}
