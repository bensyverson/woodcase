//
//  PropertyDiff.swift
//  Woodcase
//

import Foundation

/// Computes the set of changed property paths between old and new values
/// of ``PenNodeCommon`` and ``PenNode/Kind``.
///
/// Property paths use a dot-separated format:
/// - Common properties: `"common.name"`, `"common.opacity"`, etc.
/// - Kind properties: `"kind.width"`, `"kind.fontSize"`, etc.
/// - Kind type change: `"kind.type"`
///
/// These paths are used by ``LWWPropertyMap`` for per-field conflict resolution.
public enum PropertyDiff {
    /// Compares two `PenNodeCommon` values and returns the set of changed property paths.
    ///
    /// All 13 common properties are compared individually.
    ///
    /// - Parameters:
    ///   - old: The previous common properties.
    ///   - new: The updated common properties.
    /// - Returns: A set of `"common.*"` paths for properties that differ.
    public static func diffCommon(old: PenNodeCommon, new: PenNodeCommon) -> Set<String> {
        var changed = Set<String>()

        if old.name != new.name { changed.insert("common.name") }
        if old.x != new.x { changed.insert("common.x") }
        if old.y != new.y { changed.insert("common.y") }
        if old.rotation != new.rotation { changed.insert("common.rotation") }
        if old.opacity != new.opacity { changed.insert("common.opacity") }
        if old.enabled != new.enabled { changed.insert("common.enabled") }
        if old.flipX != new.flipX { changed.insert("common.flipX") }
        if old.flipY != new.flipY { changed.insert("common.flipY") }
        if old.reusable != new.reusable { changed.insert("common.reusable") }
        if old.theme != new.theme { changed.insert("common.theme") }
        if old.context != new.context { changed.insert("common.context") }
        if old.layoutPosition != new.layoutPosition { changed.insert("common.layoutPosition") }
        if old.metadata != new.metadata { changed.insert("common.metadata") }

        return changed
    }

    /// Compares two `PenNode.Kind` values and returns the set of changed property paths.
    ///
    /// If the kind cases differ (e.g. rectangle → text), returns `"kind.type"` plus
    /// all property paths for both kinds, since every field effectively changed.
    ///
    /// If the kind cases are the same, compares each field individually.
    ///
    /// - Parameters:
    ///   - old: The previous kind value.
    ///   - new: The updated kind value.
    /// - Returns: A set of `"kind.*"` paths for properties that differ.
    public static func diffKind(old: PenNode.Kind, new: PenNode.Kind) -> Set<String> {
        switch (old, new) {
        case let (.frame(oldD), .frame(newD)):
            return diffFrame(old: oldD, new: newD)
        case let (.text(oldD), .text(newD)):
            return diffText(old: oldD, new: newD)
        case let (.rectangle(oldD), .rectangle(newD)):
            return diffRectangle(old: oldD, new: newD)
        case let (.ellipse(oldD), .ellipse(newD)):
            return diffEllipse(old: oldD, new: newD)
        case let (.path(oldD), .path(newD)):
            return diffPath(old: oldD, new: newD)
        case let (.group(oldD), .group(newD)):
            return diffGroup(old: oldD, new: newD)
        case let (.line(oldD), .line(newD)):
            return diffLine(old: oldD, new: newD)
        case let (.polygon(oldD), .polygon(newD)):
            return diffPolygon(old: oldD, new: newD)
        case let (.ref(oldD), .ref(newD)):
            return diffRef(old: oldD, new: newD)
        case let (.note(oldD), .note(newD)):
            return diffNote(old: oldD, new: newD)
        case let (.prompt(oldD), .prompt(newD)):
            return diffPrompt(old: oldD, new: newD)
        case let (.context(oldD), .context(newD)):
            return diffContext(old: oldD, new: newD)
        case let (.icon(oldD), .icon(newD)):
            return diffIcon(old: oldD, new: newD)
        case let (.script(oldD), .script(newD)):
            return diffScript(old: oldD, new: newD)
        case let (.browser(oldD), .browser(newD)):
            return diffBrowser(old: oldD, new: newD)
        case let (.connection(oldD), .connection(newD)):
            return diffConnection(old: oldD, new: newD)
        case let (.unknown(oldType, oldProps), .unknown(newType, newProps)):
            var changed = Set<String>()
            if oldType != newType { changed.insert("kind.type") }
            let allKeys = Set(oldProps.keys).union(Set(newProps.keys))
            for key in allKeys {
                if oldProps[key] != newProps[key] {
                    changed.insert("kind.\(key)")
                }
            }
            return changed
        default:
            // Different kind cases — everything changed
            var result: Set = ["kind.type"]
            result.formUnion(allKindKeys(old))
            result.formUnion(allKindKeys(new))
            return result
        }
    }

