//
//  PenLayoutEngine.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import CoreText
import Foundation

/// A function that measures text and returns its bounding size.
///
/// - Parameter request: The text, its style as the node writes it, its styled runs and the
///   width it may wrap at (``PenTextMeasureRequest``).
/// - Returns: The bounding size (width, height) of the measured text.
public typealias TextMeasurer = @Sendable (_ request: PenTextMeasureRequest) -> (width: Double, height: Double)

/// Computes layout rectangles for all nodes in a .pen document.
///
/// The layout engine takes a fully parsed, variable-resolved, ref-expanded
/// ``PenDocument`` and produces a dictionary mapping each node's ID to its
/// computed layout rectangle in parent-local coordinates.
///
/// The algorithm is a combined measure/arrange recursion:
/// - **Measure** (bottom-up): compute intrinsic sizes from children
/// - **Arrange** (top-down): assign positions given parent constraints
///
/// ## Usage
///
/// ```swift
/// let rects = PenLayoutEngine.layout(document)
/// // rects["nodeId"] == PenRect(x: 0, y: 0, width: 400, height: 300)
/// ```
public nonisolated enum PenLayoutEngine {
    /// The default text measurer, backed by ``PenTextMeasurer`` and Core Text.
    public static let defaultTextMeasurer: TextMeasurer = { request in
        let size = PenTextMeasurer.measure(
            request.text,
            fontFamily: request.fontFamily,
            fontSize: request.fontSize,
            fontWeight: request.fontWeight,
            fontStyle: request.fontStyle,
            letterSpacing: request.letterSpacing,
            lineHeight: request.lineHeight,
            maxWidth: request.maxWidth,
            runs: request.runs,
            indents: request.indents
        )
        return (size.width, size.height)
    }

    /// Computes layout rectangles for all nodes in the document.
    ///
    /// Each node's rectangle uses coordinates local to its parent.
    /// Root nodes use their explicit x/y (defaulting to 0,0).
    ///
    /// - Parameters:
    ///   - document: A fully parsed, variable-resolved, ref-expanded document.
    ///   - textMeasurer: A function that measures text bounding boxes. Defaults to
    ///     ``defaultTextMeasurer``, which uses Core Text via ``PenTextMeasurer``.
    /// - Returns: A dictionary mapping node IDs to their computed layout rectangles.
    public static func layout(
        _ document: PenDocument,
        textMeasurer: TextMeasurer = defaultTextMeasurer
    ) -> [String: PenRect] {
        var rects: [String: PenRect] = [:]
        var memo = Memo()
        for node in document.children {
            let x = node.common.x?.literalValue ?? 0
            let y = node.common.y?.literalValue ?? 0
            let size = layoutNode(node, availableWidth: nil, availableHeight: nil, textMeasurer: textMeasurer, into: &rects, memo: &memo)
            rects[node.id] = freeRect(of: node, x: x, y: y, size: size, placedIn: rects)
        }
        return rects
    }

    /// Incrementally computes layout, re-laying out only roots with dirty descendants.
    ///
    /// For each top-level node, checks whether any of its descendants (or itself) are
    /// in the `dirtyNodeIDs` set. If not, the previous rects for that entire subtree
    /// are copied unchanged. If any are dirty, the entire root subtree is re-laid out.
    ///
    /// - Parameters:
    ///   - document: A fully parsed, variable-resolved, ref-expanded document.
    ///   - previousRects: The cached layout rects from the previous pass.
    ///   - dirtyNodeIDs: Node IDs that have changed since the previous layout.
    ///   - textMeasurer: A function that measures text bounding boxes.
    /// - Returns: A dictionary mapping node IDs to their computed layout rectangles.
    public static func layoutIncremental(
        _ document: PenDocument,
        previousRects: [String: PenRect],
        dirtyNodeIDs: Set<String>,
        textMeasurer: TextMeasurer = defaultTextMeasurer
    ) -> [String: PenRect] {
        var rects: [String: PenRect] = [:]
        var memo = Memo()

        for node in document.children {
            if subtreeContainsDirty(node, dirtyNodeIDs: dirtyNodeIDs) {
                // Dirty root — re-layout entire subtree
                let x = node.common.x?.literalValue ?? 0
                let y = node.common.y?.literalValue ?? 0
                let size = layoutNode(
                    node, availableWidth: nil, availableHeight: nil,
                    textMeasurer: textMeasurer, into: &rects, memo: &memo
                )
                rects[node.id] = freeRect(of: node, x: x, y: y, size: size, placedIn: rects)
            } else {
                // Clean root — copy previous rects for entire subtree
                copySubtreeRects(node, from: previousRects, into: &rects)
            }
        }

        return rects
    }

    /// Incrementally computes layout with a measurement cache for cross-frame persistence.
    ///
    /// Like ``layoutIncremental(_:previousRects:dirtyNodeIDs:textMeasurer:)``, but uses
    /// a measurement cache to skip re-computing unchanged subtrees within dirty roots.
    /// The cache holds, per node, the offered space and size of its last *final* call —
    /// the one whose rects below the node reach the result; on a hit the subtree is
    /// skipped entirely and its rects come from `previousRects`. The caller must forget
    /// the entries of every dirty node and its ancestors, and pass the rects the cache
    /// was filled alongside.
    ///
    /// - Parameters:
    ///   - document: A fully parsed, variable-resolved, ref-expanded document.
    ///   - previousRects: The cached layout rects from the previous pass.
    ///   - dirtyNodeIDs: Node IDs that have changed since the previous layout.
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///   - measurementCache: A cache of per-node measurement results, mutated in place.
    /// - Returns: A dictionary mapping node IDs to their computed layout rectangles.
    public static func layoutIncremental(
        _ document: PenDocument,
        previousRects: [String: PenRect],
        dirtyNodeIDs: Set<String>,
        textMeasurer: TextMeasurer = defaultTextMeasurer,
        measurementCache: inout [String: MeasurementCacheEntry]
    ) -> [String: PenRect] {
        var memo = Memo(finals: measurementCache)
        let rects = layOutRoots(
            of: document, previousRects: previousRects,
            isDirty: { subtreeContainsDirty($0, dirtyNodeIDs: dirtyNodeIDs) },
            textMeasurer: textMeasurer, memo: &memo
        )
        measurementCache = memo.finals
        return rects
    }

    /// Lays out the top-level nodes `isDirty` picks, through the measurement cache, and
    /// copies every other one's rects from the previous layout.
    ///
    /// A dirty root's map starts from its previous rects, so a cache hit — which skips a
    /// subtree — leaves that subtree's rects as they were.
    ///
    /// - Parameters:
    ///   - document: A fully parsed, variable-resolved, ref-expanded document.
    ///   - previousRects: The rects of the previous layout.
    ///   - isDirty: Whether a top-level node must be laid out again.
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///   - memo: The sizes remembered so far, read and filled.
    /// - Returns: Every node's rect.
    static func layOutRoots(
        of document: PenDocument,
        previousRects: [String: PenRect],
        isDirty: (PenNode) -> Bool,
        textMeasurer: TextMeasurer,
        memo: inout Memo
    ) -> [String: PenRect] {
        var rects: [String: PenRect] = [:]
        for node in document.children {
            // Clean or dirty, the map starts from the previous rects; a dirty root is then
            // laid out over them, and cache hits keep what they skip.
            copySubtreeRects(node, from: previousRects, into: &rects)
            guard isDirty(node) else { continue }
            let x = node.common.x?.literalValue ?? 0
            let y = node.common.y?.literalValue ?? 0
            let size = layoutNode(
                node, availableWidth: nil, availableHeight: nil,
                textMeasurer: textMeasurer, into: &rects, memo: &memo
            )
            rects[node.id] = freeRect(of: node, x: x, y: y, size: size, placedIn: rects)
        }
        return rects
    }

    /// Computes layout for a single subtree, returning rects for only the target node and its descendants.
    ///
    /// Use this for interactive editing scenarios (e.g., drag-resizing a flex container) where
    /// re-laying out the entire document would be too expensive at 120Hz. The caller provides
    /// `existingRects` so the engine can derive parent constraints and preserve the subtree root's
    /// position.
    ///
    /// - Parameters:
    ///   - rootID: The ID of the subtree root to re-layout.
    ///   - document: The full document (needed for tree traversal).
    ///   - existingRects: Current layout rects (used for parent constraints and position).
    ///   - textMeasurer: A function that measures text bounding boxes.
    /// - Returns: A dictionary of rects for the subtree only. Empty if `rootID` is not found.
    public static func layoutSubtree(
        rootID: String,
        in document: PenDocument,
        existingRects: [String: PenRect],
        textMeasurer: TextMeasurer = defaultTextMeasurer
    ) -> [String: PenRect] {
        var memo = Memo()
        return layoutSubtreeImpl(
            rootID: rootID, in: document, existingRects: existingRects,
            textMeasurer: textMeasurer, memo: &memo
        )
    }

    /// Computes layout for a single subtree with a measurement cache for cross-frame persistence.
    ///
    /// Like ``layoutSubtree(rootID:in:existingRects:textMeasurer:)``, but uses a measurement cache
    /// to skip re-computing unchanged sub-subtrees.
    ///
    /// - Parameters:
    ///   - rootID: The ID of the subtree root to re-layout.
    ///   - document: The full document (needed for tree traversal).
    ///   - existingRects: Current layout rects (used for parent constraints and position).
    ///   - textMeasurer: A function that measures text bounding boxes.
    ///   - measurementCache: A cache of per-node measurement results, mutated in place.
    /// - Returns: A dictionary of rects for the subtree only. Empty if `rootID` is not found.
    public static func layoutSubtree(
        rootID: String,
        in document: PenDocument,
        existingRects: [String: PenRect],
        textMeasurer: TextMeasurer = defaultTextMeasurer,
        measurementCache: inout [String: MeasurementCacheEntry]
    ) -> [String: PenRect] {
        var memo = Memo(finals: measurementCache)
        let result = layoutSubtreeImpl(
            rootID: rootID, in: document, existingRects: existingRects,
            textMeasurer: textMeasurer, memo: &memo
        )
        measurementCache = memo.finals
        return result
    }

    /// Checks whether any node in the subtree is in the dirty set, short-circuiting on the first match.
    ///
    /// This and every other walk in the engine runs from a work list, not recursion, so
    /// a deep tree cannot overflow a Swift task's stack in a debug build
    /// (`project/2026-09-26-debug-stack-depth.md`).
    private static func subtreeContainsDirty(_ node: PenNode, dirtyNodeIDs: Set<String>) -> Bool {
        var pending = [node]
        while let next = pending.popLast() {
            if dirtyNodeIDs.contains(next.id) { return true }
            pending.append(contentsOf: nodeChildren(next) ?? [])
        }
        return false
    }

    /// Copies previous rects for all nodes in a subtree into the output dict.
    ///
    /// A disabled child of a flex container is skipped with everything under it: the flow
    /// gives it no rect, so a rect it had before it was disabled must not survive. A
    /// container that places its children at their own x/y places a disabled one too.
    private static func copySubtreeRects(
        _ node: PenNode,
        from previousRects: [String: PenRect],
        into rects: inout [String: PenRect]
    ) {
        var pending = [node]
        while let next = pending.popLast() {
            if let rect = previousRects[next.id] {
                rects[next.id] = rect
            }
            guard let children = nodeChildren(next) else { continue }
            if extractLayoutProperties(next).layout == PenLayoutDirection.none {
                pending.append(contentsOf: children)
            } else {
                pending.append(contentsOf: children.filter { $0.common.enabled?.literalValue != false })
            }
        }
    }
}

