//
//  ReactRenderWebViewTests+Baselines.swift
//  WoodcaseTests
//

#if os(macOS)

    @testable import Woodcase

    extension ReactRenderWebViewTests {
        /// Why a board is not held to CG + 1.0: each a way the emitted React, or the harness
        /// page, draws differently from Pen, found by looking at the board beside Pen's export.
        enum Gap: String, Friendly {
            /// Pen rounds an auto-width text's width up to a whole point and CSS keeps it
            /// fractional, so a row of labels drifts right: the error grows along the row and
            /// the board aligns best a device pixel right (leaf BpaSrF, not measured further).
            case autoTextWidth = "an auto-width label's width stays fractional where Pen rounds it up, and a row of them drifts"
            /// `backdropFilter` is emitted, but the WebKit snapshot does not draw it.
            case backdropNotCaptured = "backdropFilter is emitted, but the WebKit snapshot draws no backdrop-filter"
            /// A group's outer shadow is a `drop-shadow` of what it paints, not Pen's silhouette:
            /// a CSS limit, kept by Ben's ruling of 2026-09-27.
            case groupDropShadow = "a group's shadow is a drop-shadow of its painted content: translucent children cast a fainter shadow that shows through them, and a line, a child's own shadow and a frame child's overhang cast one too"
            /// A group's inner shadow is not written, and generating it warns: a CSS limit.
            case groupInnerShadow = "React writes no inner shadow on a group, and warns: CSS has no filter for one"
            /// React writes no inner shadow on text, and generating it warns: a CSS limit, kept
            /// by Ben's ruling of 2026-09-27; CG and SwiftUI draw it since vVgtB2.
            case textInnerShadow = "React writes no inner shadow on text, and warns: CSS has none; CG and SwiftUI draw it"
            /// A turned `fill_container` child whose box only the running layout knows keeps the
            /// unturned slot of an ordinary fill, and generating it warns (`TurnedFillSizes`).
            case turnedFillUnresolved = "a turned fill_container child whose box only the layout knows keeps its unturned slot, and warns: flexbox cannot fill an unturned box and allocate its turned bounds"
        }

        /// Boards not held to CG + 1.0, keyed by ``SwiftUIRenderBoard/id``, with the MAE each
        /// measured and why. Each fails only past its MAE + ``baselineTolerance``.
        ///
        /// Measured 2026-09-27 with `swift test -j 3 --filter ReactRenderWebViewTests` (WebKit
        /// on macOS 27.0, the harness naming its faces by family, leaf vXVtb1). The SVG fills were re-measured the same way
        /// with leaves bLU8nV and Qfm8i8. The stroke-placement boards (per-side strokes and
        /// shapes, arc donuts, `render-strokes-and-paths`, the inner shadows under a stroke)
        /// left this table with leaves 50MfO5, SctC0l and hPsLl7: each now lands within CG + 1.0.
        /// The text, shadow and group-shadow entries were re-measured the same way with leaves
        /// Gmh2sB, 0M8jRo, 3Xbv46 and RgeMUN, which moved them.
        /// The 29 off-axis linear, angular and turned or sized radial `render-gradient-geometry`
        /// boards left with leaf VtOM4W (4.3–60.4 to 0.09–0.26, CG 0.03–0.22). The sizing
        /// fallbacks and the unstretched column left with leaf MY1B1R (`layout-fit-content-fallback`
        /// 243.750, `layout-fill-fallback` 12.381 and `layout-deep-nesting` 1.288 to 0.000–0.108,
        /// CG 0.000), and the mesh boards with leaf 3n7gRZ, which bakes each raster at 2 px per
        /// point (`render-mesh-gradients-mfold` and the malformed points 1.3–2.7 to 0.30–0.60,
        /// each equal to CG): the "black outside the fold" the fold's entry named was Pen's
        /// transparent background; the gap was the raster alone.
        /// The ten `render-font-faces` boards left with leaf qtWkxA, when the page loaded the
        /// committed Google faces and the CG side registered them before measuring, whichever
        /// suite ran first (5.2–24.6 to 1.23–1.81, under CG's 2.20–2.70: ``ceilings``), and `parser-icon-font` moved from 13.478 to
        /// 2.953 with each icon family's own font. Leaf Mu4JsL moved `render-transforms-and-effects`
        /// (35.845 to 0.634, its turned flex child's slot grown to the turned bounds) and leaf
        /// AyTAji `parser-icon-font` (2.953 to 0.410, Material Symbols at Pen's weight) to
        /// ``ceilings``, each now under CG's MAE.
        static let baselines: [String: (mae: Double, why: Gap)] = [
            // Measured 2026-09-28 (leaf ozlazY, same command): a cross-axis fill in a row that
            // fits its content; every other `render-turned-fill` board gates at CG + 1.0.
            "render-turned-fill-row-cross-fit-30": (3.708, .turnedFillUnresolved),
            // Leaf BpaSrF put each text's first baseline on Pen's whole point, and the other
            // layout-text boards left for the ceilings or CG + 1.0 (1.8–4.4 before: every text
            // sat a device pixel off). This one keeps a horizontal drift.
            "layout-text-chips": (2.638, .autoTextWidth),
            "blur3": (6.068, .backdropNotCaptured),
            "render-background-blur-flip": (5.359, .backdropNotCaptured),
            "render-background-blur-r8": (1.703, .backdropNotCaptured),
            // Group shadows are drop-shadows since leaf 0M8jRo; `group-outer` (0.482) and
            // `group-child-shadow` (1.124) now gate at CG + 1.0. Before, with no shadow at all:
            // translucent 10.713, stroke-path 5.976, inner 6.739, nested 9.356 and frame-child
            // 4.399, which the drop-shadow of the frame's overhanging child makes worse.
            "render-group-shadows-group-translucent": (7.153, .groupDropShadow),
            "render-group-shadows-group-stroke-path": (1.614, .groupDropShadow),
            "render-group-shadows-group-inner": (6.739, .groupInnerShadow),
            "render-group-shadows-group-nested": (1.555, .groupDropShadow),
            "render-group-shadows-group-frame-child": (6.498, .groupDropShadow),
            "render-text-shadows-text-inner": (5.094, .textInnerShadow),
            "render-text-shadows-text-inner-soft": (3.024, .textInnerShadow),
            "render-text-shadows-text-inner-outer": (3.775, .textInnerShadow),
            "render-text-shadows-text-inner-wrap": (3.842, .textInnerShadow),
            "render-text-shadows-text-inner-unfilled": (9.638, .textInnerShadow),
            "render-text-shadows-text-inner-translucent": (7.358, .textInnerShadow),
        ]
    }

#endif
