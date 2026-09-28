//
//  CommandRun.swift
//  WoodcaseCommandTests
//

import Foundation
import Woodcase

/// What one run of the `woodcase` binary produced: the three things an agent sees.
struct CommandRun: Friendly {
    /// Creates a record of a finished run.
    ///
    /// - Parameters:
    ///   - status: The process's exit status.
    ///   - stdout: Everything written to standard output.
    ///   - stderr: Everything written to standard error.
    init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    /// The exit status, to compare against the house table.
    let status: Int32

    /// Everything the run wrote to standard output — the API.
    let stdout: String

    /// Everything the run wrote to standard error — messages, never data.
    let stderr: String

    /// Standard output as lines, without the empty one the final newline leaves.
    var stdoutLines: [String] {
        var lines = stdout.components(separatedBy: "\n")
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }
}
