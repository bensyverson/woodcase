//
//  PreviewState.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// One illustrative state of a component: what it is called, what to look at, and the
/// markup it produces.
///
/// A state renders the **production** component from **production** prop types — a
/// `TreeRow`, a `FileListReport.Summary`, a `ViewState`. A preview-shaped twin of those
/// would drift: it renders states production cannot reach and misses ones it does, and
/// then looks like coverage.
///
/// ```swift
/// PreviewState(
///     slug: "small",
///     name: "Small",
///     note: "The row-sized disc. The initial is centred and the hue is the identity's.",
///     frame: .strip
/// ) { AvatarView(identity: "claude-a", size: .small) }
/// ```
///
/// The component is type-erased behind the closure the initialiser captures, which is
/// why this is `Sendable` but not `Friendly`: a closure is neither `Codable` nor
/// `Equatable`. Everything a reader — or a JSON listing — needs is in ``metadata``,
/// which is both. Write the closure so it captures nothing: build the props inside it
/// from ``PreviewFixtures`` and literals, and it stays sendable however the component's
/// own types are declared.
public struct PreviewState: Sendable {
    /// A state's describable half: everything about it except the markup.
    ///
    /// Split out so the catalog can be listed, compared and serialised without the
    /// closure that renders it.
    public struct Metadata: Friendly {
        /// Creates a state's metadata.
        ///
        /// - Parameters:
        ///   - slug: The URL segment naming this state within its component.
        ///   - name: The heading a reader sees above the state.
        ///   - note: What a reviewer should look at here.
        ///   - frame: The production surface the state is shown on.
        ///   - pinnedWidth: The width in CSS pixels the frame is held at instead of its
        ///     surface's own, or `nil` for the surface's width.
        public init(slug: String, name: String, note: String, frame: PreviewFrame, pinnedWidth: Int? = nil) {
            self.slug = slug
            self.name = name
            self.note = note
            self.frame = frame
            self.pinnedWidth = pinnedWidth
        }

        /// The URL segment naming this state within its component: lowercase and hyphens.
        public let slug: String

        /// The heading a reader sees above the state.
        public let name: String

        /// What a reviewer should look at here, or what went wrong here once.
        public let note: String

        /// The production surface the state is shown on.
        public let frame: PreviewFrame

        /// The width in CSS pixels the frame is held at instead of its surface's own, or
        /// `nil` when the surface's width is the picture.
        ///
        /// For a state that exists to show what a component does when its pane narrows
        /// — a width a dragged grip reaches in production, but the reference window
        /// never shows. The surface still decides the ground; only the width is pinned.
        public let pinnedWidth: Int?
    }

    /// Declares a state.
    ///
    /// - Parameters:
    ///   - slug: The URL segment naming this state within its component.
    ///   - name: The heading a reader sees above the state.
    ///   - note: What a reviewer should look at here — never empty, because a picture
    ///     with no caption teaches nothing.
    ///   - frame: The production surface the state is shown on.
    ///   - pinnedWidth: The width in CSS pixels to hold the frame at instead of the
    ///     surface's own — see ``Metadata/pinnedWidth``. `nil` for the surface's width.
    ///   - content: The component, built from production prop types. Capture nothing.
    public init(
        slug: String,
        name: String,
        note: String,
        frame: PreviewFrame,
        pinnedWidth: Int? = nil,
        content: @escaping @Sendable () -> some HTML & SendableMetatype
    ) {
        metadata = Metadata(slug: slug, name: name, note: note, frame: frame, pinnedWidth: pinnedWidth)
        compact = { content().render() }
        pretty = { content().renderFormatted() }
    }

    /// Everything about the state except the markup.
    public let metadata: Metadata

    /// The markup as the server sends it.
    private let compact: @Sendable () -> String

    /// The markup indented, for a golden file and for a person.
    private let pretty: @Sendable () -> String

    /// The URL segment naming this state within its component.
    public var slug: String {
        metadata.slug
    }

    /// The heading a reader sees above the state.
    public var name: String {
        metadata.name
    }

    /// What a reviewer should look at here.
    public var note: String {
        metadata.note
    }

    /// The production surface the state is shown on.
    public var frame: PreviewFrame {
        metadata.frame
    }

    /// The width the frame is held at instead of its surface's own, if any.
    public var pinnedWidth: Int? {
        metadata.pinnedWidth
    }

    /// Renders the state the way the server sends it.
    ///
    /// - Returns: The compact markup.
    public func render() -> String {
        compact()
    }

    /// Renders the state indented.
    ///
    /// - Returns: The formatted markup — what the golden fixture holds.
    public func renderFormatted() -> String {
        pretty()
    }

    /// The state's markup as a value that can be nested inside a page.
    ///
    /// Already-rendered text rather than the component itself, because the component is
    /// erased. `HTMLRaw` re-emits it verbatim, so a state nested in a document and the
    /// same state rendered alone are byte-identical.
    public var html: HTMLRaw {
        HTMLRaw(compact())
    }
}
