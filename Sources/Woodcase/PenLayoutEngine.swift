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
    ///   - options: The cards drawn raw, which grow to fit their raw text too
    ///     (``PenLayoutOptions``). Defaults to none.
    /// - Returns: A dictionary mapping node IDs to their computed layout rectangles.
    public static func layout(
        _ document: PenDocument,
        textMeasurer: TextMeasurer = defaultTextMeasurer,
        options: PenLayoutOptions = PenLayoutOptions()
    ) -> [String: PenRect] {
        var rects: [String: PenRect] = [:]
        var memo = Memo()
        for node in document.children {
            let x = node.common.x?.literalValue ?? 0
            let y = node.common.y?.literalValue ?? 0
            let size = layoutNode(
                node, availableWidth: nil, availableHeight: nil,
                textMeasurer: textMeasurer, options: options, into: &rects, memo: &memo
            )
            rects[node.id] = freeRect(of: node, x: x, y: y, size: size, placedIn: rects)
        }
        return rects
    }
}

// MARK: - Cache Types

public extension PenLayoutEngine {
    /// A cached measurement result for a single node, keyed by available dimensions.
    ///
    /// Used by ``layoutIncremental(_:previousRects:dirtyNodeIDs:textMeasurer:options:measurementCache:)``
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
        /// A note's raw text, when the caller draws it raw (``PenLayoutOptions/rawBodies``):
        /// the note grows to fit it too (``PenLayoutEngine/noteRawTextRequest(_:)``).
        var noteRawText: PenTextMeasureRequest?
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
