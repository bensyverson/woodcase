//
//  ShotCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Renders one node of a `.pen` file to a PNG, sized to fit within `--max` points,
/// optionally annotated with a coordinate ruler and boxes around named nodes.
///
/// `shot` is the CLI's screenshot — the last-resort, pixel-level view
/// `project/agents/cli-design.md` asks every read to offer only after cheaper,
/// structural ones (`tree`), and scoped to the smallest node an agent actually needs.
/// It runs the same pipeline `woodcase render` does — parse, expand refs, resolve
/// variables, lay out, render — for one named node instead of every top-level frame,
/// and reports back exactly what is needed to map a pixel to a layout point.
///
/// ## Picking a node
///
/// A bare invocation with no node is refused rather than rendering the whole
/// document: a giant, unreadable collage is a *plausible wrong answer*, and those are
/// worse than an error (`project/agents/cli-design.md` § Errors that teach). The
/// refusal lists everything renderable at the top level by name and id so the next
/// command can name one — even when there is exactly one, because a caller that meant a
/// different document should see that mistake, not a silently "right" screenshot of the
/// wrong file.
///
/// ## Components, both halves
///
/// A real Pen file keeps two shapes at its top level, and `shot` draws both:
///
/// - a **reusable component definition** — a frame marked `reusable`, which is the
///   thing an editor shows on its canvas. Every top-level frame of `banking.pen` is one.
/// - a **component instance** — a `ref` that places a definition. Every artboard of
///   `woodcase-app.pen` is one.
///
/// Neither is drawable under the id it is authored with. Expansion re-ids an instance
/// root to `<ref id>/<component root id>` and, by default, strips definitions
/// altogether — so `shot` expands for ``Woodcase/PenRefExpander/Purpose/canvas``,
/// which is the *design canvas* reading `woodcase tree` already takes, and maps the
/// resolved address to its post-expansion id with ``Woodcase/EditableDocument/expandedID(of:)``. The `node=`
/// on the printed line is that expanded id: it is what the rects are keyed by, what
/// `tree --expand` prints, and what `--outline` measures against.
///
/// ## Scale
///
/// By default the image is never enlarged past the node's own size:
///
/// ```text
/// scale = min(1, --max / longestSide)
/// ```
///
/// A 320-pt phone screen renders at 1× under the default `--max 1600`; only a node
/// wider or taller than `--max` is shrunk.
///
/// `--scale <multiplier>` renders at exactly that many pixels per layout point
/// instead, and — unlike `--max` — enlarges: a 16×16 icon read at `--scale 8` is a
/// legible 128×128 PNG. `--scale` takes precedence over `--max` entirely rather than
/// being capped by it, so the two are never combined; pick `--max` to fit a budget or
/// `--scale` to make a small node readable.
///
/// ## Fitting a vision model, and tiling when it does not fit
///
/// `--max` is where a vision model's own longest-edge limit belongs. The printed
/// `pixels=` then says whether the node fitted in one look; when it did not, the answer
/// is not a smaller scale but more pictures. `--crop x,y,w,h` renders one
/// sub-rectangle, in the node's own layout points — the space the printed `rect=`
/// establishes — and becomes the `rect=` of that run, so the mapping formula below
/// covers a tile without a second form. `--max` and `--scale` size the *crop*, which is
/// the whole point: a 1200×6000 board fits `--max 1600` only at 0.267×, while four
/// 1200×1500 crops of it are 1× each. See ``ShotCrop``.
///
/// ## Saying where things landed
///
/// `--json` reports every rect the run drew — the node, then each `--outline` in flag
/// order, each with the id and the address it was named by (``ShotRect``). Together with
/// `scale`, `gutterLeft` and `gutterTop` that is enough to place any of them in the
/// image, which is what turns a screenshot into something a caller can act on: an
/// address it can pass to `set`.
///
/// ## Mapping a pixel back to a point
///
/// ```text
/// point = (pixel − gutter) / scale + origin
/// ```
///
/// `scale`, `gutter` and the rect whose `x`/`y` is `origin` are all on the printed
/// line. `gutter` is `0,0` unless `--grid` was asked for, and `origin` is the
/// subtraction ``PenRenderer`` applies before drawing the node's subtree. The same
/// arithmetic is what `--grid` burns into the picture and what `--outline` uses to
/// place a box, so the numbers on the line and the numbers in the image can never
/// disagree.
///
/// The frame those numbers are in is the *rendered node's*, not the canvas's, because
/// the layout engine settles each rect relative to its **parent** — only a top-level
/// node's rect is in canvas coordinates.
/// ``Woodcase/PenLayoutEngine/absoluteRects(under:in:layoutRects:)`` composes the
/// offsets down the rendered node's subtree so an `--outline` box is placed in the same
/// frame the printed `rect=` establishes.
struct Shot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render: one node of a .pen file to a PNG, with an optional ruler and boxes.",
        discussion: """
        A read verb: it takes a shared lock, writes nothing to the .pen file, and \
        leaves its bytes and modification date alone. It writes one PNG, at --out.

        Reach for `woodcase tree` first — structure is cheaper to read than pixels. \
        When you do need the picture, scope it to the smallest node that shows the \
        problem and annotate it, so what you see maps back to what you can edit.

        --scale <multiplier> renders at exactly that many pixels per layout point, \
        enlarging past the node's own size — --max never does. A 16x16 icon is 16 \
        illegible pixels at --max's default; --scale 8 makes the same node a readable \
        128x128 PNG. --scale takes precedence over --max entirely when both are given.

        SIZING A SHOT FOR A VISION MODEL. Pass the model's own longest-edge limit as \
        --max, read the printed pixels= to see whether the node fitted in one look, and \
        when it did not, tile it with --crop rather than shrinking it further.

        --crop x,y,w,h renders just that sub-rectangle of the node. It is written in the \
        node's own layout points -- the same space the printed rect= uses -- and it \
        becomes the rect= of the run, so the mapping formula below needs no second form. \
        --max and --scale then size the crop and not the node, which is what makes a \
        tile of a tall board legible; --outline is judged against the crop, so a box \
        that is not on this tile is refused instead of drawn nowhere. A 1200x6000 board \
        under --max 1600 comes back at scale 0.267; the same board read four tiles at a \
        time comes back at 1x each. Start each tile at the node's printed rect= origin: \
        for a board whose rect= is 3053,-10,1200,6000 the first tile is \
        --crop 3053,-10,1200,1500, the second 3053,1490,1200,1500, and so on.

        --extent painted frames everything the node paints -- its stroke band, shadows, \
        blur and any child an unclipped frame lets overhang it -- instead of its layout \
        rect, the way Pen frames an export. The printed rect= is then that extent, in \
        the same space as the layout rect, so the mapping formula below still holds and \
        --crop and --outline are judged against it. A 100x60 card with a 12-point outer \
        stroke and a shadow offset 10,10 blurred 8 prints rect= 148 by 108, starting 14 \
        points up and left of the card. --extent layout, the default, is the rect `tree` \
        reports.

        --extent painted WITHOUT --crop ALSO GROWS TO WHOLE PIXELS AT THE RENDER SCALE, \
        the way Pen's own PNG export does: the extent's corner (rect='s x,y) stays \
        exactly where it is, fractional or not, and only its width and height grow, just \
        enough that pixels= lands on a whole pixel. A turned node whose painted extent is \
        149.39 by 134.75 points prints rect= width 149.5, height 135.0 at --scale 2 -- \
        rounded up from the raw extent, not down -- so pixels=299x270 matches Pen's \
        export pixel for pixel instead of cropping the last row and column.

        --outline <node> boxes a node's layout rect and tags it with the node's name. \
        The address is resolved exactly as the rendered node's is — a name, an id, a \
        `Parent/Child` path, a path through a component instance — and the flag \
        repeats. The ring is drawn just *outside* the rect, so the node's own edge \
        pixels are never covered. Only a node inside the rendered node's own subtree \
        can be boxed; anything else is refused rather than drawn nowhere.

        --grid draws a numbered ruler along the top and left edges, ticked every 100 \
        layout points, plus a faint line across the image at each tick. The numbers \
        count from the rendered node's own rect origin — the `rect=` on the printed \
        line — so a node whose rect starts at x=40 has no tick before 100. They are \
        layout points, not pixel counts, whatever --max shrank the render to.

        --grid MAKES THE IMAGE BIGGER THAN --max. The ruler lives in a gutter added \
        outside the render, because a ruler scaled down with the picture cannot be \
        read. The printed `pixels=` is the file's real size and `gutter=` is what was \
        added, so a pixel still maps back:

          point = (pixel - gutter) / scale + origin        (origin is rect's x,y)

        Worked example. A 1600x400 header shrunk to fit 800 points, with the logo \
        boxed and the ruler on:

          woodcase shot design.pen Dashboard/Header --out header.png \\
            --max 800 --grid --outline Dashboard/Header/Logo

          Hdr01  scale=0.5  rect=0.0,0.0,1600.0,400.0  pixels=828x224 \\
            gutter=28,24  out=header.png

        The PNG is 828 wide, not 800: 800 pixels of render plus a 28-pixel gutter. A \
        feature you spot at pixel (328, 124) is at layout point \
        ((328-28)/0.5, (124-24)/0.5) = (600, 200) — which is what the ruler in the \
        gutter reads off, and what every other verb's coordinates are measured in.

        """
    )

    /// The `.pen` file to render.
    @Argument(help: "The .pen file to render.")
    var file: PenFilePath

    /// The node to render: an id, a name, or a `Parent/Child` path (``NodeAddress``).
    /// Required — see the type's discussion for why there is no default.
    @Argument(help: "The node to render: an id, a name, or a `Parent/Child` path.")
    var node: String?

    /// Where to write the PNG.
    @Option(name: .long, help: ArgumentHelp("Output PNG path.", valueName: "path"))
    var out: String

    /// The longest side, in points, the output image may have.
    @Option(
        name: .customLong("max"),
        help: ArgumentHelp(
            "The longest side of the image, in points. The node is never enlarged past its own size. "
                + "Ignored when --scale is given.",
            valueName: "points"
        )
    )
    var maxSize: Int = 1600

    /// Pixels per layout point to render at, `nil` unless `--scale` was given.
    ///
    /// Unlike `--max`, this enlarges: it renders at exactly this multiplier, which is
    /// how a 6–22pt component (an icon, a badge) becomes a PNG a reviewer can actually
    /// read. Takes precedence over `--max` rather than being capped by it.
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Render at exactly this many pixels per layout point — unlike --max, this "
                + "enlarges. Takes precedence over --max.",
            valueName: "multiplier"
        )
    )
    var scale: Double?

    /// The `--theme` pin, declared once for every verb in ``ThemeOption``.
    @OptionGroup var themePin: ThemeOption

    /// Whether to add the numbered ruler. See ``ShotOverlay`` for why it is drawn last
    /// and why it makes the image larger than `--max`.
    @Flag(
        name: .long,
        help: "Add a ruler numbered in layout points. Grows the image past --max by the gutter."
    )
    var grid = false

    /// Node addresses to box, resolved the same way ``node`` is.
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Box this node and tag it with its name. Repeatable.",
            valueName: "node"
        )
    )
    var outline: [String] = []

    /// The sub-rectangle to render, `nil` unless `--crop` was given. See ``ShotCrop``.
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Render only this sub-rectangle of the node, in the node's own layout points "
                + "— the space `rect=` prints. --max and --scale then size the crop.",
            valueName: "x,y,w,h"
        )
    )
    var crop: ShotCrop?

    /// Which extent the shot frames: the layout rect by default. See ``ShotExtent``.
    @Option(
        name: .long,
        help: ArgumentHelp(
            "Frame the layout rect (the default) or everything the node paints: strokes, "
                + "shadows, blur and unclipped children, as Pen frames an export.",
            valueName: "layout|painted"
        )
    )
    var extent: ShotExtent = .layout

    /// The `--json` flag.
    @OptionGroup var output: OutputOptions

    /// Rejects a `--scale` that cannot render anything, and a `--crop` that is not four
    /// numbers with an area.
    func validate() throws {
        if let scale, scale <= 0 {
            throw ValidationError("--scale must be a positive number, got \(scale).")
        }
        _ = try crop?.region()
    }

    func run() async throws {
        let url = try file.existingFile()
        let request = try Request(
            node: node, theme: themePin.theme, maxSize: maxSize, scale: scale,
            grid: grid, outline: outline, crop: crop?.region(), extent: extent, out: out
        )
        let result = try await runReportingFailures(editing: url) {
            try await Self.render(request, editing: url)
        }
        try print(output.json ? result.json() : result.text)
    }
}
