//
//  ShotTargets.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Works out what `shot` is being asked to draw: the node to render, and the nodes to
/// box around it.
///
/// Kept apart from ``Shot`` itself because it is the half that has to run *inside* the
/// read transaction, where the document exists — and because `--outline` earns its
/// keep only by resolving addresses exactly as the rendered node does. One `resolve`,
/// one grammar, one set of errors: a caller who can name a node for `shot` can name
/// one for `--outline` without learning anything new, and gets the same "ambiguous,
/// here are the candidates" when they cannot.
enum ShotTargets {
    /// What ``select(node:outlining:in:editing:)`` found.
    struct Selection {
        /// The document expanded for the canvas — imported instances included — and
        /// not yet variable-resolved.
        let document: PenDocument

        /// The node to render.
        let root: Box

        /// One entry per `--outline`, in the order given.
        let outlines: [Box]

        /// The node id to render, in the form ref expansion produces — see
        /// ``Woodcase/EditableDocument/expandedID(of:)``. For a top-level component
        /// instance that is `<ref id>/<component root id>`, not the authored ref id.
        var nodeID: String {
            root.id
        }
    }

    /// One resolved address: which node, what the caller called it, and what to call it
    /// back.
    ///
    /// Separate from ``ShotOverlay/Target`` because the rect is not known yet — an
    /// address resolves inside the read transaction, and layout runs after it. The
    /// rendered node is one of these too, so `--json` can report it in the same shape as
    /// the boxes drawn on it.
    struct Box {
        /// The resolved id, in the form ref expansion produces.
        let id: String

        /// The address exactly as the caller typed it, so a refusal or a `--json` row
        /// hands back something that can be pasted into the next command.
        let address: String

        /// The name to print in the box's tag.
        let label: String
    }

    /// Resolves the rendered node and every `--outline` node, or refuses with the
    /// top-level frames to choose from.
    ///
    /// - Parameters:
    ///   - node: The address to render, as typed, or `nil`.
    ///   - outlines: The `--outline` addresses, as typed, in the order given.
    ///   - document: The document to resolve against.
    ///   - url: The `.pen` file, for the error message if resolution fails.
    /// - Returns: The materialized document, the id to render, and the boxes to draw.
    /// - Throws: ``CommandFailure`` — usage when `node` is `nil` or an address does
    ///   not resolve.
    static func select(
        node: String?,
        outlining outlines: [String],
        in document: EditableDocument,
        editing url: URL
    ) throws -> Selection {
        guard let node else {
            throw CommandFailure(message: noNodeMessage(for: document), exitCode: .usage)
        }
        do {
            let resolved = try document.resolve(node)
            let boxes = try outlines.map { address -> Box in
                let target = try document.resolve(address)
                return Box(
                    id: document.expandedID(of: target),
                    address: address,
                    label: label(for: target, in: document)
                )
            }
            return Selection(
                document: document.expanded(for: .canvas),
                root: Box(
                    id: document.expandedID(of: resolved),
                    address: node,
                    label: label(for: resolved, in: document)
                ),
                outlines: boxes
            )
        } catch {
            throw CommandFailure.describing(error, in: document, editing: url)
        }
    }

    /// The refusal for a target the layout engine settled no rect for.
    ///
    /// This is a *usage* failure, not an environment one: the pipeline ran, the file is
    /// fine, and what went wrong is that the named node is not something the layout
    /// engine measures. Exit 5 would have told the reader to go and check their setup
    /// (`project/agents/cli-design.md` § The table), which is the one place the answer
    /// is not.
    ///
    /// - Parameters:
    ///   - address: The id the rect was looked for under, after ref expansion.
    ///   - requested: The address as the caller typed it, which may be a name or a path.
    ///   - url: The `.pen` file, named in the remedy.
    /// - Returns: The failure to throw.
    static func missingRectFailure(
        address: String,
        requested: String,
        editing url: URL
    ) -> CommandFailure {
        CommandFailure(
            message: """
            \(requested) resolved to \(address), which the layout engine settled no rect \
            for — there is nothing to draw. `woodcase tree \(url.path) --expand` lists \
            every node the layout engine saw, with the ids `shot` renders.
            """,
            exitCode: .usage
        )
    }

