//
//  PenPostIt+Label.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// A word the chrome shows: what it says, not how it is spelled.
    ///
    /// The expansion (``PenPostIt/expansion(of:width:height:style:measure:labels:identityColor:body:)``)
    /// takes a function that turns a label into a string, so an editor passes its localized
    /// strings and the chrome is measured in the words drawn; Woodcase's renderer and CLI
    /// pass ``english``. Each chrome text part names the label it shows
    /// (``PenPostItExpansion/Text/label``). The ▶ before a prompt's header and Run is the
    /// look's (``Style/playGlyph``), not the label's.
    enum Label: Friendly {
        /// A prompt's header: "PROMPT".
        case promptTitle
        /// A context's header: "CONTEXT".
        case contextTitle
        /// The Run button: "Run".
        case run
        /// Where a prompt's run stands and who queued it: "Queued · ben".
        case status(RunState, requestedBy: String?)

        /// The label in English, as the rev 2 mockup words it.
        public var english: String {
            switch self {
            case .promptTitle: "PROMPT"
            case .contextTitle: "CONTEXT"
            case .run: "Run"
            case let .status(state, requestedBy):
                Self.englishState(state) + (requestedBy.map { " · \($0)" } ?? "")
            }
        }

        /// A run state's English word.
        private static func englishState(_ state: RunState) -> String {
            switch state {
            case .queued: "Queued"
            case .running: "Running"
            case .done: "Done"
            }
        }
    }
}
