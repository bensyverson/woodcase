//
//  PenPostIt+DrawingOptions.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// What a caller draws notes with: its words for the chrome's labels and its colors for
    /// identities.
    ///
    /// ``PenRenderer`` takes one so an editor's fallback render shows the same localized
    /// chrome and chosen colors as its GPU path. The defaults are what Woodcase's own
    /// renderer and CLI draw: English labels (``Label/english``) and every identity in its
    /// ``ActorColor``.
    ///
    /// Not ``Friendly``: it holds the caller's functions.
    struct DrawingOptions: Sendable {
        /// The caller's words for the chrome's labels.
        public var labels: @Sendable (Label) -> String

        /// The color a person chose, by identity, or `nil` to draw them in their ``ActorColor``.
        public var identityColor: @Sendable (String) -> PenHexColor?

        /// Creates drawing options.
        ///
        /// - Parameters:
        ///   - labels: Turns a label into the string drawn and measured. Defaults to English.
        ///   - identityColor: The color a person chose, by identity, or `nil` for their
        ///     ``ActorColor``. Defaults to none chosen.
        public init(
            labels: @escaping @Sendable (Label) -> String = { $0.english },
            identityColor: @escaping @Sendable (String) -> PenHexColor? = { _ in nil }
        ) {
            self.labels = labels
            self.identityColor = identityColor
        }
    }
}
