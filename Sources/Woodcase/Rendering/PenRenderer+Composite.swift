//
//  PenRenderer+Composite.swift
//  Woodcase
//

import CoreGraphics

/// How a node with opacity or a blend mode composites with what lies beneath it.
///
/// A node at a blend mode, or below full opacity, is one isolated group, as CSS's
/// `mix-blend-mode` and Figma blend one: its paints, effects and children are drawn at the
/// normal blend and full alpha onto a transparent layer — each paint keeping its own blend
/// inside — and the layer is then blended with the backdrop at the node's mode and opacity.
/// For a node of a single paint that is the paint drawn at the node's mode, so the node's
/// mode wins over the paint's own (integrator's ruling, 2026-10-20, under Ben's W3C ruling).
extension PenRenderer {
    /// The layer a node opened, closed by ``endComposite(_:in:)``.
    enum NodeComposite {
        /// A Core Graphics transparency layer, composited at the alpha and blend mode the
        /// graphics state held when it began.
        case transparencyLayer
        /// A per-pixel layer, for a node whose blend — or one inside it — Core Graphics
        /// draws inexactly.
        case pixelLayer(PenBlendLayer)
    }

    /// Opens the node's group layer, or returns `nil` when it composites as it draws.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - opacity: Its effective opacity, overrides applied.
    ///   - context: The context it draws into.
    static func beginComposite(for node: PenNode, opacity: Double?, in context: CGContext) -> NodeComposite? {
        // Normal, and an unknown mode, which draws as normal, need no layer of their own.
        let mode = blendMode(for: node).flatMap { $0.compositing == .coreGraphics && $0.cgBlendMode == .normal ? nil : $0 }
        let alpha = opacity.map { min(max($0, 0), 1) } ?? 1
        guard mode != nil || alpha < 1 else { return nil }
        // A Core Graphics layer hides its pixels until it ends, so a per-pixel blend at or
        // inside the node needs the node's own layer per pixel too.
        if mode?.compositing == .perPixel || containsPerPixelBlend(node),
           let layer = PenBlendLayer(mode: mode ?? .normal, opacity: alpha, in: context)
        {
            return .pixelLayer(layer)
        }
        if alpha < 1 {
            context.setAlpha(CGFloat(alpha))
        }
        if let mode {
            context.setBlendMode(mode.cgBlendMode)
        }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setAlpha(1)
        context.setBlendMode(.normal)
        return .transparencyLayer
    }

    /// Closes a layer ``beginComposite(for:opacity:in:)`` opened, blending it onto what lies
    /// beneath.
    static func endComposite(_ composite: NodeComposite, in context: CGContext) {
        switch composite {
        case .transparencyLayer:
            context.endTransparencyLayer()
        case let .pixelLayer(layer):
            layer.composite(in: context)
        }
    }

    /// Opens the isolated group a node's paint stack draws in when any of its paints blends,
    /// or returns `nil` when none does and the paints draw straight onto the backdrop.
    ///
    /// The group starts transparent, so a blended paint blends only with the paints drawn
    /// beneath it inside, and the group then composites at the normal blend (``PenPaintStack``).
    /// It is a per-pixel layer when a paint or inner shadow inside blends per pixel — a Core
    /// Graphics layer would hide the pixels that blend reads — and a Core Graphics
    /// transparency layer otherwise, which is also the fallback where the context's pixels
    /// cannot be read.
    ///
    /// - Parameters:
    ///   - stack: The node's paints.
    ///   - innerShadows: The inner shadows drawn among them.
    ///   - context: The context they draw into.
    static func beginPaintStack(
        _ stack: PenPaintStack, innerShadows: [PenCastShadow], in context: CGContext
    ) -> NodeComposite? {
        guard stack.blends else { return nil }
        let shadowsPerPixel = innerShadows.contains { $0.shadow.blendMode?.compositing == .perPixel }
        if stack.blendsPerPixel || shadowsPerPixel, let layer = PenBlendLayer(mode: .normal, opacity: 1, in: context) {
            return .pixelLayer(layer)
        }
        // The graphics state is at full alpha and the normal blend here: a node's own
        // composite resets both once its layer is open.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        return .transparencyLayer
    }

    /// Whether any paint, shadow or descendant of `node` blends by a per-pixel mode.
    static func containsPerPixelBlend(_ node: PenNode) -> Bool {
        var pending = [node]
        while let next = pending.popLast() {
            if blendModes(of: next).contains(where: { $0.compositing == .perPixel }) {
                return true
            }
            switch next.kind {
            case let .frame(data): pending.append(contentsOf: data.children ?? [])
            case let .group(data): pending.append(contentsOf: data.children ?? [])
            default: break
            }
        }
        return false
    }

    /// Every blend mode `node` itself draws with: its own, its fills', its stroke's and its
    /// shadows'.
    private static func blendModes(of node: PenNode) -> [PenBlendMode] {
        let paints = (fills(for: node)?.all ?? []) + (strokePaints(for: node)?.all ?? [])
        let shadows: [PenBlendMode] = effects(for: node)?.all.compactMap {
            if case let .shadow(shadow) = $0 { return shadow.blendMode }
            return nil
        } ?? []
        return [blendMode(for: node)].compactMap(\.self) + paints.compactMap(\.blendMode) + shadows
    }

    /// The node's stroke paints, for the kinds that carry a stroke.
    static func strokePaints(for node: PenNode) -> PenFills? {
        switch node.kind {
        case let .frame(data): data.stroke
        case let .rectangle(data): data.stroke
        case let .ellipse(data): data.stroke
        case let .polygon(data): data.stroke
        case let .line(data): data.stroke
        case let .path(data): data.stroke
        case let .browser(data): data.stroke
        default: nil
        }
    }
}
