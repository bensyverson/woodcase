//
//  PenPostIt+DrawingOptions.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// What a caller draws notes with: its words for the chrome's labels, its colors for
    /// identities, and the cards whose body it draws raw.
    ///
    /// ``PenRenderer`` takes one so an editor's fallback render shows the same localized
    /// chrome, chosen colors and raw bodies as its GPU path, and
    /// ``expansion(of:width:height:style:measure:options:)`` takes the same value, so a
    /// renderer passes it through whole. The defaults are what Woodcase's own renderer and
    /// CLI draw: English labels (``Label/english``), every identity in its
    /// ``ActorColor``, and every body styled.
    ///
    /// Not ``Friendly``: it holds the caller's functions.
    struct DrawingOptions: Sendable {
        /// The caller's words for the chrome's labels.
        public var labels: @Sendable (Label) -> String

        /// The color a person chose, by identity, or `nil` to draw them in their ``ActorColor``.
        public var identityColor: @Sendable (String) -> PenHexColor?

        /// The ids of the notes, prompts and contexts whose body is drawn raw
        /// (``BodyText/raw``): the cards an editor is editing. Every other body is styled.
        public var rawBodies: Set<String>

        /// Creates drawing options.
        ///
        /// - Parameters:
        ///   - labels: Turns a label into the string drawn and measured. Defaults to English.
        ///   - identityColor: The color a person chose, by identity, or `nil` for their
        ///     ``ActorColor``. Defaults to none chosen.
        ///   - rawBodies: The ids of the cards whose body is drawn as written. Defaults to
        ///     none.
        public init(
            labels: @escaping @Sendable (Label) -> String = { $0.english },
            identityColor: @escaping @Sendable (String) -> PenHexColor? = { _ in nil },
            rawBodies: Set<String> = []
        ) {
            self.labels = labels
            self.identityColor = identityColor
            self.rawBodies = rawBodies
        }

        /// How a node's body is drawn under these options.
        ///
        /// - Parameter id: The node's id.
        /// - Returns: ``BodyText/raw`` for an id in ``rawBodies``, otherwise
        ///   ``BodyText/styled``.
        public func bodyText(for id: String) -> BodyText {
            rawBodies.contains(id) ? .raw : .styled
        }

        /// The layout options that grow the cards these options draw raw, so layout and
        /// drawing agree on which cards are raw.
        public var layoutOptions: PenLayoutOptions {
            PenLayoutOptions(rawBodies: rawBodies)
        }
    }
}
