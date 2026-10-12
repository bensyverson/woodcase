//
//  PenPostIt+Variant.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// Which of the three canvas notes a node is: a post-it, or one of the format's two
    /// special variants.
    ///
    /// All three are drawn as artwork in the rev 2 look (``PenPostIt/expansion(of:width:height:style:measure:labels:identityColor:)``),
    /// take markdown in `content` and grow to fit it. A note that is a comment message
    /// (``NoteType/comment``) is still a ``note`` here; it is Penumbra's to draw.
    enum Variant: String, Friendly, CaseIterable {
        /// A post-it: tinted paper with its author at the bottom.
        case note
        /// An instruction for a model: a white card with its model, ▶ Run and the run's status.
        case prompt
        /// Standing guidance for agents: a quiet card with an ⓘ mark.
        case context

        /// The variant a node kind is.
        ///
        /// - Parameter kind: Any node kind.
        /// - Returns: The variant, or `nil` for a kind that is not a note, prompt or context.
        public init?(_ kind: PenNode.Kind) {
            switch kind {
            case .note: self = .note
            case .prompt: self = .prompt
            case .context: self = .context
            default: return nil
            }
        }
    }
}
