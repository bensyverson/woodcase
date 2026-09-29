//
//  PreviewComponent.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// One component of the viewer, and every state of it worth looking at.
///
/// A component declares its own previews beside itself, in
/// `Components/Previews/<Component>+Previews.swift`, as a `static let previews`. The
/// only thing ``PreviewCatalog`` holds is the list of those declarations, so adding a
/// state is one literal in the component's own file and registers nothing.
///
/// **Representative, not exhaustive.** The states are the ones worth looking at — empty,
/// ordinary, crowded, wrong, mid-flight — and there is deliberately no matrix generator.
///
/// Like ``PreviewState``, this is `Sendable` rather than `Friendly`: its states hold the
/// closures that render them. ``metadata`` is the serializable half.
public struct PreviewComponent: Sendable {
    /// A component's describable half: everything except the markup its states render.
    public struct Metadata: Friendly {
        /// Creates a component's metadata.
        ///
        /// - Parameters:
        ///   - slug: The URL segment naming the component.
        ///   - title: The component's display name.
        ///   - blurb: One sentence saying what the component is for.
        ///   - source: The repository-relative path of the file that defines it.
        ///   - states: The states, in the order they are declared.
        public init(
            slug: String,
            title: String,
            blurb: String,
            source: String,
            states: [PreviewState.Metadata]
        ) {
            self.slug = slug
            self.title = title
            self.blurb = blurb
            self.source = source
            self.states = states
        }

        /// The URL segment naming the component: lowercase and hyphens.
        public let slug: String

        /// The component's display name.
        public let title: String

        /// One sentence saying what the component is for.
        public let blurb: String

        /// The repository-relative path of the file that defines it.
        public let source: String

        /// The states, in the order they are declared.
        public let states: [PreviewState.Metadata]
    }

    /// Declares a component's previews.
    ///
    /// - Parameters:
    ///   - slug: The URL segment naming the component, unique across the catalog.
    ///   - title: The component's display name.
    ///   - blurb: One sentence saying what the component is for.
    ///   - source: The repository-relative path of the file that defines it — where a
    ///     reader goes when something looks wrong.
    ///   - states: The states, in the order they should be read.
    public init(
        slug: String,
        title: String,
        blurb: String,
        source: String,
        states: [PreviewState]
    ) {
        self.slug = slug
        self.title = title
        self.blurb = blurb
        self.source = source
        self.states = states
    }

    /// The URL segment naming the component.
    public let slug: String

    /// The component's display name.
    public let title: String

    /// One sentence saying what the component is for.
    public let blurb: String

    /// The repository-relative path of the file that defines it.
    public let source: String

    /// The states, in the order they should be read.
    public let states: [PreviewState]

    /// Everything about the component except the markup its states render.
    public var metadata: Metadata {
        Metadata(
            slug: slug,
            title: title,
            blurb: blurb,
            source: source,
            states: states.map(\.metadata)
        )
    }

    /// Finds one of this component's states.
    ///
    /// - Parameter slug: The state's slug.
    /// - Returns: The state, or `nil` if this component declares no such state.
    public func state(slug: String) -> PreviewState? {
        states.first { $0.slug == slug }
    }
}