    // MARK: - Per-kind diff helpers

    /// Records the flat 2.17 stroke keys that differ between two strokable payloads.
    private static func diffStroke(
        old: some PenStrokable,
        new: some PenStrokable,
        into changed: inout Set<String>
    ) {
        if old.stroke != new.stroke { changed.insert("kind.stroke") }
        if old.strokeWidth != new.strokeWidth { changed.insert("kind.strokeWidth") }
        if old.strokeLinecap != new.strokeLinecap { changed.insert("kind.strokeLinecap") }
        if old.strokeLinejoin != new.strokeLinejoin { changed.insert("kind.strokeLinejoin") }
        if old.strokeAlignment != new.strokeAlignment { changed.insert("kind.strokeAlignment") }
    }

    private static func diffFrame(old: PenNode.FrameData, new: PenNode.FrameData) -> Set<String> {
        var changed = Set<String>()
        if old.width != new.width { changed.insert("kind.width") }
        if old.height != new.height { changed.insert("kind.height") }
        if old.cornerRadius != new.cornerRadius { changed.insert("kind.cornerRadius") }
        if old.clip != new.clip { changed.insert("kind.clip") }
        if old.fills != new.fills { changed.insert("kind.fills") }
        diffStroke(old: old, new: new, into: &changed)
        if old.effects != new.effects { changed.insert("kind.effects") }
        if old.blendMode != new.blendMode { changed.insert("kind.blendMode") }
        if old.layout != new.layout { changed.insert("kind.layout") }
        if old.gap != new.gap { changed.insert("kind.gap") }
        if old.padding != new.padding { changed.insert("kind.padding") }
        if old.justifyContent != new.justifyContent { changed.insert("kind.justifyContent") }
        if old.alignItems != new.alignItems { changed.insert("kind.alignItems") }
        if old.slot != new.slot { changed.insert("kind.slot") }
        return changed
    }

    private static func diffText(old: PenNode.TextData, new: PenNode.TextData) -> Set<String> {
        var changed = Set<String>()
        if old.width != new.width { changed.insert("kind.width") }
        if old.height != new.height { changed.insert("kind.height") }
        if old.content != new.content { changed.insert("kind.content") }
        if old.textGrowth != new.textGrowth { changed.insert("kind.textGrowth") }
        if old.fontFamily != new.fontFamily { changed.insert("kind.fontFamily") }
        if old.fontSize != new.fontSize { changed.insert("kind.fontSize") }
        if old.fontWeight != new.fontWeight { changed.insert("kind.fontWeight") }
        if old.fontStyle != new.fontStyle { changed.insert("kind.fontStyle") }
        if old.letterSpacing != new.letterSpacing { changed.insert("kind.letterSpacing") }
        if old.lineHeight != new.lineHeight { changed.insert("kind.lineHeight") }
        if old.textAlign != new.textAlign { changed.insert("kind.textAlign") }
        if old.textAlignVertical != new.textAlignVertical { changed.insert("kind.textAlignVertical") }
        if old.underline != new.underline { changed.insert("kind.underline") }
        if old.strikethrough != new.strikethrough { changed.insert("kind.strikethrough") }
        if old.href != new.href { changed.insert("kind.href") }
        if old.fills != new.fills { changed.insert("kind.fills") }
        diffStroke(old: old, new: new, into: &changed)
        if old.effects != new.effects { changed.insert("kind.effects") }
        if old.blendMode != new.blendMode { changed.insert("kind.blendMode") }
        return changed
    }

