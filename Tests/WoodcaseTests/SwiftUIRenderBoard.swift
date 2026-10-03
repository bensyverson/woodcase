//
//  SwiftUIRenderBoard.swift
//  WoodcaseTests
//

// macOS-only, like the render test it feeds: the CG side renders with Core Graphics.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// One board the SwiftUI render test compiles, renders and measures: a fixture's only
    /// top-level frame against `<fixture>.png`, or one artboard of a many-board fixture
    /// against Pen's export of it — `<fixture>-<artboard>@2x.png`, `<fixture>-<artboard>.png`
    /// or `<artboard>.png`, the first that exists.
    ///
    /// A board is rendered under the light color scheme unless it names another; a dark
    /// board may be measured against another artboard's export — a light artboard drawn
    /// dark against its twin that Pen exported under `theme: {mode: dark}`.
    struct SwiftUIRenderBoard: Friendly, CustomTestStringConvertible {
        /// The color scheme a board is rendered under.
        enum ColorScheme: String, Friendly {
            /// SwiftUI's `.light`, the harness's default.
            case light
            /// SwiftUI's `.dark`.
            case dark
        }

        /// The fixture file, without `.pen`.
        var fixture: String

        /// The top-level frame's name, or `nil` for a fixture with one board.
        var artboard: String?

        /// Pen's export of a one-board fixture, when it is not named for the fixture.
        var reference: String?

        /// The artboard whose export this board is measured against, and which the CG
        /// renderer draws, when it is not the board's own.
        var referenceArtboard: String?

        /// The color scheme SwiftUI renders the board under.
        var colorScheme: ColorScheme = .light

        /// The fixtures with effects and transforms, one board each.
        static let effectFixtures = ["render-transforms-and-effects", "blur1", "blur2", "blur3"]

        /// The one-board fixtures of strokes, paths and icons, each with Pen's export.
        static let shapeBoards = [
            SwiftUIRenderBoard(fixture: "render-strokes-and-paths"),
            SwiftUIRenderBoard(fixture: "parser-icon-font", reference: "icon-font-test"),
        ]

        /// The one-board text fixtures outside ``SwiftUIFixtures/names``: Inter at eight
        /// sizes with no `lineHeight`, one and three lines each, which pins the natural pitch.
        static let textBoards = [SwiftUIRenderBoard(fixture: "text-natural-line-height")]

        /// Boards rendered under the dark color scheme: `swiftui-color-scheme`'s unfilled
        /// text and icon, which Pen draws as nothing in any scheme, and its themed mesh,
        /// whose `mode` axis the scheme selects, against the twin Pen exported dark.
        static let darkBoards = [
            SwiftUIRenderBoard(fixture: "swiftui-color-scheme", artboard: "unfilled", colorScheme: .dark),
            SwiftUIRenderBoard(
                fixture: "swiftui-color-scheme", artboard: "themed-mesh", referenceArtboard: "themed-mesh-dark", colorScheme: .dark
            ),
        ]

        /// The fixtures with one exported PNG per artboard.
        static let artboardFixtures = [
            "render-shadows", "render-background-blur", "render-text-line-height", "render-group-shadows", "render-rotated-free",
            "render-text-shadows", "render-per-side-shapes",
        ]

        /// The framed boards of `render-transformed-free`: nodes turned and flipped about their
        /// `x`/`y` anchor inside a flex frame, a group and a `layout: none` frame. Its two turned
        /// roots are not pages SwiftUI places, so they are measured by the CG renderer only
        /// (`PenTransformedFreeTests`).
        static let transformBoards = ["flexabs", "grouped", "nested", "flips"].map {
            SwiftUIRenderBoard(fixture: "render-transformed-free", artboard: $0)
        }

        /// The framed boards of `render-free-groups`: groups whose children reach left of and
        /// above their anchor, placed freely and in a flex flow, turned, flipped, nested,
        /// blurred and shadowed. Its root group is not a page SwiftUI places, so it is measured
        /// by the CG renderer only (`PenFreeGroupTests`).
        static let groupBoards = ["pos", "neg", "flex", "rot", "nest", "flexrot", "flip", "blur", "shadow"].map {
            SwiftUIRenderBoard(fixture: "render-free-groups", artboard: $0)
        }

        /// The boards of `render-sizeless-frames`: a `layout: none` frame with no size, which
        /// Pen settles at 0×0 whatever its children reach — plain, clipped, stroked and
        /// shadowed, in a flex flow, in a fit_content flex frame, and with explicit
        /// `fit_content` sizes (leaf Jg0BOv, `PenSizelessFrameTests`).
        static let sizelessBoards = ["plain", "clip", "paint", "flex", "fitflex", "explicit"].map {
            SwiftUIRenderBoard(fixture: "render-sizeless-frames", artboard: $0)
        }

        /// The boards of `render-stroke-shadows`: a stroked node casting an outer shadow,
        /// outside, centered and inside, per side, on each shape kind and on a line, which Pen
        /// casts from the silhouette its stroke band grows (leaf vPZ0ia,
        /// `PenStrokeShadowSnapshotTests`). Not in ``artboardFixtures``, which React's render
        /// test shares.
        static let strokeShadowBoards: [SwiftUIRenderBoard] = {
            let fixture = "render-stroke-shadows"
            let names = (try? PenSnapshotTestHelpers.artboardNames(in: fixture, fixturesDir: SwiftUIFixtures.directory)) ?? []
            return names.map { SwiftUIRenderBoard(fixture: fixture, artboard: $0) }
        }()

        /// The boards of `render-turned-fill`: a turned `fill_container` flex child — on the main
        /// axis, the cross axis and both, in rows and columns, at 30°, 60° and 90° — whose unturned
        /// box Pen fills and whose turned bounds are its slot (leaf ozlazY,
        /// `scripts/gen-turned-fill-fixture`; Pen's exports are of its settled layout).
        static let turnedFillBoards: [SwiftUIRenderBoard] = {
            let fixture = "render-turned-fill"
            let names = (try? PenSnapshotTestHelpers.artboardNames(in: fixture, fixturesDir: SwiftUIFixtures.directory)) ?? []
            return names.map { SwiftUIRenderBoard(fixture: fixture, artboard: $0) }
        }()

        /// The boards of `render-inner-shadow-shapes` and `render-painted-lines`: inner shadows on
        /// SVG-like shapes and icons, and painted strokes on flat lines, fixed and full-width
        /// (leaf 4fZZ38, `scripts/gen-react-fx-fixtures`; `PenInnerShadowShapesSnapshotTests`).
        /// Not in ``artboardFixtures``, which React's render test shares through its own list.
        static let effectProbeBoards: [SwiftUIRenderBoard] = ["render-inner-shadow-shapes", "render-painted-lines"].flatMap { fixture in
            let names = (try? PenSnapshotTestHelpers.artboardNames(in: fixture, fixturesDir: SwiftUIFixtures.directory)) ?? []
            return names.map { SwiftUIRenderBoard(fixture: fixture, artboard: $0) }
        }

        /// The boards of `render-image-crops`: image paints placed by `mode` and cropped by
        /// `transform` (format 2.20) — stretch, cover and contain with six crops each, on wide and
        /// tall boxes, and on an ellipse, an outer stroke and at half opacity (leaf X6YNC3,
        /// `scripts/gen-image-crop-fixture`; `PenImageCropSnapshotTests`). Not in
        /// ``SwiftUIFixtures/paintFixtures``, which the goldens share; `ReactRenderWebViewTests`
        /// adds them to its boards itself (leaf fmV137).
        static let imageCropBoards: [SwiftUIRenderBoard] = {
            let fixture = "render-image-crops"
            let names = (try? PenSnapshotTestHelpers.artboardNames(in: fixture, fixturesDir: SwiftUIFixtures.directory)) ?? []
            return names.map { SwiftUIRenderBoard(fixture: fixture, artboard: $0) }
        }()

        /// Every board, in a stable order: the layout and text fixtures, the effects
        /// fixtures, then each exported artboard of the many-board fixtures and of the paint
        /// fixtures.
        static let all: [SwiftUIRenderBoard] = {
            let single = (SwiftUIFixtures.rendered + effectFixtures).map { SwiftUIRenderBoard(fixture: $0) } + shapeBoards + textBoards
            let boards = (artboardFixtures + SwiftUIFixtures.paintFixtures).flatMap { fixture in
                let names = (try? PenSnapshotTestHelpers.artboardNames(in: fixture, fixturesDir: SwiftUIFixtures.directory)) ?? []
                return names.map { SwiftUIRenderBoard(fixture: fixture, artboard: $0) }.filter { $0.referenceName != nil }
            }
            return single + boards + transformBoards + groupBoards + sizelessBoards + strokeShadowBoards + turnedFillBoards + effectProbeBoards
                + imageCropBoards + darkBoards
        }()

        /// The name the harness writes the render under, and the baselines key it by.
        var id: String {
            let base = artboard.map { "\(fixture)-\($0)" } ?? fixture
            return colorScheme == .light ? base : "\(base)-in-\(colorScheme.rawValue)"
        }

        var testDescription: String {
            id
        }

        /// Pen's export, without `.png`, or `nil` when Pen exported none for this artboard.
        var referenceName: String? {
            guard let artboard = referenceArtboard ?? artboard else { return reference ?? fixture }
            return ["\(fixture)-\(artboard)@2x", "\(fixture)-\(artboard)", artboard].first {
                FileManager.default.fileExists(atPath: SwiftUIFixtures.directory.appendingPathComponent("\($0).png").path)
            }
        }

        /// The board's top-level frame in the parsed fixture, or, with `reference`, the frame
        /// it is measured against.
        func node(in document: PenDocument, reference: Bool = false) -> PenNode? {
            if let artboard = reference ? referenceArtboard ?? artboard : artboard {
                return document.children.first { $0.common.name == artboard }
            }
            return document.children.first
        }

        /// The reference's pixels per point: its width over the board's laid-out width.
        func referenceScale() throws -> Int {
            let resolved = try PenVariableResolver.resolve(PenRefExpander.expand(SwiftUIFixtures.document(fixture)))
            guard let root = node(in: resolved, reference: true),
                  let rect = PenLayoutEngine.layout(resolved)[root.id], rect.width > 0, let referenceName,
                  let reference = PenSnapshotTestHelpers.loadFixtureImage(named: referenceName, fixturesDir: SwiftUIFixtures.directory)
            else { return 1 }
            return max(1, Int((Double(reference.width) / rect.width).rounded()))
        }

        /// The board's page source, its view type renamed `type` so boards whose frames
        /// share a name can be compiled into one module, the support files, the theme files
        /// of a fixture with variables, the local images the page loads (as the fixture
        /// writes their URLs), and the icon fonts it draws with.
        func emitPage(named type: String) throws -> (
            page: GeneratedFile, support: [GeneratedFile], theme: [GeneratedFile], images: Set<String>, fonts: [URL]
        ) {
            let document = try SwiftUIFixtures.document(fixture)
            guard let root = node(in: document),
                  var page = PageAnalyzer.analyze(document).first(where: { $0.id == root.id })
            else { throw BoardError.noPage(id) }
            page.name = type
            let result = try SwiftUIEmitter.emit(
                document: document, components: [], pages: [page], theme: ThemeAnalyzer.analyze(document)
            )
            let files = result.files
            guard let file = files.first(where: { $0.path.contains("/Pages/") }) else { throw BoardError.noPage(id) }
            let fonts = result.iconLibraries.sorted().flatMap(SwiftUIEmitter.iconFontFiles(for:))
            return (
                file, files.filter { $0.path.contains("/Support/") }, files.filter { $0.path.contains("/Theme/") },
                result.imageAssetURLs, fonts
            )
        }

        /// The Core Graphics renderer's image of the frame the board is measured against, at
        /// `scale`.
        func renderCG(scale: CGFloat) throws -> CGImage? {
            let resolved = try PenVariableResolver.resolve(PenRefExpander.expand(SwiftUIFixtures.document(fixture)))
            guard let root = node(in: resolved, reference: true) else { return nil }
            let rects = PenLayoutEngine.layout(resolved)
            guard let rect = rects[root.id] else { return nil }
            return PenRenderer.render(
                resolved, layoutRects: rects, size: CGSize(width: rect.width, height: rect.height),
                scale: scale, rootNodeID: root.id,
                imageProvider: PenRenderer.fileImageProvider(relativeTo: SwiftUIFixtures.directory)
            )
        }

        /// A board the fixture does not hold.
        enum BoardError: Error {
            /// No page was analyzed for this board.
            case noPage(String)
        }
    }

#endif