    /// Settles what the render will actually cover: the whole node, or the `--crop` a
    /// caller narrowed it to.
    ///
    /// A crop that runs off the node is refused rather than clamped. Clamping would
    /// return an image a different size from the one asked for, and every downstream
    /// number — `pixels=`, the tile grid a caller is stepping through, the arithmetic
    /// that turns a pixel back into a point — would still be computed against the crop
    /// that was typed. That is a plausible wrong answer, so the refusal names the node's
    /// own rect and spells the largest crop that does fit at the same origin.
    ///
    /// - Parameters:
    ///   - crop: The `--crop` rectangle, or `nil` for the whole node.
    ///   - node: The rendered node's own layout rect.
    ///   - id: The rendered node's id, named in the refusal.
    ///   - url: The `.pen` file, named in the refusal.
    /// - Returns: The region to render, in the rendered node's own coordinate space.
    /// - Throws: ``CommandFailure`` with `usage` when the crop is not wholly inside the
    ///   node.
    static func drawnRegion(
        crop: PenRect?,
        of node: PenRect,
        named id: String,
        editing url: URL
    ) throws -> PenRect {
        guard let crop else { return node }
        guard ShotGeometry.contains(node, crop) else {
            let fitted = ShotGeometry.clamp(crop, to: node)
            let remedy = fitted.width > 0 && fitted.height > 0
                ? "The largest crop at that origin is `--crop \(ShotCrop.argument(for: fitted))`."
                : """
                That origin is outside the node altogether — `--crop \
                \(ShotCrop.argument(for: node))` is the whole of it.
                """
            throw CommandFailure(
                message: """
                --crop \(ShotCrop.argument(for: crop)) runs off \(id), whose rect is \
                \(ShotCrop.argument(for: node)) — a crop is measured in the node's own \
                layout points, the same space the printed `rect=` uses. \(remedy) \
                `woodcase shot \(url.path) \(id) --out <path> --json` prints the rect to \
                crop inside.
                """,
                exitCode: .usage
            )
        }
        return crop
    }

    /// Turns the resolved boxes into drawable ones, refusing any that would fall off
    /// the image.
    ///
    /// A box drawn entirely outside the render is the *silently does nothing* case
    /// `project/agents/cli-design.md` § Errors that teach rules out: the PNG would come
    /// back looking exactly like one with no `--outline` at all, and the caller would
    /// conclude the node is invisible rather than out of frame.
    ///
    /// - Parameters:
    ///   - selection: The resolved target and boxes.
    ///   - frame: The rendered node's subtree, in the rendered node's coordinate frame
    ///     — ``Woodcase/PenLayoutEngine/absoluteRects(under:in:layoutRects:)``.
    ///     Membership is what decides whether a node is in the picture at all.
    ///   - drawn: The region the image covers — the rendered node's own rect, or the
    ///     `--crop` narrowed from it. Boxes are judged against this, not the node, so a
    ///     tile refuses a landmark that is not on *that* tile.
    ///   - node: The rendered node's own rect, which bounds any crop the remedy suggests.
    ///   - url: The `.pen` file, named in the refusal.
    /// - Returns: The boxes to draw.
    /// - Throws: ``CommandFailure`` with `usage` for a node outside the rendered node's
    ///   subtree, or one placed clear of the drawn region.
    static func overlayTargets(
        for selection: Selection,
        in frame: [String: PenRect],
        within drawn: PenRect,
        of node: PenRect,
        editing url: URL
    ) throws -> [ShotOverlay.Target] {
        try selection.outlines.map { box in
            guard let rect = frame[box.id] else {
                throw CommandFailure(
                    message: """
                    --outline \(box.label) (\(box.id)) is not inside the rendered node \
                    \(selection.nodeID), so the box would fall off the image. Shoot an \
                    ancestor that contains both, then `--crop` back down to the part you \
                    need: `woodcase tree \(url.path) --expand` shows which.
                    """,
                    exitCode: .usage
                )
            }
            guard ShotGeometry.overlaps(rect, drawn) else {
                throw CommandFailure(
                    message: """
                    --outline \(box.label) (\(box.id)) is at \
                    \(ShotCrop.argument(for: rect)) in layout points, clear of the \
                    \(ShotCrop.argument(for: drawn)) region this run drew of \
                    \(selection.nodeID) — the box would fall off the image. \
                    \(widen(drawn, toInclude: rect, within: node, editing: url))
                    """,
                    exitCode: .usage
                )
            }
            return ShotOverlay.Target(rect: rect, label: box.label)
        }
    }