    private static func diffRectangle(old: PenNode.RectangleData, new: PenNode.RectangleData) -> Set<String> {
        var changed = Set<String>()
        if old.width != new.width { changed.insert("kind.width") }
        if old.height != new.height { changed.insert("kind.height") }
        if old.cornerRadius != new.cornerRadius { changed.insert("kind.cornerRadius") }
        if old.fills != new.fills { changed.insert("kind.fills") }
        diffStroke(old: old, new: new, into: &changed)
        if old.effects != new.effects { changed.insert("kind.effects") }
        if old.blendMode != new.blendMode { changed.insert("kind.blendMode") }
        return changed
    }

    private static func diffEllipse(old: PenNode.EllipseData, new: PenNode.EllipseData) -> Set<String> {
        var changed = Set<String>()
        if old.width != new.width { changed.insert("kind.width") }
        if old.height != new.height { changed.insert("kind.height") }
        if old.innerRadius != new.innerRadius { changed.insert("kind.innerRadius") }
        if old.startAngle != new.startAngle { changed.insert("kind.startAngle") }
        if old.sweepAngle != new.sweepAngle { changed.insert("kind.sweepAngle") }
        if old.fills != new.fills { changed.insert("kind.fills") }
        diffStroke(old: old, new: new, into: &changed)
        if old.effects != new.effects { changed.insert("kind.effects") }
        if old.blendMode != new.blendMode { changed.insert("kind.blendMode") }
        return changed
    }

    private static func diffPath(old: PenNode.PathData, new: PenNode.PathData) -> Set<String> {
        var changed = Set<String>()
        if old.width != new.width { changed.insert("kind.width") }
        if old.height != new.height { changed.insert("kind.height") }
        if old.geometry != new.geometry { changed.insert("kind.geometry") }
        if old.viewBox != new.viewBox { changed.insert("kind.viewBox") }
        if old.fillRule != new.fillRule { changed.insert("kind.fillRule") }
        if old.fills != new.fills { changed.insert("kind.fills") }
        diffStroke(old: old, new: new, into: &changed)
        if old.effects != new.effects { changed.insert("kind.effects") }
        if old.blendMode != new.blendMode { changed.insert("kind.blendMode") }
        return changed
    }

    private static func diffGroup(old: PenNode.GroupData, new: PenNode.GroupData) -> Set<String> {
        var changed = Set<String>()
        if old.effects != new.effects { changed.insert("kind.effects") }
        if old.blendMode != new.blendMode { changed.insert("kind.blendMode") }
        return changed
    }

    private static func diffLine(old: PenNode.LineData, new: PenNode.LineData) -> Set<String> {
        var changed = Set<String>()
        if old.width != new.width { changed.insert("kind.width") }
        if old.height != new.height { changed.insert("kind.height") }
        diffStroke(old: old, new: new, into: &changed)
        if old.effects != new.effects { changed.insert("kind.effects") }
        if old.blendMode != new.blendMode { changed.insert("kind.blendMode") }
        return changed
    }

    private static func diffPolygon(old: PenNode.PolygonData, new: PenNode.PolygonData) -> Set<String> {
        var changed = Set<String>()
        if old.width != new.width { changed.insert("kind.width") }
        if old.height != new.height { changed.insert("kind.height") }
        if old.polygonCount != new.polygonCount { changed.insert("kind.polygonCount") }
        if old.cornerRadius != new.cornerRadius { changed.insert("kind.cornerRadius") }
        if old.fills != new.fills { changed.insert("kind.fills") }
        diffStroke(old: old, new: new, into: &changed)
        if old.effects != new.effects { changed.insert("kind.effects") }
        if old.blendMode != new.blendMode { changed.insert("kind.blendMode") }
        return changed
    }

