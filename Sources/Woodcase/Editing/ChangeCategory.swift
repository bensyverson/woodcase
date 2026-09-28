//
//  ChangeCategory.swift
//  Woodcase
//

import Foundation

/// Classifies property changes for incremental layout invalidation.
///
/// The layout cache uses this to decide whether a change requires re-layout
/// (size/position changed) or only re-rendering (visual-only change like color).
public enum ChangeCategory: Friendly {
    /// Visual-only change (color, opacity, fills, stroke, effects, blendMode, etc.).
    /// The node needs re-rendering but its layout rect is unchanged.
    case renderOnly

    /// Size or position change (x, y, width, height, gap, padding, font props, etc.).
    /// The node and its ancestors need re-layout.
    case layout

    /// Structural change (insert, delete, move, variable/import changes).
    /// The entire layout cache must be invalidated.
    case structural

    // MARK: - Merging

    /// Merges two optional categories, returning the most severe.
    ///
    /// Severity order: `structural` > `layout` > `renderOnly` > `nil`.
    public static func merge(_ a: ChangeCategory?, _ b: ChangeCategory?) -> ChangeCategory? {
        switch (a, b) {
        case (.structural, _), (_, .structural):
            .structural
        case (.layout, _), (_, .layout):
            .layout
        case (.renderOnly, _), (_, .renderOnly):
            .renderOnly
        default:
            nil
        }
    }

    // MARK: - Common Properties

    /// Categorizes the change between two common property sets.
    ///
    /// Returns `nil` if nothing changed.
    public static func categorize(
        oldCommon: PenNodeCommon,
        newCommon: PenNodeCommon
    ) -> ChangeCategory? {
        guard oldCommon != newCommon else { return nil }

        // Layout-affecting common properties
        if oldCommon.x != newCommon.x
            || oldCommon.y != newCommon.y
            || oldCommon.rotation != newCommon.rotation
            || oldCommon.enabled != newCommon.enabled
            || oldCommon.layoutPosition != newCommon.layoutPosition
            || oldCommon.theme != newCommon.theme
        {
            return .layout
        }

        // Everything else in common is render-only:
        // name, opacity, flipX, flipY, reusable, context, metadata
        return .renderOnly
    }

    // MARK: - Kind Properties

    /// Categorizes the change between two kind-specific property sets.
    ///
    /// Returns `nil` if nothing changed.
    public static func categorize(
        oldKind: PenNode.Kind,
        newKind: PenNode.Kind
    ) -> ChangeCategory? {
        guard oldKind != newKind else { return nil }

        // Different kind types → always layout
        guard oldKind.typeName == newKind.typeName else {
            return .layout
        }

        switch (oldKind, newKind) {
        case let (.frame(old), .frame(new)):
            return categorizeFrame(old: old, new: new)
        case let (.text(old), .text(new)):
            return categorizeText(old: old, new: new)
        case let (.rectangle(old), .rectangle(new)):
            return categorizeRectangle(old: old, new: new)
        case let (.ellipse(old), .ellipse(new)):
            return categorizeEllipse(old: old, new: new)
        case let (.path(old), .path(new)):
            return categorizePath(old: old, new: new)
        case let (.group(old), .group(new)):
            return categorizeGroup(old: old, new: new)
        case let (.line(old), .line(new)):
            return categorizeLine(old: old, new: new)
        case let (.polygon(old), .polygon(new)):
            return categorizePolygon(old: old, new: new)
        case let (.icon(old), .icon(new)):
            return categorizeIcon(old: old, new: new)
        case let (.script(old), .script(new)):
            return categorizeScript(old: old, new: new)
        case let (.browser(old), .browser(new)):
            return categorizeBrowser(old: old, new: new)
        case (.connection, .connection):
            // A connection has no box and moves nothing: its endpoints and paint only
            // change what is drawn.
            return .renderOnly
        default:
            // ref, note, prompt, context, unknown — conservatively layout
            return .layout
        }
    }

    // MARK: - Per-Type Categorization

    private static func categorizeFrame(
        old: PenNode.FrameData,
        new: PenNode.FrameData
    ) -> ChangeCategory {
        // Layout-affecting frame properties
        if old.width != new.width
            || old.height != new.height
            || old.layout != new.layout
            || old.gap != new.gap
            || old.padding != new.padding
            || old.justifyContent != new.justifyContent
            || old.alignItems != new.alignItems
        {
            return .layout
        }
        // Render-only: fills, stroke, effects, blendMode, cornerRadius, clip, slot
        return .renderOnly
    }

    private static func categorizeText(
        old: PenNode.TextData,
        new: PenNode.TextData
    ) -> ChangeCategory {
        // Layout-affecting text properties
        if old.width != new.width
            || old.height != new.height
            || old.content != new.content
            || old.textGrowth != new.textGrowth
            || old.fontFamily != new.fontFamily
            || old.fontSize != new.fontSize
            || old.fontWeight != new.fontWeight
            || old.fontStyle != new.fontStyle
            || old.letterSpacing != new.letterSpacing
            || old.lineHeight != new.lineHeight
        {
            return .layout
        }
        // Render-only: textAlign, textAlignVertical, underline, strikethrough,
        // href, fills, stroke, effects, blendMode
        return .renderOnly
    }

    private static func categorizeRectangle(
        old: PenNode.RectangleData,
        new: PenNode.RectangleData
    ) -> ChangeCategory {
        if old.width != new.width || old.height != new.height {
            return .layout
        }
        return .renderOnly
    }

    private static func categorizeEllipse(
        old: PenNode.EllipseData,
        new: PenNode.EllipseData
    ) -> ChangeCategory {
        if old.width != new.width || old.height != new.height {
            return .layout
        }
        return .renderOnly
    }

    private static func categorizePath(
        old: PenNode.PathData,
        new: PenNode.PathData
    ) -> ChangeCategory {
        if old.width != new.width || old.height != new.height {
            return .layout
        }
        return .renderOnly
    }

    private static func categorizeGroup(
        old _: PenNode.GroupData,
        new _: PenNode.GroupData
    ) -> ChangeCategory {
        // A group has no layout properties of its own; its only remaining
        // fields — effects, blendMode — are both render-only. (`children`
        // is not compared here, matching frame: structural child changes
        // go through insert/delete/move, not this property diff.)
        .renderOnly
    }

    private static func categorizeLine(
        old: PenNode.LineData,
        new: PenNode.LineData
    ) -> ChangeCategory {
        if old.width != new.width || old.height != new.height {
            return .layout
        }
        return .renderOnly
    }

    private static func categorizePolygon(
        old: PenNode.PolygonData,
        new: PenNode.PolygonData
    ) -> ChangeCategory {
        if old.width != new.width || old.height != new.height {
            return .layout
        }
        return .renderOnly
    }

    private static func categorizeIcon(
        old: PenNode.IconData,
        new: PenNode.IconData
    ) -> ChangeCategory {
        if old.width != new.width || old.height != new.height {
            return .layout
        }
        return .renderOnly
    }

    private static func categorizeScript(
        old: PenNode.ScriptData,
        new: PenNode.ScriptData
    ) -> ChangeCategory {
        if old.width != new.width || old.height != new.height {
            return .layout
        }
        // Render-only: scriptUri, inputs, clip — none of these affect layout size.
        return .renderOnly
    }

    private static func categorizeBrowser(
        old: PenNode.BrowserData,
        new: PenNode.BrowserData
    ) -> ChangeCategory {
        if old.width != new.width || old.height != new.height {
            return .layout
        }
        // Render-only: the page's address, device, zoom and scroll, and the paint.
        return .renderOnly
    }
}
