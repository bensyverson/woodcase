//
//  PreviewFixtures.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// The sample data every preview state is built from.
///
/// One fixed moment, one clock, and a builder per production prop type with everything
/// overridable. The clock is pinned in UTC so a relative age renders the same in Berlin
/// and in Denver, and so a golden blessed on one machine passes on another.
///
/// ```swift
/// PreviewFixtures.row(id: "Ttl01", depth: 2, type: "text", name: "Title")
/// ```
///
/// These build the **production** types — `TreeRow`, `ActivityEvent`,
/// `FileListReport.Summary`, `ViewerPresence.Identity`, ``ArtboardLayout`` — never a
/// preview-shaped copy of one. A copy would drift from what the server can actually
/// produce, and then look like coverage.
public enum PreviewFixtures {
    /// The moment every preview renders at, so ages and clock columns are deterministic.
    public static let now = Date(timeIntervalSince1970: 1_772_000_000)

    /// A clock pinned to ``now`` in UTC, so a fixture blessed in Berlin passes in Denver.
    public static let clock = ViewerClock(now: now, timeZone: TimeZone(identifier: "UTC")!)

    /// An activity event, with everything overridable.
    ///
    /// - Parameters:
    ///   - secondsAgo: How long before ``now`` it happened.
    ///   - identity: The `--as` name that wrote it.
    ///   - op: What kind of write it was.
    ///   - file: The document it touched.
    ///   - nodes: The node ids it touched.
    ///   - paths: The name paths it touched.
    ///   - inverse: The operations that undo it — what a write touching no node counts
    ///     to say how big it was.
    ///   - revision: The revision it produced.
    ///   - batch: The transaction it belonged to, or `nil` for a write that stood alone.
    /// - Returns: The event.
    public static func event(
        secondsAgo: TimeInterval,
        identity: String = "claude-a",
        op: ActivityEvent.Kind = .set,
        file: String = "/Users/ana/Designs/banking.pen",
        nodes: [String] = ["Ttl01"],
        paths: [String] = ["Dashboard/Header/Title"],
        inverse: [EditOperation] = [],
        revision: String = "3f2a91c0d4e5b678",
        batch: String? = nil
    ) -> ActivityEvent {
        ActivityEvent(
            time: now.addingTimeInterval(-secondsAgo),
            identity: identity,
            file: URL(fileURLWithPath: file),
            op: op,
            nodes: nodes,
            paths: paths,
            inverse: inverse,
            revision: revision,
            batch: batch
        )
    }

    /// A tree row, with everything overridable.
    ///
    /// - Parameters:
    ///   - id: The node's id.
    ///   - address: The address it is reached by; defaults to its name, then to `#id`.
    ///   - rev: The document revision the row was read at.
    ///   - depth: How deep in the tree it sits.
    ///   - type: The node's `type` field.
    ///   - name: Its name, or `nil` for an unnamed node.
    ///   - rect: Its settled rectangle.
    ///   - clip: Whether it is clipped by its parent.
    ///   - isReusable: Whether it is a component definition.
    ///   - isInstance: Whether it is an instance of one.
    ///   - isSlot: Whether it is a slot.
    ///   - childCount: How many children it has.
    /// - Returns: The row.
    public static func row(
        id: String,
        address: String? = nil,
        rev: String = "0000000000000000",
        depth: Int = 0,
        type: String = "frame",
        name: String? = nil,
        rect: PenRect? = PenRect(x: 0, y: 0, width: 400, height: 300),
        clip: TreeRow.Clip = .none,
        isReusable: Bool = false,
        isInstance: Bool = false,
        isSlot: Bool = false,
        childCount: Int = 0
    ) -> TreeRow {
        TreeRow(
            id: id,
            address: address ?? name ?? "#\(id)",
            rev: rev,
            depth: depth,
            type: type,
            name: name,
            rect: rect,
            clip: clip,
            isReusable: isReusable,
            isInstance: isInstance,
            isSlot: isSlot,
            childCount: childCount,
            properties: nil
        )
    }

    /// A presence identity.
    ///
    /// - Parameters:
    ///   - name: The `--as` name it writes under.
    ///   - secondsAgo: How long before ``now`` it last wrote.
    ///   - events: How many events it has written.
    /// - Returns: The identity.
    public static func identity(
        _ name: String,
        secondsAgo: TimeInterval,
        events: Int = 4
    ) -> ViewerPresence.Identity {
        ViewerPresence.Identity(
            name: name,
            lastSeen: now.addingTimeInterval(-secondsAgo),
            events: events,
            files: ["a1b2c3d4e5f6"]
        )
    }

    /// A file summary for the dashboard.
    ///
    /// - Parameters:
    ///   - id: The file's viewer id.
    ///   - name: Its base name, which also spells its path.
    ///   - artboards: How many artboards to give it.
    ///   - lastChange: The last write the log saw, if any.
    ///   - error: Why the file could not be read, if it could not.
    /// - Returns: The summary.
    public static func summary(
        id: String,
        name: String,
        artboards: Int = 2,
        lastChange: FileListReport.LastChange? = nil,
        error: String? = nil
    ) -> FileListReport.Summary {
        FileListReport.Summary(
            id: id,
            path: "/Users/ana/Designs/\(name).pen",
            name: name,
            revision: error == nil ? "3f2a91c0d4e5b678" : nil,
            artboards: (0 ..< artboards).map {
                Artboard(id: "Cnv0\($0)", name: "Canvas \($0)", width: 400, height: 300)
            },
            lastChange: lastChange,
            error: error
        )
    }

    /// An artboard layout with a handful of boxes, one of them clipped.
    ///
    /// - Parameter scale: The density the render was made at.
    /// - Returns: The layout.
    public static func layout(scale: Double = 0.7) -> ArtboardLayout {
        ArtboardLayout(
            artboard: "Cnv01",
            width: 400,
            height: 300,
            scale: scale,
            revision: "3f2a91c0d4e5b678",
            nodes: [
                ArtboardLayout.Node(id: "Cnv01", path: "Dashboard", x: 0, y: 0, width: 400, height: 300),
                ArtboardLayout.Node(id: "Hdr01", path: "Dashboard/Header", x: 0, y: 0, width: 400, height: 64),
                ArtboardLayout.Node(id: "Ttl01", path: "Dashboard/Header/Title", x: 24, y: 20, width: 118, height: 24),
                ArtboardLayout.Node(
                    id: "Vr7Kd", path: "Dashboard/Cards/Customers",
                    x: 328, y: 24, width: 120, height: 172, clip: .partial
                ),
            ]
        )
    }
}
