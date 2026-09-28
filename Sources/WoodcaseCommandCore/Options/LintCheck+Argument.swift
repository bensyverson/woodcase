//
//  LintCheck+Argument.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Woodcase

/// `--exclude clipped` on the command line.
///
/// ``LintCheck`` is already `String, CaseIterable`, so ArgumentParser derives
/// ``ExpressibleByArgument/allValueStrings`` for free — an unrecognised id is rejected
/// before `run()` ever sees it, in a message that lists every valid one.
extension LintCheck: ExpressibleByArgument {}
