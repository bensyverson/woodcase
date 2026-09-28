//
//  DocumentLinter+Scroll.swift
//  Woodcase
//

import Foundation

/// What a node's `common.metadata._scroll` key says about its designed overflow.
///
/// `_scroll` follows the `_role`/`_props` underscore-key convention ``ComponentAnalyzer``
/// reads: an extension of ``PenMetadata`` a document author sets, and Pen.app's own
/// schema carries verbatim through a resave.
private enum DeclaredScrollAxis {
    /// No `_scroll` key at all.
    case none

    /// `_scroll` is `"vertical"` or `"horizontal"`.
    case axis(TreeRow.OverflowAxis)

    /// `_scroll` is set to something else, described the way the value reads in the
    /// file — quoted for a string, named for anything else — for a warning to quote.
    case invalid(String)
}

/// The scroll-aware half of the ``LintCheck/clipped`` check.
///
/// Every other geometric check in `DocumentLinter.swift` asks about one row against
/// its parent in isolation. This one has to see a parent's *other* children too — to
/// count how many overflow the same axis before folding them into one finding — so it
/// runs once over the whole listing, the same shape ``DocumentLinter/artboardOverlaps(rows:in:)``
/// and ``DocumentLinter/duplicateNames(rows:)`` already use, and its findings are
/// merged into ``DocumentLinter/findings(in:root:theme:diagnostics:)`` the same way.
///
/// It keeps the check id `clipped` rather than minting a new one: every finding here
/// is still "this rect doesn't fit," just reported once for the frame instead of once
/// per child when nothing says the overflow is designed, so `--exclude clipped`
/// continues to exclude all of it with no second id for a caller to remember.
///
/// ## The three behaviours
///
/// A row's parent must be a `frame` with `clip:true` for any of this to apply — a
/// `group` has no `clip` flag, and a frame that does not clip shows every pixel of an
/// overflowing child regardless of what `_scroll` says. Against such a frame:
///
/// 1. **A valid `_scroll`.** A child whose ``TreeRow/overflowAxes`` is exactly the
///    declared axis is not a finding, however far past the fold it goes — that is the
///    scroll working as designed. A child that also crosses the cross axis keeps its
///    ``DocumentLinter/clipped(_:parent:)`` finding unchanged.
/// 2. **No `_scroll` (or an invalid one).** When the frame itself stacks its children
///    on an axis (``PenNode/FrameData/layout`` is `.horizontal` or `.vertical`), every
///    child whose overflow is exactly that stacking axis is folded into one finding
///    on the frame, naming how many and how far the farthest continues, and
///    proposing the `_scroll` value that would quiet them. A freeform frame
///    (`layout: none`) has no stacking axis to collapse onto, so nothing here applies
///    and every overflowing child keeps its own finding.
/// 3. **An invalid `_scroll`.** Whatever kind of node carries it, a `_scroll` value
///    that is not `"vertical"` or `"horizontal"` is its own finding, on top of
///    whichever of the two behaviours above applies as if it were absent.
extension DocumentLinter {
    /// Findings for the ``LintCheck/clipped`` check, keyed by the row each is
    /// reported on.
    ///
    /// - Parameters:
    ///   - rows: The rows of the listing being linted, in pre-order.
    ///   - context: The settled tree, for reading a clipping frame's own `clip` flag
    ///     and `_scroll` metadata the same way every other check reads a node.
    /// - Returns: Row id → the findings to report on that row, in document order.
    static func clippedFindings(rows: [TreeRow], in context: Context) -> [String: [LintFinding]] {
        var byRow: [String: [LintFinding]] = [:]
        var childrenByParent: [String: [TreeRow]] = [:]
        var ancestors: [TreeRow] = []
        for row in rows {
            while let last = ancestors.last, last.depth >= row.depth {
                ancestors.removeLast()
            }
            if let parent = ancestors.last {
                childrenByParent[parent.id, default: []].append(row)
            }
            ancestors.append(row)
        }

        for row in rows {
            if let node = context.resolved(row), let invalid = invalidScrollFinding(row, node: node) {
                byRow[row.id, default: []].append(invalid)
            }

            let overflowing = (childrenByParent[row.id] ?? []).filter { $0.clip != .none }
            guard !overflowing.isEmpty else { continue }

            guard let node = context.resolved(row),
                  case let .frame(data) = node.kind,
                  data.clip?.literalValue == true
            else {
                for child in overflowing {
                    byRow[child.id, default: []].append(contentsOf: clipped(child, parent: row))
                }
                continue
            }

            switch declaredScrollAxis(node.common.metadata) {
            case let .axis(declared):
                for child in overflowing where child.overflowAxes != [declared] {
                    byRow[child.id, default: []].append(contentsOf: clipped(child, parent: row))
                }
            case .none, .invalid:
                let stacking = stackingAxis(of: data)
                var collapsible: [TreeRow] = []
                for child in overflowing {
                    if let stacking, child.overflowAxes == [stacking] {
                        collapsible.append(child)
                    } else {
                        byRow[child.id, default: []].append(contentsOf: clipped(child, parent: row))
                    }
                }
                if let stacking, !collapsible.isEmpty {
                    byRow[row.id, default: []].append(
                        collapsedFinding(row, node: node, axis: stacking, children: collapsible)
                    )
                }
            }
        }
        return byRow
    }