    private static func diffRef(old: PenNode.RefData, new: PenNode.RefData) -> Set<String> {
        var changed = Set<String>()
        if old.ref != new.ref { changed.insert("kind.ref") }
        if old.descendants != new.descendants { changed.insert("kind.descendants") }
        if old.rootOverrides != new.rootOverrides { changed.insert("kind.rootOverrides") }
        return changed
    }

    private static func diffNote(old: PenNode.NoteData, new: PenNode.NoteData) -> Set<String> {
        var changed = Set<String>()
        if old.content != new.content { changed.insert("kind.content") }
        return changed
    }

    private static func diffPrompt(old: PenNode.PromptData, new: PenNode.PromptData) -> Set<String> {
        var changed = Set<String>()
        if old.content != new.content { changed.insert("kind.content") }
        if old.model != new.model { changed.insert("kind.model") }
        return changed
    }

    private static func diffContext(old: PenNode.ContextData, new: PenNode.ContextData) -> Set<String> {
        var changed = Set<String>()
        if old.content != new.content { changed.insert("kind.content") }
        return changed
    }

    private static func diffIcon(old: PenNode.IconData, new: PenNode.IconData) -> Set<String> {
        var changed = Set<String>()
        if old.icon != new.icon { changed.insert("kind.icon") }
        if old.library != new.library { changed.insert("kind.library") }
        if old.weight != new.weight { changed.insert("kind.weight") }
        if old.width != new.width { changed.insert("kind.width") }
        if old.height != new.height { changed.insert("kind.height") }
        if old.fills != new.fills { changed.insert("kind.fills") }
        if old.effects != new.effects { changed.insert("kind.effects") }
        if old.blendMode != new.blendMode { changed.insert("kind.blendMode") }
        return changed
    }

    private static func diffScript(old: PenNode.ScriptData, new: PenNode.ScriptData) -> Set<String> {
        var changed = Set<String>()
        if old.scriptUri != new.scriptUri { changed.insert("kind.scriptUri") }
        if old.inputs != new.inputs { changed.insert("kind.inputs") }
        if old.clip != new.clip { changed.insert("kind.clip") }
        if old.width != new.width { changed.insert("kind.width") }
        if old.height != new.height { changed.insert("kind.height") }
        return changed
    }

    private static func diffConnection(old: PenNode.ConnectionData, new: PenNode.ConnectionData) -> Set<String> {
        var changed = Set<String>()
        if old.source != new.source { changed.insert("kind.source") }
        if old.target != new.target { changed.insert("kind.target") }
        diffStroke(old: old, new: new, into: &changed)
        return changed
    }

    private static func diffBrowser(old: PenNode.BrowserData, new: PenNode.BrowserData) -> Set<String> {
        var changed = Set<String>()
        if old.url != new.url { changed.insert("kind.url") }
        if old.deviceId != new.deviceId { changed.insert("kind.deviceId") }
        if old.zoom != new.zoom { changed.insert("kind.zoom") }
        if old.scrollX != new.scrollX { changed.insert("kind.scrollX") }
        if old.scrollY != new.scrollY { changed.insert("kind.scrollY") }
        if old.cornerRadius != new.cornerRadius { changed.insert("kind.cornerRadius") }
        if old.width != new.width { changed.insert("kind.width") }
        if old.height != new.height { changed.insert("kind.height") }
        diffStroke(old: old, new: new, into: &changed)
        if old.effects != new.effects { changed.insert("kind.effects") }
        return changed
    }

    /// Returns all property paths for a given kind case (used when kinds differ entirely).
    ///
    /// A node of a type Woodcase has no schema for keeps whatever keys the file carried,
    /// so its vocabulary is the keys it holds; every known type answers from the table
    /// below, which `woodcase schema` prints and needs no node to read.
    static func allKindKeys(_ kind: PenNode.Kind) -> Set<String> {
        if case let .unknown(_, properties) = kind {
            return Set(properties.keys.map { "kind.\($0)" })
        }
        guard let type = kind.nodeType else { return [] }
        return allKindKeys(type)
    }