    // MARK: - Private

    /// The name to tag a box with: the node's own name, or its `#id` marker.
    ///
    /// For a node inside a component instance the name lives on the *component's*
    /// child — the instance descendant has no storage of its own — so the last segment
    /// of the descendant key is what is looked up.
    ///
    /// - Parameters:
    ///   - target: The resolved address.
    ///   - document: The document to read the name from.
    /// - Returns: The label.
    private static func label(
        for target: ResolvedNodeAddress,
        in document: EditableDocument
    ) -> String {
        let storedID = target.descendantKey?
            .split(separator: NodeAddress.separator)
            .last
            .map(String.init) ?? target.targetID
        return document.nodes[storedID]?.common.name ?? NodeAddress.marker(forID: target.address)
    }

    /// The remedy sentence for a box that missed the drawn region: the crop that would
    /// have included it, when one exists inside the node.
    ///
    /// A caller stepping a tile grid down a tall board hits this constantly, and the
    /// answer it wants is not "shoot something else" but "here is the tile that has it".
    /// When the box overflows the node itself — a descendant may — no crop of the node
    /// can hold it, and the older remedy is the true one.
    ///
    /// - Parameters:
    ///   - drawn: The region this run drew.
    ///   - box: The rect that missed it.
    ///   - node: The rendered node's own rect, which bounds any crop.
    ///   - url: The `.pen` file, named in the remedy.
    /// - Returns: A sentence ending in the command to run next.
    private static func widen(
        _ drawn: PenRect,
        toInclude box: PenRect,
        within node: PenRect,
        editing url: URL
    ) -> String {
        let widened = ShotGeometry.clamp(ShotGeometry.union(drawn, box), to: node)
        guard ShotGeometry.contains(widened, box) else {
            return """
            Shoot an ancestor that contains both: `woodcase tree \(url.path)` shows which.
            """
        }
        return """
        `--crop \(ShotCrop.argument(for: widened))` draws a region holding both; \
        `woodcase tree \(url.path)` shows what else is in it.
        """
    }

    /// The refusal message when no node is named: everything at the top level that
    /// `shot` can actually draw, by name and id.
    ///
    /// A list that sends the reader somewhere the tool cannot go is worse than no list,
    /// so this names exactly the two shapes ``Shot`` renders — a frame, and a `ref` that
    /// places a component — and marks the reusable *definitions*, because in a real Pen
    /// file (`banking.pen`, `woodcase-app.pen`) the top-level frames are all definitions
    /// and the artboards on the canvas are all refs. Both render; only one is what a
    /// caller looking for "the screen" usually means, and the marker is how they tell.
    ///
    /// - Parameter document: The document to list from.
    /// - Returns: The message, ending with what to run next.
    private static func noNodeMessage(for document: EditableDocument) -> String {
        let entries = document.rootOrder.compactMap { id -> String? in
            guard let node = document.nodes[id] else { return nil }
            switch node.kind {
            case .frame, .ref: break
            default: return nil
            }
            let label = node.common.name ?? NodeAddress.marker(forID: id)
            let marker = node.common.reusable == true ? "  (component definition)" : ""
            return "  \(label)  \(id)\(marker)"
        }
        let list = entries.isEmpty
            ? "  (this document has nothing renderable at the top level)"
            : entries.joined(separator: "\n")
        return """
        No node given — rendering the whole document risks a giant, misleading image. \
        Pick one of these, by name or id:
        \(list)
        """
    }
}
