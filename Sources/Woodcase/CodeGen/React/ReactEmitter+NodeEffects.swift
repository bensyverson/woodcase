//
//  ReactEmitter+NodeEffects.swift
//  Woodcase
//

extension ReactEmitter {
    /// A node's effects as the renderer draws them, picked out once for the CSS every kind
    /// of node writes (``PenRenderer``'s rules; <doc:PenRendering>, *Effects*).
    ///
    /// Every enabled shadow is drawn, in array order — the first at the bottom — each with
    /// its own blend mode; the first enabled layer blur with a radius, and the first enabled
    /// background blur, are drawn, and any others are not.
    struct NodeEffects: Friendly {
        /// The enabled outer shadows, in array order: the first is drawn at the bottom.
        let outerShadows: [PenEffect.PenShadowEffect]
        /// The enabled inner shadows, in array order: the first is drawn at the bottom.
        let innerShadows: [PenEffect.PenShadowEffect]
        /// The layer blur the renderer draws: the first enabled one with a radius.
        let layerBlur: PenEffect.PenBlurEffect?
        /// The background blur the renderer draws: the first enabled one with a radius.
        let backgroundBlur: PenEffect.PenBackgroundBlurEffect?

        /// Picks the drawn effects out of a node's `effect` list.
        ///
        /// - Parameter effects: The node's effects, if it has any.
        init(_ effects: PenEffects?) {
            let all = effects?.all ?? []
            let shadows = all.compactMap { effect -> PenEffect.PenShadowEffect? in
                guard case let .shadow(shadow) = effect, shadow.enabled?.literalValue != false else { return nil }
                return shadow
            }
            outerShadows = shadows.filter { $0.shadowType != .inner }
            innerShadows = shadows.filter { $0.shadowType == .inner }
            layerBlur = all.lazy.compactMap { effect -> PenEffect.PenBlurEffect? in
                guard case let .blur(blur) = effect, blur.enabled?.literalValue != false,
                      (blur.radius?.literalValue ?? 0) > 0
                else { return nil }
                return blur
            }.first
            backgroundBlur = all.lazy.compactMap { effect -> PenEffect.PenBackgroundBlurEffect? in
                guard case let .backgroundBlur(blur) = effect, blur.enabled?.literalValue != false,
                      (blur.radius?.literalValue ?? 0) > 0
                else { return nil }
                return blur
            }.first
        }

        /// Whether any drawn shadow composites with a blend mode other than normal.
        var hasBlendedShadow: Bool {
            (outerShadows + innerShadows).contains { $0.isBlended }
        }

        /// The outer shadows as a CSS shadow list — `box-shadow`'s or `text-shadow`'s —
        /// top first, since CSS paints the first entry on top and Pen the last.
        var outerShadowList: [String] {
            outerShadows.reversed().map(\.cssShadow)
        }

        /// The outer shadows as a box-shadow list, top first, each cast by the box grown
        /// by `spread` (``ReactEmitter/shadowSpread(_:)``).
        func outerShadowList(spread: SymbolicLength) -> [String] {
            outerShadows.reversed().map { $0.cssShadow(spread: spread) }
        }

        /// The inner shadows as `inset` box-shadow entries, top first.
        var innerShadowList: [String] {
            innerShadows.reversed().map { "inset \($0.cssShadow)" }
        }

        /// The outer shadows as `drop-shadow()` filter functions, the top shadow first.
        ///
        /// A filter list applies left to right, and each `drop-shadow` sits under everything
        /// before it, so the shadow Pen draws on top is applied first. Each also shadows the
        /// shadows applied before it — an approximation where several overlap. Unlike a
        /// box or text shadow's, a `drop-shadow`'s blur length is the Gaussian's standard
        /// deviation (``PenEffect/PenShadowEffect/cssDropShadow``).
        var dropShadowFunctions: [String] {
            outerShadows.reversed().map { "drop-shadow(\($0.cssDropShadow))" }
        }

        /// The layer blur as a `blur()` filter function: CSS takes the Gaussian's standard
        /// deviation, half of Pen's radius, fraction and all.
        var blurFunction: String? {
            layerBlur?.radius?.literalValue.map { "blur(\(formatPx($0 / 2)))" }
        }

        /// The background blur's `blur()`, at half its radius, or `nil` when there is none.
        var backdropFunction: String? {
            backgroundBlur?.radius?.literalValue.map { "blur(\(formatPx($0 / 2)))" }
        }
    }
}
