//
//  PenImageTransform+CropRect.swift
//  Woodcase
//

import Foundation

public extension PenImageTransform {
    /// The crop that shows the pixel rect `rect` of an image of `imageSize` pixels:
    /// `[W/cw, 0, 0, H/ch, -cx/cw, -cy/ch]` for the rect `(cx, cy, cw, ch)` of a `W × H`
    /// image.
    ///
    /// The transform maps the image's unit square onto the crop box's, so its numbers
    /// are fractions, not pixels: the scales are how many times the crop fits across the
    /// image, the translation is in widths and heights of the crop. That meaning is the
    /// same in every ``PenImageFillMode``; what differs is where the crop box lands
    /// (``PenImagePlacement``):
    ///
    /// - **stretch** shows exactly `rect`, stretched over the node's box.
    /// - **contain** shows exactly `rect`, scaled to fit inside the box and clipped to it.
    /// - **cover** shows `rect` scaled to cover the box — exactly `rect` when the box has
    ///   its aspect ratio, its middle otherwise — and first moves or shrinks a rect that
    ///   leaves the image back inside it.
    ///
    /// Since it is in fractions, the same transform crops the same part of any image of
    /// the same aspect ratio, which is why replacing an image keeps its crop.
    ///
    /// ```swift
    /// // The right half of a 256 × 128 image: [2, 0, 0, 1, -1, 0].
    /// let crop = PenImageTransform(cropping: PenRect(x: 128, y: 0, width: 128, height: 128),
    ///                              imageSize: PenSize(width: 256, height: 128))
    /// ```
    ///
    /// - Parameters:
    ///   - rect: The part of the image to show, in its pixels, y down from its top-left
    ///     corner. It may reach past the image's edge.
    ///   - imageSize: The image's size in pixels.
    /// - Returns: `nil` when `rect` or `imageSize` is empty or holds a non-finite number.
    init?(cropping rect: PenRect, imageSize: PenSize) {
        let numbers = [rect.x, rect.y, rect.width, rect.height, imageSize.width, imageSize.height]
        guard numbers.allSatisfy(\.isFinite), rect.width > 0, rect.height > 0,
              imageSize.width > 0, imageSize.height > 0
        else { return nil }
        self.init(
            a: imageSize.width / rect.width, b: 0, c: 0, d: imageSize.height / rect.height,
            tx: -rect.x / rect.width, ty: -rect.y / rect.height
        )
    }

    /// The pixel rect of an image of `imageSize` pixels this crop shows: the inverse of
    /// ``init(cropping:imageSize:)``. The identity gives the whole image.
    ///
    /// This is the crop as written, before cover keeps it inside the image
    /// (``PenImagePlacement/keptInsideImage(_:)``).
    ///
    /// - Parameter imageSize: The image's size in pixels.
    /// - Returns: The rect, or `nil` when the crop shears or turns the image (no
    ///   axis-aligned rect describes it), when it is singular or flips an axis, or when
    ///   a number is not finite.
    func cropRect(imageSize: PenSize) -> PenRect? {
        guard b == 0, c == 0, a > 0, d > 0,
              [a, d, tx, ty, imageSize.width, imageSize.height].allSatisfy(\.isFinite)
        else { return nil }
        let width = imageSize.width / a, height = imageSize.height / d
        return PenRect(x: -tx * width, y: -ty * height, width: width, height: height)
    }
}
