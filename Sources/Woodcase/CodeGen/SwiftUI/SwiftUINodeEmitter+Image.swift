//
//  SwiftUINodeEmitter+Image.swift
//  Woodcase
//

import Foundation

extension SwiftUINodeEmitter {
    /// An image fill as a view that fills the box it is offered: the image, stretched, or
    /// scaled to fill or fit and centered — `fill` overflows the box, and the node's clip
    /// cuts it, as Pen draws it. A local file (beside the .pen file) is bundled into the
    /// package; a remote (`http`/`https`) one is fetched at *draw* time by `AsyncImage`,
    /// never downloaded while generating.
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
                return .view(Self.asyncImageView(url: url, mode: fill.mode ?? .stretch))
            }
            guard let name = Self.resourceName(url) else {
                unemitted.append("the image \(SwiftUILiteral.string(url)) (only images beside the .pen file are bundled)")
                return nil
            }
            expression = "Image(penResource: \(SwiftUILiteral.string(name)), bundle: .module)"
        }
        let image = SwiftUIViewCode(head: expression).modified(".resizable()")
        switch fill.mode ?? .stretch {
        case .stretch:
            return .view(image)
        case .fill:
            return .view(Self.placed(image.modified(".scaledToFill()")))
        case .fit:
            return .view(Self.placed(image.modified(".scaledToFit()")))
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
    /// The resizable + scale modifiers apply inside the loaded `Image`'s own closure —
    /// `AsyncImage` itself carries none, since only `Image` has them — and `fill`/`fit`
    /// center the whole `AsyncImage` in a `Color.clear` overlay, exactly as a bundled image's
    /// modes do.
    private static func asyncImageView(url: String, mode: PenImageFillMode) -> SwiftUIViewCode {
        var content = SwiftUIViewCode(head: "image").modified(".resizable()")
        switch mode {
        case .stretch: break
        case .fill: content = content.modified(".scaledToFill()")
        case .fit: content = content.modified(".scaledToFit()")
        }
        var asyncImage = SwiftUIViewCode(
            head: "AsyncImage(url: URL(string: \(SwiftUILiteral.string(url))))",
            parameters: "image",
            body: [content]
        )
        asyncImage.trailingClosures = [SwiftUIViewCode.TrailingClosure(label: "placeholder", body: [SwiftUIViewCode(head: "Color.clear")])]
        switch mode {
        case .stretch: return asyncImage
        case .fill, .fit: return placed(asyncImage)
        }
    }

    /// `image` centered in the box it is offered, whatever size it takes itself.
    private static func placed(_ image: SwiftUIViewCode) -> SwiftUIViewCode {
        var view = SwiftUIViewCode(head: "Color.clear")
        view.modifiers.append(SwiftUIViewCode.Modifier(".overlay", content: [image]))
        return view
    }
}
