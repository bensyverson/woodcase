//
//  ReactEmitter+FillLayers.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    /// The layers that draw a box's `layered` paints over its background, bottom first.
    ///
    /// Each covers the node's box and clips to its shape (`borderRadius: inherit`). A crop's
    /// layer holds its ``imageCropElement(_:href:frame:ctx:)`` and carries the paint's
    /// opacity and blend mode; any other paint is the layer's own background.
    ///
    /// - Parameters:
    ///   - layered: The paints, bottom first (``PaintSplit/layered``).
    ///   - box: The node's box, which sizes a mesh raster.
    ///   - beneathChildren: Whether the layers must paint under the node's children: they
    ///     then sit at `zIndex: -1`, and the host must isolate.
    ///   - imageHref: The image expression for the first paint when an image prop drives it.
    ///   - ctx: The emission context.
    static func fillLayers(
        _ layered: [PenFill],
        box: FillBox,
        beneathChildren: Bool,
        imageHref: String? = nil,
        ctx: EmitContext
    ) -> [FillLayer] {
        layered.enumerated().compactMap { index, fill -> FillLayer? in
            guard fill.isEnabled else { return nil }
            var styles: [(String, String)] = [("position", "\"absolute\""), ("inset", "0"), ("borderRadius", "\"inherit\"")]
            let content: String?
            if case let .image(image) = fill, image.transform != nil {
                guard let element = imageCropElement(image, href: index == 0 ? imageHref : nil, ctx: ctx) else { return nil }
                content = element
                styles.append(("overflow", "\"hidden\""))
                styles.append(contentsOf: cropLayerPaintStyles(image))
            } else {
                let paint = emitFillStyles(.single(fill), box: box, ctx: ctx)
                guard !paint.isEmpty else { return nil }
                styles.append(contentsOf: paint)
                content = nil
            }
            if beneathChildren {
                styles.append(("zIndex", "-1"))
            }
            styles.append(("pointerEvents", "\"none\""))
            return FillLayer(styles, content: content)
        }
    }

    /// The opacity and blend mode of a crop's layer: the paint's own, which a CSS background
    /// layer cannot carry.
    static func cropLayerPaintStyles(_ image: PenFill.PenImageFill) -> [(String, String)] {
        var styles: [(String, String)] = []
        if let opacity = image.opacity {
            styles.append(("opacity", emitPenValue(opacity)))
        }
        if let mode = image.blendMode, mode != .normal {
            styles.append(("mixBlendMode", "\"\(blendModeToCSSValue(mode))\""))
        }
        return styles
    }

    /// Moves the inset entries of the box's `boxShadow` — its inner and centered strokes and
    /// inner shadows — to a layer over `layers`, since a box's own `box-shadow` paints
    /// under every child element and so under the layers. The outer entries stay on the
    /// box. Returns `layers` with that layer appended, or unchanged when there are no
    /// layers or no inset entries.
    static func liftingInsetShadows(
        _ styles: inout [(String, String)],
        over layers: [FillLayer],
        beneathChildren: Bool
    ) -> [FillLayer] {
        guard !layers.isEmpty, let index = styles.firstIndex(where: { $0.0 == "boxShadow" }) else { return layers }
        let value = styles[index].1
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return layers }
        let entries = topLevelEntries(String(value.dropFirst().dropLast()))
        let inset = entries.filter { $0.hasPrefix("inset ") }
        guard !inset.isEmpty else { return layers }
        let outer = entries.filter { !$0.hasPrefix("inset ") }
        if outer.isEmpty {
            styles.remove(at: index)
        } else {
            styles[index].1 = "\"\(outer.joined(separator: ", "))\""
        }
        var cap: [(String, String)] = [("position", "\"absolute\""), ("inset", "0"), ("borderRadius", "\"inherit\"")]
        cap.append(("boxShadow", "\"\(inset.joined(separator: ", "))\""))
        if beneathChildren {
            cap.append(("zIndex", "-1"))
        }
        cap.append(("pointerEvents", "\"none\""))
        return layers + [FillLayer(cap)]
    }

    /// The comma-separated entries of a CSS list, split only at commas outside parentheses
    /// (`rgba(…)`, `var(…)`), each trimmed.
    static func topLevelEntries(_ list: String) -> [String] {
        var entries: [String] = []
        var current = ""
        var depth = 0
        for character in list {
            switch character {
            case "(": depth += 1
            case ")": depth -= 1
            case "," where depth == 0:
                entries.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            default: break
            }
            current.append(character)
        }
        entries.append(current.trimmingCharacters(in: .whitespaces))
        return entries.filter { !$0.isEmpty }
    }
}