// MARK: - Cache Types

public extension PenLayoutEngine {
    /// A cached measurement result for a single node, keyed by available dimensions.
    ///
    /// Used by ``layoutIncremental(_:previousRects:dirtyNodeIDs:textMeasurer:measurementCache:)``
    /// to skip re-computing unchanged subtrees: the offered space and size of the node's
    /// last final call in the layout that produced the rects passed with it.
    struct MeasurementCacheEntry: Friendly {
        public let availableWidth: Double?
        public let availableHeight: Double?
        public let width: Double
        public let height: Double

        public init(availableWidth: Double?, availableHeight: Double?, width: Double, height: Double) {
            self.availableWidth = availableWidth
            self.availableHeight = availableHeight
            self.width = width
            self.height = height
        }
    }
}

// MARK: - Internal Types

extension PenLayoutEngine {
    struct TextMeasurementInput {
        /// The node's text, style and runs, unwrapped: the width is decided per measurement.
        let request: PenTextMeasureRequest
        let textGrowth: PenTextGrowth?
    }

    struct NodeLayoutProperties {
        let widthSizing: PenSizing
        let heightSizing: PenSizing
        let layout: PenLayoutDirection
        let gap: Double
        let padding: PenPadding.Edges
        let justifyContent: PenJustifyContent
        let alignItems: PenAlignItems
        let children: [PenNode]
        let isContainer: Bool
        let textInput: TextMeasurementInput?
        /// A note's text, measured to grow the note (``PenLayoutEngine/noteTextRequest(_:)``).
        var noteText: PenTextMeasureRequest?
        /// The space around a note's text, its chrome included (``PenPostIt/bodyInsets(of:style:)``).
        var noteInsets: PenPadding.Edges?
    }

