//
//  ParsableCommand+Failures.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation

extension ParsableCommand {
    /// Runs a verb's work, turning any failure into a message on standard error and a
    /// house exit code.
    ///
    /// - Parameters:
    ///   - file: The .pen file this verb is editing, if any.
    ///   - isolation: The caller's actor, inherited so the body runs where the verb
    ///     does. Never passed explicitly.
    ///   - body: The verb's work.
    /// - Returns: Whatever `body` returned.
    /// - Throws: An ``ArgumentParser/ExitCode``.
    @discardableResult
    func runReportingFailures<Value>(
        editing file: URL? = nil,
        isolation _: isolated (any Actor)? = #isolation,
        _ body: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await body()
        } catch let code as ExitCode {
            throw code
        } catch let exit as CleanExit {
            throw exit
        } catch {
            let failure = CommandFailure.describing(error, editing: file)
            StandardError.write(failure.message)
            throw failure.exitCode
        }
    }
}
