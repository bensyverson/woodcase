//
//  ReactEmitter+FrameFill.swift
//  Woodcase
//

extension ReactEmitter {
    /// A frame's paint: the background declarations on the frame itself, and the layers
    /// over them that draw what a background cannot (``PaintSplit``).
    struct FrameFill: Friendly {
        /// The frame's own background, as ``FillLayer/Declaration``s.
        var background: [FillLayer.Declaration]
        /// The layers over the background, bottom first.
        var layers: [FillLayer]

        /// The background as the `(property, value)` pairs the emitter writes.
        var styles: [(String, String)] {
            background.map { ($0.property, $0.value) }
        }
    }

    /// The paint of `node`, a frame: its fills, or — when an image prop targets it — the
    /// prop's image placed by the first fill's mode and crop.
    ///
    /// - Parameters:
    ///   - node: The frame.
    ///   - data: Its data.
    ///   - component: The component being emitted, whose props may target the frame.
    ///   - beneathChildren: Whether layers must paint under the frame's children.
    ///   - ctx: The emission context.
    static func frameFill(
        _ node: PenNode,
        data: PenNode.FrameData,
        component: ComponentDefinition,
        beneathChildren: Bool,
        ctx: EmitContext
    ) -> FrameFill {
        let box = FillBox(width: data.width, height: data.height)
        let imageProp = component.props.first { $0.type == .imageURL && $0.targetNodeID == node.id }
        var styles: [(String, String)] = []
        var layers: [FillLayer] = []
        if let imageProp {
            if let fill = data.fills?.all.first, isCroppedImage(fill) {
                layers = fillLayers([fill], box: box, beneathChildren: beneathChildren, imageHref: "{\(imageProp.name)}", ctx: ctx)
            } else {
                styles.append(("backgroundImage", "`url('${\(imageProp.name)}')`"))
                // Sizing and position from the original fill's mode
                if let fills = data.fills, let fill = fills.all.first, case let .image(img) = fill {
                    styles.append(("backgroundSize", "\"\(cssImageSize(img.placement))\""))
                    styles.append(("backgroundPosition", "\"center\""))
                    styles.append(("backgroundRepeat", "\"no-repeat\""))
                }
            }
        } else {
            let split = PaintSplit(data.fills)
            if let background = split.backgroundFills {
                styles = emitFillStyles(background, box: box, ctx: ctx)
            }
            layers = fillLayers(split.layered, box: box, beneathChildren: beneathChildren, ctx: ctx)
        }
        return FrameFill(background: FillLayer(styles).declarations, layers: layers)
    }
}
