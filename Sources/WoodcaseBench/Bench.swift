//
//  Bench.swift
//  WoodcaseBench
//

import Foundation

/// One named measurement `WoodcaseBench` can run.
///
/// A bench prints `PROBE` lines and checks nothing: the suite holds the line by
/// counting work, and a bench says what that work costs on an optimized build, which
/// means something only beside `uptime`.
struct Bench {
    /// What to type after `WoodcaseBench`, in kebab case.
    let name: String

    /// What the bench measures, in a line, for `WoodcaseBench list`.
    let summary: String

    /// The arguments it takes after its name, for the usage line; empty for none.
    var arguments: String = ""

    /// Runs the bench with the arguments after its name.
    let run: @MainActor ([String]) throws -> Void
}

extension Bench {
    /// Why a bench could not start.
    struct UsageError: Error, CustomStringConvertible {
        /// What went wrong and what to type instead.
        let description: String
    }
}