    struct ChildMeasurement {
        let node: PenNode
        var mainSize: Double
        var crossSize: Double
        let isFlexibleMain: Bool
        let isFlexibleCross: Bool
        let mainFallback: Double?
        let crossFallback: Double?
        var measuredWidth: Double
        var measuredHeight: Double
    }
}

// MARK: - Declared Sizing

extension PenLayoutEngine {
    /// The sizing this engine lays a node's width out by, defaults included.
    ///
    /// Not the same thing as the node's declared `width`: an absent width is
    /// `fit_content`, and a `group` has no width of its own at all — it is always
    /// `fit_content` around its children. Anything reasoning about sizing (``DocumentLinter``
    /// does) asks here rather than reading the property, so there is one answer to
    /// "what does `fill_container` mean on this node" and the layout owns it.
    ///
    /// - Parameter node: The node to ask about.
    /// - Returns: The width sizing the layout pass uses.
    static func widthSizing(of node: PenNode) -> PenSizing {
        extractLayoutProperties(node).widthSizing
    }

    /// The sizing this engine lays a node's height out by, defaults included.
    ///
    /// - Parameter node: The node to ask about.
    /// - Returns: The height sizing the layout pass uses.
    /// - SeeAlso: ``widthSizing(of:)``
    static func heightSizing(of node: PenNode) -> PenSizing {
        extractLayoutProperties(node).heightSizing
    }
}