    // MARK: - Reading the annotation

    /// The axis a frame's own layout stacks its children on, or `nil` for a freeform
    /// (`layout: none`, or absent) frame, which has no single axis to collapse an
    /// overflow onto.
    ///
    /// `data.layout` is a `PenLayoutDirection?` whose wrapped type has its own
    /// `.none` case (the authored `"layout": "none"`), so this unwraps first rather
    /// than switching over the optional directly — `case .none` there would match
    /// only the *absent* key, not the far more common explicit `"none"`.
    private static func stackingAxis(of data: PenNode.FrameData) -> TreeRow.OverflowAxis? {
        guard let layout = data.layout else { return nil }
        switch layout {
        case .horizontal: return .horizontal
        case .vertical: return .vertical
        case .none: return nil
        }
    }

    /// Parses a node's `_scroll` metadata extension.
    private static func declaredScrollAxis(_ metadata: PenMetadata?) -> DeclaredScrollAxis {
        guard let raw = metadata?["_scroll"] else { return .none }
        guard case let .string(value) = raw else { return .invalid(describe(raw)) }
        if value == TreeRow.OverflowAxis.horizontal.rawValue { return .axis(.horizontal) }
        if value == TreeRow.OverflowAxis.vertical.rawValue { return .axis(.vertical) }
        return .invalid("\"\(value)\"")
    }

    /// A metadata value the way it would read quoted in a finding.
    private static func describe(_ value: AnyCodable) -> String {
        switch value {
        case .null: "null"
        case let .bool(value): "\(value)"
        case let .int(value): "\(value)"
        case let .double(value): "\(value)"
        case let .string(value): "\"\(value)\""
        case .array: "an array"
        case .dictionary: "an object"
        }
    }

    // MARK: - Findings

    /// The one finding for a `_scroll` value that is not `"vertical"` or
    /// `"horizontal"`, on whatever node carries it — a stray key is as much a
    /// mistake on a node that never clips as on one that does.
    private static func invalidScrollFinding(_ row: TreeRow, node: PenNode) -> LintFinding? {
        guard case let .invalid(described) = declaredScrollAxis(node.common.metadata) else { return nil }
        return LintFinding(
            check: .clipped,
            nodeID: row.id,
            path: row.address,
            message: "declares common.metadata._scroll=\(described), which is not a designed scroll axis. "
                + "Valid values are \"vertical\" and \"horizontal\"."
        )
    }

    /// One finding replacing several children's individual ``clipped(_:parent:)``
    /// findings: they all continue past the fold on the frame's own stacking axis,
    /// and nothing says whether that is a bug or a scrolling list.
    ///
    /// - Parameters:
    ///   - row: The clipping frame.
    ///   - node: The frame's settled node, for its current `_scroll` metadata.
    ///   - axis: The frame's stacking axis, which is also the axis every child in
    ///     `children` overflows on and nothing else.
    ///   - children: The children folded into this one finding, in document order.
    private static func collapsedFinding(
        _ row: TreeRow,
        node _: PenNode,
        axis: TreeRow.OverflowAxis,
        children: [TreeRow]
    ) -> LintFinding {
        let extent = axis == .horizontal ? (row.rect?.width ?? 0) : (row.rect?.height ?? 0)
        let total = children.map { pastTheFold(of: $0.rect, extent: extent, axis: axis) }.max() ?? 0
        return LintFinding(
            check: .clipped,
            nodeID: row.id,
            path: row.address,
            message: "\(children.count) children continue \(number(total))pt past the fold on the "
                + "\(axis.rawValue) axis, and \(name(of: row)) clips them. A designed scroll? Run "
                + "`woodcase set <file> \(row.address) common.metadata._scroll=\(axis.rawValue)` "
                + "to say so."
        )
    }

    /// How far past the frame's edge one child's rect continues on `axis` — the far
    /// edge for a child that overflows below or to the right, the near edge for one
    /// that overflows above or to the left, whichever the rect actually crosses.
    private static func pastTheFold(of rect: PenRect?, extent: Double, axis: TreeRow.OverflowAxis) -> Double {
        guard let rect else { return 0 }
        let origin = axis == .horizontal ? rect.x : rect.y
        let size = axis == .horizontal ? rect.width : rect.height
        return max(max(0, origin + size - extent), max(0, -origin))
    }
}
