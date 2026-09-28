//
//  ActivityRow.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// One line of the activity feed: time, identity, verb, path.
///
/// Columnar and single-line on purpose — the feed is scanned, not read, and a row that
/// wraps destroys the column alignment that makes scanning possible. The path is
/// truncated with an ellipsis and the whole row expands to show what was left out.
///
/// The expander is a `<details>`, so it works with the script switched off. Nothing on
/// this page needs JavaScript to be usable; JavaScript only keeps it live.
public struct ActivityRow: HTML {
    /// Creates a row.
    ///
    /// - Parameters:
    ///   - event: The activity-log event to draw.
    ///   - clock: The moment the page is rendered for.
    ///   - showsFile: Whether to prefix the path with the file's name, which the
    ///     cross-file dashboard needs and a single file's feed does not.
    public init(event: ActivityEvent, clock: ViewerClock, showsFile: Bool = false) {
        self.event = event
        self.clock = clock
        self.showsFile = showsFile
    }

    /// The event to draw.
    public let event: ActivityEvent

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// Whether to prefix the path with the file's name.
    public let showsFile: Bool

    /// The file's name without its extension or directory.
    var fileName: String {
        URL(fileURLWithPath: event.file).deletingPathExtension().lastPathComponent
    }

    /// What the row says happened, in the path column.
    ///
    /// The first name path, because an edit that touched several nodes is still one
    /// action and the rest are one click away. An event that touched none — a variable
    /// or theme write — says how many operations it carried instead, which is the only
    /// true thing there is to say about it in one column.
    public var summaryText: String {
        let subject = event.paths.first ?? event.nodes.first ?? operationsText
        let extra = max(0, event.paths.count - 1)
        let suffix = extra > 0 ? " +\(extra)" : ""
        return showsFile ? "\(fileName) · \(subject)\(suffix)" : "\(subject)\(suffix)"
    }

    /// How many operations an event carried, as text.
    var operationsText: String {
        let count = event.inverse.count
        return "\(count) \(count == 1 ? "op" : "ops")"
    }

    public var body: some HTML {
        details(.class("v-row v-activity-row"), .data("identity", value: event.identity)) {
            summary(.class("v-activity-summary")) {
                span(.class("v-activity-time"), .title(clock.age(event.time, style: .long))) {
                    clock.time(event.time)
                }
                AvatarView(identity: event.identity)
                IdentityHandle(event.identity, className: "v-activity-identity")
                span(.class("v-activity-verb")) { event.op.rawValue }
                span(.class("v-activity-path")) { bdi { summaryText } }
            }
            div(.class("v-activity-detail")) {
                p(.class("v-activity-file")) { event.file }
                p(.class("v-activity-rev")) { "rev \(event.revision)" }
                if !event.nodes.isEmpty {
                    ul(.class("v-activity-nodes")) {
                        for (index, node) in event.nodes.enumerated() {
                            li {
                                span(.class("v-activity-node-path")) {
                                    index < event.paths.count ? event.paths[index] : node
                                }
                                IdChip(id: node, extraClasses: "v-mono v-activity-node-id")
                            }
                        }
                    }
                }
                if let batch = event.batch {
                    p(.class("v-activity-batch")) { "batch \(batch)" }
                }
            }
        }
    }
}