// MARK: - Property Extraction

extension PenLayoutEngine {
    static func extractLayoutProperties(_ node: PenNode) -> NodeLayoutProperties {
        switch node.kind {
        case let .frame(data):
            NodeLayoutProperties(
                widthSizing: data.width ?? .fitContent(fallback: nil),
                heightSizing: data.height ?? .fitContent(fallback: nil),
                layout: data.layout ?? .horizontal,
                gap: data.gap?.literalValue ?? 0,
                padding: data.padding?.resolve() ?? .zero,
                justifyContent: data.justifyContent ?? .start,
                alignItems: data.alignItems ?? .start,
                children: data.children ?? [],
                isContainer: true,
                textInput: nil
            )
        case let .group(data):
            // A group has no layout properties of its own: it is always an
            // absolute container whose children sit at their own explicit x/y.
            NodeLayoutProperties(
                widthSizing: .fitContent(fallback: nil),
                heightSizing: .fitContent(fallback: nil),
                layout: .none,
                gap: 0,
                padding: .zero,
                justifyContent: .start,
                alignItems: .start,
                children: data.children ?? [],
                isContainer: true,
                textInput: nil
            )
        default:
            NodeLayoutProperties(
                widthSizing: extractLeafWidth(node.kind),
                heightSizing: extractLeafHeight(node.kind),
                layout: .horizontal,
                gap: 0,
                padding: .zero,
                justifyContent: .start,
                alignItems: .start,
                children: [],
                isContainer: false,
                textInput: extractTextInput(node),
                noteText: noteTextRequest(node),
                noteInsets: PenPostIt.bodyInsets(of: node)
            )
        }
    }

