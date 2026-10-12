//
//  PenNoteBoard.PromptQuery.State+Argument.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Woodcase

/// `--state queued` on `woodcase prompts`.
///
/// The type is `String, CaseIterable`, so ArgumentParser refuses a misspelling before
/// `run()` sees it, in a message listing every valid run state.
extension PenNoteBoard.PromptQuery.State: ExpressibleByArgument {}