    /// Returns all property paths a node of this type accepts.
    ///
    /// - Parameter type: The node type to list.
    /// - Returns: Every `kind.*` path the codec reads and writes on that type.
    public static func allKindKeys(_ type: PenNode.NodeType) -> Set<String> {
        switch type {
        case .frame:
            Set(["kind.width", "kind.height", "kind.cornerRadius", "kind.clip",
                 "kind.fills", "kind.stroke", "kind.strokeWidth",
                 "kind.strokeLinecap", "kind.strokeLinejoin", "kind.strokeAlignment",
                 "kind.effects", "kind.blendMode",
                 "kind.layout", "kind.gap", "kind.padding", "kind.justifyContent", "kind.alignItems",
                 "kind.slot"])
        case .text:
            Set(["kind.width", "kind.height", "kind.content", "kind.textGrowth",
                 "kind.fontFamily", "kind.fontSize", "kind.fontWeight", "kind.fontStyle",
                 "kind.letterSpacing", "kind.lineHeight", "kind.textAlign", "kind.textAlignVertical",
                 "kind.underline", "kind.strikethrough", "kind.href",
                 "kind.fills", "kind.stroke", "kind.strokeWidth",
                 "kind.strokeLinecap", "kind.strokeLinejoin", "kind.strokeAlignment",
                 "kind.effects", "kind.blendMode"])
        case .rectangle:
            Set(["kind.width", "kind.height", "kind.cornerRadius",
                 "kind.fills", "kind.stroke", "kind.strokeWidth",
                 "kind.strokeLinecap", "kind.strokeLinejoin", "kind.strokeAlignment",
                 "kind.effects", "kind.blendMode"])
        case .ellipse:
            Set(["kind.width", "kind.height", "kind.innerRadius", "kind.startAngle", "kind.sweepAngle",
                 "kind.fills", "kind.stroke", "kind.strokeWidth",
                 "kind.strokeLinecap", "kind.strokeLinejoin", "kind.strokeAlignment",
                 "kind.effects", "kind.blendMode"])
        case .path:
            Set(["kind.width", "kind.height", "kind.geometry", "kind.viewBox", "kind.fillRule",
                 "kind.fills", "kind.stroke", "kind.strokeWidth",
                 "kind.strokeLinecap", "kind.strokeLinejoin", "kind.strokeAlignment",
                 "kind.effects", "kind.blendMode"])
        case .group:
            Set(["kind.effects", "kind.blendMode"])
        case .line:
            Set(["kind.width", "kind.height", "kind.stroke", "kind.strokeWidth",
                 "kind.strokeLinecap", "kind.strokeLinejoin", "kind.strokeAlignment",
                 "kind.effects", "kind.blendMode"])
        case .polygon:
            Set(["kind.width", "kind.height", "kind.polygonCount", "kind.cornerRadius",
                 "kind.fills", "kind.stroke", "kind.strokeWidth",
                 "kind.strokeLinecap", "kind.strokeLinejoin", "kind.strokeAlignment",
                 "kind.effects", "kind.blendMode"])
        case .ref:
            Set(["kind.ref", "kind.descendants", "kind.rootOverrides"])
        case .note:
            Set(["kind.content"])
        case .prompt:
            Set(["kind.content", "kind.model"])
        case .context:
            Set(["kind.content"])
        case .icon:
            Set(["kind.icon", "kind.library", "kind.weight",
                 "kind.width", "kind.height", "kind.fills", "kind.effects", "kind.blendMode"])
        case .script:
            Set(["kind.scriptUri", "kind.inputs", "kind.clip", "kind.width", "kind.height"])
        case .browser:
            Set(["kind.url", "kind.deviceId", "kind.zoom", "kind.scrollX", "kind.scrollY",
                 "kind.cornerRadius", "kind.width", "kind.height",
                 "kind.stroke", "kind.strokeWidth",
                 "kind.strokeLinecap", "kind.strokeLinejoin", "kind.strokeAlignment",
                 "kind.effects"])
        case .connection:
            Set(["kind.source", "kind.target",
                 "kind.stroke", "kind.strokeWidth",
                 "kind.strokeLinecap", "kind.strokeLinejoin", "kind.strokeAlignment"])
        }
    }
}