    static func extractTextInput(_ node: PenNode) -> TextMeasurementInput? {
        guard case let .text(data) = node.kind else { return nil }

        return TextMeasurementInput(
            request: PenTextMeasureRequest(
                text: data.content?.literalValue ?? "",
                fontFamily: data.fontFamily?.literalValue,
                fontSize: data.fontSize?.literalValue,
                fontWeight: data.fontWeight?.literalValue,
                fontStyle: data.fontStyle?.literalValue,
                letterSpacing: data.letterSpacing?.literalValue,
                lineHeight: data.lineHeight?.literalValue,
                runs: node.appliedRuns
            ),
            textGrowth: data.textGrowth
        )
    }

    static func extractLeafWidth(_ kind: PenNode.Kind) -> PenSizing {
        switch kind {
        case let .rectangle(d): d.width ?? .fitContent(fallback: nil)
        case let .ellipse(d): d.width ?? .fitContent(fallback: nil)
        case let .text(d): d.width ?? .fitContent(fallback: nil)
        case let .line(d): d.width ?? .fitContent(fallback: nil)
        case let .polygon(d): d.width ?? .fitContent(fallback: nil)
        case let .path(d): d.width ?? .fitContent(fallback: nil)
        case let .icon(d): d.width ?? .fitContent(fallback: nil)
        case let .script(d): d.width ?? .fitContent(fallback: nil)
        case let .browser(d): d.width ?? .fitContent(fallback: nil)
        case let .note(d): PenPostIt.layoutSizing(d.width)
        case let .prompt(d): PenPostIt.layoutSizing(d.width, default: PenPostIt.cardDefaultWidth)
        case let .context(d): PenPostIt.layoutSizing(d.width, default: PenPostIt.cardDefaultWidth)
        case let .unknown(_, properties): PenSizing(declared: properties["width"]) ?? .fitContent(fallback: nil)
        default: .fitContent(fallback: nil)
        }
    }

    static func extractLeafHeight(_ kind: PenNode.Kind) -> PenSizing {
        switch kind {
        case let .rectangle(d): d.height ?? .fitContent(fallback: nil)
        case let .ellipse(d): d.height ?? .fitContent(fallback: nil)
        case let .text(d): d.height ?? .fitContent(fallback: nil)
        case let .line(d): d.height ?? .fitContent(fallback: nil)
        case let .polygon(d): d.height ?? .fitContent(fallback: nil)
        case let .path(d): d.height ?? .fitContent(fallback: nil)
        case let .icon(d): d.height ?? .fitContent(fallback: nil)
        case let .script(d): d.height ?? .fitContent(fallback: nil)
        case let .browser(d): d.height ?? .fitContent(fallback: nil)
        case let .note(d): PenPostIt.layoutSizing(d.height)
        case let .prompt(d): PenPostIt.layoutSizing(d.height, default: PenPostIt.cardDefaultHeight)
        case let .context(d): PenPostIt.layoutSizing(d.height, default: PenPostIt.cardDefaultHeight)
        case let .unknown(_, properties): PenSizing(declared: properties["height"]) ?? .fitContent(fallback: nil)
        default: .fitContent(fallback: nil)
        }
    }
}

// MARK: - Rotation Bounding Box

extension PenLayoutEngine {
    /// Returns the axis-aligned bounding box size for a rect rotated by the given angle in degrees.
    ///
    /// Pen expands layout rects to contain the full rotated shape. For a rect of
    /// size (w, h) rotated by θ:
    /// - `boundingWidth  = |w * cos(θ)| + |h * sin(θ)|`
    /// - `boundingHeight = |w * sin(θ)| + |h * cos(θ)|`
    static func rotatedBoundingBox(width w: Double, height h: Double, rotationDegrees: Double) -> (width: Double, height: Double) {
        guard rotationDegrees != 0 else { return (w, h) }
        let rad = rotationDegrees * .pi / 180
        let cosA = abs(cos(rad))
        let sinA = abs(sin(rad))
        return (w * cosA + h * sinA, w * sinA + h * cosA)
    }

    /// Expands a measured size to account for rotation if the node has one.
    ///
    /// A group is no exception: Pen grows a turned group's slot in a flex flow to the
    /// bounds of its children's union turned (`render-free-groups.pen`'s `flexrot`).
    static func applyRotationExpansion(
        width: Double, height: Double, node: PenNode
    ) -> (width: Double, height: Double) {
        guard let rotation = node.common.rotation?.literalValue, rotation != 0 else {
            return (width, height)
        }
        return rotatedBoundingBox(width: width, height: height, rotationDegrees: rotation)
    }
}

