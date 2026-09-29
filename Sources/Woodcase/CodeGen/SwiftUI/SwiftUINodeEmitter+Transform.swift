//
//  SwiftUINodeEmitter+Transform.swift
//  Woodcase
//

import Foundation

extension SwiftUINodeEmitter {
    /// `view` flipped and rotated as `node` is, as Pen draws it: flip, then rotate.
    ///
    /// Pen turns and flips a node about its `x`/`y` anchor. A node placed by its own
    /// coordinates — in a `ZStack` (`container` is ``Container/absolute``), a group among
    /// them — is offset to that anchor, so it turns and flips about its top-leading corner
    /// and lands where Pen puts it, whatever its size. A node in a stack is placed by the
    /// stack instead, and Pen's layout grows its slot to the turned bounding box; so it
    /// turns about its center, and a node of fixed size — a turned fill child included, when
    /// ``turnedFillsSized(_:of:)`` fixed its box — is framed to that box, centered in
    /// it as the renderer centers it. A group in a stack sizes itself to that box
    /// (`PenGroupFlow`) and turns about its center too. `rotationEffect` moves pixels but not layout, which is
    /// why the frame is needed there.
    ///
    /// Pen's rotation is counter-clockwise and SwiftUI's clockwise, so the angle is negated.
    /// A rotation variable is read through the theme like any other number; the box a fixed-size
    /// stack child is framed to (below) is then the same trigonometry read at runtime, since the
    /// angle it turns to is no longer known when this code is generated.
    func transformed(_ view: SwiftUIViewCode, _ node: PenNode, in container: Container) -> SwiftUIViewCode {
        var unemitted: [String] = []
        let rotation = number(node.common.rotation, unemitted: &unemitted)
        warnUnemitted(node, unemitted)
        let flipX = node.common.flipX?.literalValue == true
        let flipY = node.common.flipY?.literalValue == true
        let isGroup = if case .group = node.kind { true } else { false }
        let isAnchored = (isGroup && !Self.isFlow(container)) || container == .absolute
        let anchor = isAnchored ? ", anchor: .topLeading" : ""
        var view = view
        if flipX || flipY {
            view = view.modified(".scaleEffect(x: \(flipX ? -1 : 1), y: \(flipY ? -1 : 1)\(anchor))")
        }
        guard let rotation, !rotation.isZero else { return view }
        view = view.modified(".rotationEffect(.degrees(\(rotation.negated.code))\(anchor))")
        if !isAnchored,
           case let .fixed(width) = declaredSizing(node, axis: .width),
           case let .fixed(height) = declaredSizing(node, axis: .height)
        {
            view = view.modified(rotatedFrame(rotation, width: width, height: height))
        }
        return view
    }

    /// The `.frame(width:height:)` that fits a fixed-size box turned by `rotation`, so a
    /// stack gives it the room Pen's layout would: the exact box, rounded to a millionth of
    /// a point so a quarter turn reads `40`, not `40.000000000000005`, for a literal angle
    /// known now; the same trigonometry written as an expression, read at draw time, for one
    /// the theme sets — `cos`/`sin`/`abs` resolve under a plain `import SwiftUI`.
    private func rotatedFrame(_ rotation: SwiftUINumber, width: Double, height: Double) -> String {
        guard let degrees = rotation.literal else {
            let radians = "(\(rotation.code) * Double.pi / 180)"
            let turnedWidth = "abs(cos(\(radians))) * \(SwiftUILiteral.number(width)) + abs(sin(\(radians))) * \(SwiftUILiteral.number(height))"
            let turnedHeight = "abs(sin(\(radians))) * \(SwiftUILiteral.number(width)) + abs(cos(\(radians))) * \(SwiftUILiteral.number(height))"
            return ".frame(width: \(turnedWidth), height: \(turnedHeight))"
        }
        let radians = degrees * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))
        let round = { (value: Double) in SwiftUILiteral.number((value * 1e6).rounded() / 1e6) }
        let box = (width: width * cosine + height * sine, height: width * sine + height * cosine)
        return ".frame(width: \(round(box.width)), height: \(round(box.height)))"
    }

    /// A frame's flow children, each turned `fill_container` child's box written as the
    /// fixed size its container's numbers give it, as are the fills sharing with it
    /// (``TurnedFillSizes``): a stack gives a flexible frame what is left after the others,
    /// not Pen's share of an unturned box, and frames only a fixed-size turned node to its
    /// turned bounds. A turned fill child those numbers do not fix is warned about and keeps
    /// the unturned slot of a flexible frame.
    func turnedFillsSized(_ children: [PenNode], of frame: PenNode.FrameData) -> [PenNode] {
        let sizes = TurnedFillSizes(container: frame)
        for child in children {
            guard let reason = sizes.unresolved[child.id] else { continue }
            diagnostics?.warn(
                reason.warning(label: child.common.name ?? child.id, emitter: "SwiftUI"), stage: .codeGen, nodeID: child.id
            )
        }
        return children.map(sizes.sized)
    }
}
