//
//  PenSchema+Defaults.swift
//  Woodcase
//

import Foundation

/// What each property is when a node leaves it unset, as the layout engine and the
/// renderer read it — the source of ``PenSchemaTable/Property/default``.
///
/// Each value is the one the engine falls back to, named from the constant it uses where
/// there is one (``PenTextStyle/defaultFontSize``, ``PenPostIt/defaultFontSize``); where
/// the engine spells a fallback inline (`data.layout ?? .horizontal` in
/// `PenLayoutEngine.extractLayoutProperties`), `PenSchemaDefaultEngineTests` draws the
/// property unset against it set to the value here, so the two cannot drift.
///
/// A property is left out when unset means nothing is drawn in its place (`fills`,
/// `effects`, `stroke`), when the engine never reads it (`name`, `reusable`, a browser's
/// `zoom`), or when its absence is a state of its own (a ref's `descendants`).
extension PenSchema {
    /// The default of one property on one node type, or `nil` when it has none.
    ///
    /// - Parameters:
    ///   - path: A `common.*` or `kind.*` path.
    ///   - type: The node type, or `nil` for a `common.*` row, whose defaults are the
    ///     same on every type.
    /// - Returns: The default.
    static func unsetDefault(of path: String, on type: PenNode.NodeType?) -> PenPropertyDefault? {
        if let common = commonDefaults[path] { return common }
        guard let type else { return nil }
        if postItTypes.contains(type), let postIt = postItDefaults(of: path, on: type) { return postIt }
        if path == widthPath || path == heightPath {
            return fitContentTypes.contains(type) ? .string(fitContent) : nil
        }
        return kindDefaults[path]
    }

    // MARK: - Private

    private static let widthPath = "kind.width"
    private static let heightPath = "kind.height"

    /// The sizing spelling that hugs content, as the `width` shape spells it.
    private static let fitContent = "fit_content"

    /// The types a note's text style and size defaults apply to.
    private static let postItTypes: Set<PenNode.NodeType> = [.note, .prompt, .context]

    /// The types whose unset width and height lay out as `fit_content`
    /// (`PenLayoutEngine.extractLeafWidth`, and a frame's own sizing).
    private static let fitContentTypes: Set<PenNode.NodeType> = [
        .frame, .text, .rectangle, .ellipse, .line, .polygon, .path, .icon, .script, .browser,
    ]

    /// Placement and appearance, the same on every node.
    private static let commonDefaults: [String: PenPropertyDefault] = [
        "common.x": .number(0),
        "common.y": .number(0),
        "common.rotation": .number(0),
        "common.opacity": .number(1),
        "common.enabled": .boolean(true),
        "common.flipX": .boolean(false),
        "common.flipY": .boolean(false),
        "common.layoutPosition": .string(PenLayoutPosition.auto.rawValue),
    ]

    /// The `kind.*` defaults, the same on every type that takes the property.
    private static let kindDefaults: [String: PenPropertyDefault] = [
        // Layout (`PenLayoutEngine.extractLayoutProperties`).
        "kind.layout": .string(PenLayoutDirection.horizontal.rawValue),
        "kind.gap": .number(0),
        "kind.padding": .number(0),
        "kind.justifyContent": .string(PenJustifyContent.start.rawValue),
        "kind.alignItems": .string(PenAlignItems.start.rawValue),
        "kind.clip": .boolean(false),
        // Shape geometry (`PenShapeGeometry`).
        "kind.cornerRadius": .number(0),
        "kind.innerRadius": .number(0),
        "kind.startAngle": .number(0),
        "kind.sweepAngle": .number(360),
        "kind.polygonCount": .number(Double(PenShapeGeometry.defaultPolygonCount)),
        "kind.fillRule": .string(PenFillRule.nonzero.rawValue),
        // Stroke (`PenStrokable.uniformStrokeWidth`, `PenStrokeRenderer.Style`).
        "kind.strokeWidth": .number(1),
        "kind.strokeAlignment": .string(PenStrokeAlign.center.rawValue),
        "kind.strokeLinejoin": .string(PenStrokeJoin.miter.rawValue),
        "kind.strokeLinecap": .string(PenStrokeCap.butt.rawValue),
        "kind.blendMode": .string(PenBlendMode.normal.rawString),
        // Text (`PenTextStyle.init(_:)`, and the measurer for growth).
        "kind.textGrowth": .string(PenTextGrowth.auto.rawValue),
        "kind.fontFamily": .string(PenTextStyle.defaultFontFamily),
        "kind.fontSize": .number(PenTextStyle.defaultFontSize),
        "kind.fontWeight": .string(String(Int(PenTextStyle.defaultFontWeight))),
        "kind.fontStyle": .string(PenFontFace.Style.normal.rawValue),
        "kind.letterSpacing": .derived(.fontKerning),
        "kind.lineHeight": .derived(.fontLineHeight),
        "kind.textAlign": .string(PenTextAlign.left.rawValue),
        "kind.textAlignVertical": .string(PenTextAlignVertical.top.rawValue),
        "kind.underline": .boolean(false),
        "kind.strikethrough": .boolean(false),
    ]

    /// A note's, prompt's or context's own defaults (`PenNode.noteTextStyle`,
    /// `PenPostIt.layoutSizing`), or `nil` where it takes the shared one.
    private static func postItDefaults(of path: String, on type: PenNode.NodeType) -> PenPropertyDefault? {
        let isNote = type == .note
        switch path {
        case "kind.fontSize": return .number(PenPostIt.defaultFontSize)
        case "kind.lineHeight": return .number(PenPostIt.defaultLineHeight)
        case widthPath: return .number(isNote ? PenPostIt.defaultSize : PenPostIt.cardDefaultWidth)
        case heightPath: return .number(isNote ? PenPostIt.defaultSize : PenPostIt.cardDefaultHeight)
        default: return nil
        }
    }
}