// MARK: - Tree Helpers

extension PenLayoutEngine {
    /// Returns the direct children of a node, or `nil` for leaf nodes.
    static func nodeChildren(_ node: PenNode) -> [PenNode]? {
        switch node.kind {
        case let .frame(data): data.children
        case let .group(data): data.children
        default: nil
        }
    }

    /// Short-circuits layout for leaf nodes with fixed width and height.
    /// Returns the rect it wrote if the short-circuit applied, `nil` otherwise.
    @discardableResult
    static func tryShortCircuitFixedLeaf(
        _ child: PenNode,
        x: Double,
        y: Double,
        into rects: inout [String: PenRect]
    ) -> PenRect? {
        guard !child.kind.canHaveChildren else { return nil }
        // A note's, prompt's or context's fixed height is its least: it grows to fit its text.
        if PenPostIt.Variant(child.kind) != nil { return nil }
        let wSizing = extractLeafWidth(child.kind)
        let hSizing = extractLeafHeight(child.kind)
        guard case let .fixed(w) = wSizing, case let .fixed(h) = hSizing else { return nil }
        let rect = freeRect(of: child, x: x, y: y, width: w, height: h)
        rects[child.id] = rect
        return rect
    }
}

// MARK: - Subtree Layout

private extension PenLayoutEngine {
    /// Searches the tree for a node by ID, returning both the node and its parent — the
    /// first match in pre-order.
    static func findNodeWithParent(
        id: String,
        in nodes: [PenNode],
        parent: PenNode?
    ) -> (node: PenNode, parent: PenNode?)? {
        var pending: [(node: PenNode, parent: PenNode?)] = nodes.reversed().map { ($0, parent) }
        while let next = pending.popLast() {
            if next.node.id == id { return next }
            pending.append(contentsOf: (nodeChildren(next.node) ?? []).reversed().map { ($0, next.node) })
        }
        return nil
    }

    /// Derives the available width/height that a parent would offer to a child during layout.
    static func deriveAvailableDimensions(
        parent: PenNode?,
        existingRects: [String: PenRect]
    ) -> (width: Double?, height: Double?) {
        guard let parent, let parentRect = existingRects[parent.id] else {
            return (nil, nil) // Top-level: unconstrained, matching layout() behavior
        }
        let props = extractLayoutProperties(parent)
        let availableWidth = parentRect.width - props.padding.left - props.padding.right
        let availableHeight = parentRect.height - props.padding.top - props.padding.bottom
        return (availableWidth, availableHeight)
    }

    /// Shared implementation for both cached and uncached subtree layout.
    static func layoutSubtreeImpl(
        rootID: String,
        in document: PenDocument,
        existingRects: [String: PenRect],
        textMeasurer: TextMeasurer,
        memo: inout Memo
    ) -> [String: PenRect] {
        guard let (node, parent) = findNodeWithParent(
            id: rootID, in: document.children, parent: nil
        ) else {
            return [:]
        }

        let (availableWidth, availableHeight) = deriveAvailableDimensions(
            parent: parent, existingRects: existingRects
        )

        var rects: [String: PenRect] = [:]
        let size = layoutNode(
            node, availableWidth: availableWidth, availableHeight: availableHeight,
            textMeasurer: textMeasurer, into: &rects, memo: &memo
        )

        // layoutNode writes descendant rects but NOT the root's own rect. A node placed by
        // its own x/y lands where its anchor and its new size put it, as in a full layout;
        // a flow child keeps the position its parent gave it (existingRects), grown to its
        // turned bounds as the flow grows it.
        let isFree = parent.map {
            extractLayoutProperties($0).layout == .none || node.common.layoutPosition == .absolute
        } ?? true
        let declaredX = node.common.x?.literalValue ?? 0
        let declaredY = node.common.y?.literalValue ?? 0
        if isFree {
            rects[rootID] = freeRect(of: node, x: declaredX, y: declaredY, size: size, placedIn: rects)
        } else {
            let turned = applyRotationExpansion(width: size.width, height: size.height, node: node)
            let rotation = node.common.rotation?.literalValue ?? 0
            rects[rootID] = PenRect(
                x: existingRects[rootID]?.x ?? declaredX, y: existingRects[rootID]?.y ?? declaredY,
                width: turned.width, height: turned.height,
                unturnedSize: rotation == 0 ? nil : PenSize(width: size.width, height: size.height)
            )
        }

        return rects
    }
}

