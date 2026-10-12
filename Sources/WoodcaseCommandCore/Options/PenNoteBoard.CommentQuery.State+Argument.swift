//
//  PenNoteBoard.CommentQuery.State+Argument.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Woodcase

/// `--state open` on `woodcase comments`.
///
/// The type is `String, CaseIterable`, so ArgumentParser refuses a misspelling before
/// `run()` sees it, in a message listing every valid state.
extension PenNoteBoard.CommentQuery.State: ExpressibleByArgument {}
