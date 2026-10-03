//
//  SwiftUINodeEmitter+Image.swift
//  Woodcase
//

import Foundation

extension SwiftUINodeEmitter {
    /// An image fill as a view that fills the box it is offered: the image, stretched, or
    /// scaled to cover or fit and centered — `cover` overflows the box, and the node's clip
    /// cuts it, as Pen draws it. A missing mode is cover (format 2.20; an older file's paint
    /// was given an explicit `stretch` when it was read). A cropped paint (one with a
    /// `transform`) is drawn through the support file's `PenImageCrop`, which places the crop
    /// box as ``PenImagePlacement`` does; for cover, the crop is written already kept inside
    /// the image (``PenImagePlacement/keptInsideImage(_:)``). A local file (beside the .pen
    /// file) is bundled into the package; a remote (`http`/`https`) one is fetched at *draw*
    /// time by `AsyncImage`, never downloaded while generating.
    ///
    /// `nil` for a fill with no image yet, and for one this emitter cannot draw at all (an
    /// absolute local path, reported in `unemitted`). `head` is the image expression when it
    /// is not the fill's own file — an image prop's name in a component's body; that path is
    /// never remote, since ``SwiftUIProp`` only binds a prop to a local image.
    func imageContent(_ fill: PenFill.PenImageFill, head: String? = nil, unemitted: inout [String]) -> SwiftUIPaintLayer.Content? {
        let expression: String
        if let head {
            expression = head
        } else {
            guard let url = fill.url else { return nil }
            if RemoteImageResolver.isRemote(url) {
                return Self.asyncImageView(url: url, fill: fill).map { .view($0) }
            }
            guard let name = Self.resourceName(url) else {
                unemitted.append("the image \(SwiftUILiteral.string(url)) (only images beside the .pen file are bundled)")
                return nil
            }
            expression = "Image(penResource: \(SwiftUILiteral.string(name)), bundle: .module)"
        }
        return Self.placedImage(expression, fill: fill).map { .view($0) }
    }

    /// The image `expression` placed by `fill`'s mode and crop, or `nil` for a crop that draws
    /// nothing (a singular `transform`).
    private static func placedImage(_ expression: String, fill: PenFill.PenImageFill) -> SwiftUIViewCode? {
        if let transform = fill.transform {
            return cropped(expression, placement: fill.placement, transform: transform)
        }
        let image = SwiftUIViewCode(head: expression).modified(".resizable()")
        switch fill.placement {
        case .stretch:
            return image
        case .cover:
            return placed(image.modified(".scaledToFill()"))
        case .contain:
            return placed(image.modified(".scaledToFit()"))
        }
    }

    /// The resource an image fill's URL is bundled as — its file name — or `nil` when the
    /// URL is not a file beside the .pen file.
    ///
    /// SwiftPM's `.process` flattens a target's resources into its bundle, where the support
    /// file's `Image(penResource:bundle:)` loads it. SwiftUI's own `Image(_:bundle:)` looks
    /// in asset catalogs, and on macOS does not find a loose file (measured: it draws nothing).
    /// A remote URL also fails this test — it is handled before ``imageContent(_:head:unemitted:)``
    /// ever calls it — so this stays the "local, bundleable" test alone.
    static func resourceName(_ url: String) -> String? {
        guard !url.isEmpty, !url.hasPrefix("/"), !url.contains("://") else { return nil }
        let name = URL(fileURLWithPath: url).lastPathComponent
        return name.isEmpty ? nil : name
    }

    /// A remote image fill drawn by SwiftUI's own `AsyncImage`: `url` is fetched by the
    /// running app, never by `woodcase generate swiftui` itself. Nothing is shown while it
    /// loads or if it fails — `Color.clear`, the same "nothing" an unloadable local image
    /// draws — though Pen itself draws a checkerboard placeholder there (measured with
    /// `scripts/pen-oracle`, see `project/2026-09-27-pen-missing-image-checkerboard.md`), a
    /// gap kept on purpose rather than built now.
    ///
    /// The resizable + scale modifiers — or the crop — apply inside the loaded `Image`'s own
    /// closure, `AsyncImage` itself carries none, since only `Image` has them; `cover`/`contain`
    /// with no crop center the whole `AsyncImage` in a `Color.clear` overlay, exactly as a
    /// bundled image's modes do.
    private static func asyncImageView(url: String, fill: PenFill.PenImageFill) -> SwiftUIViewCode? {
        let content: SwiftUIViewCode
        if let transform = fill.transform {
            guard let crop = cropped("image", placement: fill.placement, transform: transform) else { return nil }
            content = crop
        } else {
            var image = SwiftUIViewCode(head: "image").modified(".resizable()")
            switch fill.placement {
            case .stretch: break
            case .cover: image = image.modified(".scaledToFill()")
            case .contain: image = image.modified(".scaledToFit()")
            }
            content = image
        }
        var asyncImage = SwiftUIViewCode(
            head: "AsyncImage(url: URL(string: \(SwiftUILiteral.string(url))))",
            parameters: "image",
            body: [content]
        )
        asyncImage.trailingClosures = [SwiftUIViewCode.TrailingClosure(label: "placeholder", body: [SwiftUIViewCode(head: "Color.clear")])]
        guard fill.transform == nil, fill.placement != .stretch else { return asyncImage }
        return placed(asyncImage)
    }

    /// The image `expression` drawn through `PenImageCrop`: a canvas that fills the box it is
    /// offered and places the crop box from the image's own size, as ``PenImagePlacement``
    /// does. Cover's crop is written already kept inside the image. `nil` for a singular crop,
    /// which draws nothing.
    private static func cropped(
        _ expression: String,
        placement: PenImageFillMode.Placement,
        transform: PenImageTransform
    ) -> SwiftUIViewCode? {
        let crop: PenImageTransform
        switch placement {
        case .stretch, .contain:
            guard transform.planeTransform.inverted() != nil else { return nil }
            crop = transform
        case .cover:
            guard let kept = PenImagePlacement.keptInsideImage(transform) else { return nil }
            crop = kept
        }
        let coefficients = [("a", crop.a), ("b", crop.b), ("c", crop.c), ("d", crop.d), ("tx", crop.tx), ("ty", crop.ty)]
            .map { "\($0.0): \(SwiftUILiteral.number(cropCoefficient($0.1)))" }
            .joined(separator: ", ")
        return SwiftUIViewCode(
            head: "PenImageCrop(\(expression), placement: .\(placement.rawValue), crop: CGAffineTransform(\(coefficients)))"
        )
    }

    /// A crop coefficient rounded to twelve decimal places, so cover's arithmetic writes
    /// `1.3`, not `1.3000000000000003`.
    private static func cropCoefficient(_ value: Double) -> Double {
        let rounded = (value * 1e12).rounded() / 1e12
        return rounded == 0 ? 0 : rounded
    }

    /// `image` centered in the box it is offered, whatever size it takes itself.
    private static func placed(_ image: SwiftUIViewCode) -> SwiftUIViewCode {
        var view = SwiftUIViewCode(head: "Color.clear")
        view.modifiers.append(SwiftUIViewCode.Modifier(".overlay", content: [image]))
        return view
    }
}