// MARK: - Size Resolution

extension PenLayoutEngine {
    static func resolveIntrinsicSize(_ sizing: PenSizing, available: Double?) -> (size: Double, isFlexible: Bool, fallback: Double?) {
        switch sizing {
        case let .fixed(v):
            return (v, false, nil)
        case let .fitContent(fallback):
            return (fallback ?? 0, false, fallback)
        case let .fillContainer(fallback):
            if let available {
                return (available, true, fallback)
            }
            return (fallback ?? 0, true, fallback)
        case .variable:
            return (0, false, nil)
        }
    }

    static func resolveContainerSize(_ sizing: PenSizing, contentSize: Double, available: Double?) -> (size: Double, isFlexible: Bool, fallback: Double?) {
        switch sizing {
        case let .fixed(v):
            return (v, false, nil)
        case let .fitContent(fallback):
            let size = contentSize > 0 ? contentSize : (fallback ?? 0)
            return (size, false, fallback)
        case let .fillContainer(fallback):
            if let available {
                return (available, true, fallback)
            }
            // No parent to fill. If the author declared a fallback, honor it —
            // `fill_container(N)` means "use N when standalone." Otherwise fall
            // back to the measured content size.
            if let fallback {
                return (fallback, true, fallback)
            }
            return (contentSize, true, nil)
        case .variable:
            return (0, false, nil)
        }
    }
}

// MARK: - Leaves

extension PenLayoutEngine {
    /// The size of a node with no children: its declared sizes, or its text measured.
    ///
    /// - Parameters:
    ///   - props: The node's layout properties.
    ///   - availableWidth: The width its parent offers it.
    ///   - availableHeight: The height its parent offers it.
    ///   - textMeasurer: A function that measures text bounding boxes.
    /// - Returns: The node's size.
    static func layoutLeafNode(
        _ props: NodeLayoutProperties,
        availableWidth: Double?,
        availableHeight: Double?,
        textMeasurer: TextMeasurer
    ) -> (width: Double, height: Double) {
        // Resolve width first — text height may depend on it (wrapping)
        let (resolvedWidth, _, _) = resolveIntrinsicSize(props.widthSizing, available: availableWidth)

        if let noteText = props.noteText {
            let (setHeight, _, _) = resolveIntrinsicSize(props.heightSizing, available: availableHeight)
            let grown = grownNoteHeight(
                noteText, insets: props.noteInsets ?? PenPostIt.textInsets,
                width: resolvedWidth, setHeight: setHeight, textMeasurer: textMeasurer
            )
            return (resolvedWidth, grown)
        }

        // Check if text measurement can provide intrinsic sizing
        if let textInput = props.textInput,
           textInput.textGrowth != .fixedWidthHeight
        {
            let needsWidthFromText = props.widthSizing.isFitContent && textInput.textGrowth != .fixedWidth
            let needsHeightFromText = props.heightSizing.isFitContent

            let text = textInput.request.text
            if !text.isEmpty, needsWidthFromText || needsHeightFromText {
                // For width measurement: unconstrained unless width is already resolved
                let measureMaxWidth: Double? = needsWidthFromText ? nil : resolvedWidth

                var request = textInput.request
                request.maxWidth = measureMaxWidth
                let measured = textMeasurer(request)

                let w = needsWidthFromText ? measured.width : resolvedWidth
                let h = needsHeightFromText ? measured.height : resolveIntrinsicSize(props.heightSizing, available: availableHeight).size
                return (w, h)
            }

            // Empty text node: use one line height as the intrinsic height
            // so it still occupies vertical space in layout (matching Pen's behavior).
            if text.isEmpty, needsHeightFromText {
                let oneLineHeight = textMeasurer(textInput.request.measuring(" ", maxWidth: nil, runs: []))
                return (0, oneLineHeight.height)
            }
        }

        let (h, _, _) = resolveIntrinsicSize(props.heightSizing, available: availableHeight)
        return (resolvedWidth, h)
    }
}
