//
//  PenPostIt+RunState.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// Where a prompt's work stands, as its `woodcase.state` spells it.
    ///
    /// Run queues work in the file (Penumbra's notes design rev 2, decision 14): pressing
    /// it sets `queued` and ``PenMetadata/WoodcaseKey/requestedBy``; a watching agent claims
    /// it (`running`), answers in a comment thread anchored to the prompt, and marks it
    /// `done`. A prompt with no state has never been run. A note's state is
    /// ``PenPostIt/State`` instead; each is held to its own spellings when written
    /// (``PenMetadata/WoodcaseKey/shape(on:)``).
    enum RunState: String, Friendly, CaseIterable {
        /// Run was pressed; no one has claimed the work yet.
        case queued
        /// An agent has claimed the work.
        case running
        /// The work is answered.
        case done
    }
}
