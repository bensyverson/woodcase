//
//  PenDiagnosticSeverity+Argument.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Woodcase

/// `--severity error` on the command line.
extension PenDiagnostic.Severity: ExpressibleByArgument {
    /// The values `--help` offers, from the type itself so a new level cannot be
    /// missing from the help text.
    public static var allValueStrings: [String] {
        allCases.map(\.rawValue)
    }
}
