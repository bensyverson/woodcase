//
//  ScriptRunFormatter.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase
import WoodcaseScripting

/// Renders what `woodcase js` did: the live transcript, and the `--json` object.
///
/// ```text
/// cp           Canvas/Cards/Cards  Kp2xA  (+2)
/// set          Canvas/Title  Ttl01
///              kind.content stored the number 42 as the text "42" — the property takes text, not a number
/// result  0
/// document  4f2a1b0c9d8e7f60
/// ```
///
/// Both forms are pure functions of one ``ScriptRunReport``, so they cannot say
/// different things. The text form is *streamed* rather than composed, because a write
/// row has to appear when the write happens and a `console.log` between the rows it was
/// printed between — so the verb calls ``transcript(of:)`` per event as the host hands
/// it over, and ``tail(of:)`` once at the end. Each of those is the same function the
/// `--json` object's own fields are built from.
///
/// ## Which stream
///
/// stdout carries the answer: the write rows, the `console.log` lines, `result` and
/// `document`. stderr carries what stderr always carries — `console.warn` and
/// `console.error`, the run's own warnings, and the refusal. That is the same split
/// every other verb makes, and it is what lets `woodcase js … | jq` work under `--json`
/// while a human still sees the warnings.
enum ScriptRunFormatter {
    /// How wide the member column is, separator included.
    ///
    /// Every write row leads with the member of `doc` that made it, padded so the paths
    /// line up whatever wrote them — `apply`'s fixed status column, one surface over.
    /// The width is ``WoodcaseScripting/ScriptWriteMember/columnWidth``, a fact about the
    /// vocabulary rather than a number chosen here, plus the house two-space separator.
    private static let memberColumn = ScriptWriteMember.columnWidth + 2

    /// How far a divergence is indented under the row it belongs to.
    ///
    /// Past the member gutter, so a sentence sits under the path it is about rather than
    /// under the column that says which verb wrote it — exactly what `apply` does with
    /// its own `line N` gutter.
    private static let divergenceIndent = String(repeating: " ", count: memberColumn)

    /// How far the quoted source line of a refusal is indented under its location.
    ///
    /// Two spaces — the house column separator. There is no member gutter on stderr:
    /// a refusal names a place in a script, not a write.
    private static let quotedSourceIndent = "  "

    /// What one event puts on each stream.
    struct Transcript {
        /// Lines for standard output, in order.
        let stdout: [String]

        /// Lines for standard error, in order.
        let stderr: [String]
    }

    /// One event's lines, split by stream.
    ///
    /// - Parameter event: The event to render.
    /// - Returns: What it writes to each stream.
    static func transcript(of event: ScriptRunReport.Event) -> Transcript {
        switch event.event {
        case .write:
            guard let report = event.write, let member = event.member else {
                return Transcript(stdout: [], stderr: [])
            }
            return Transcript(stdout: rows(for: report, by: member), stderr: [])
        case .log:
            let line = event.text ?? ""
            return event.level == .log
                ? Transcript(stdout: [line], stderr: [])
                : Transcript(stdout: [], stderr: [line])
        case .warning:
            return Transcript(stdout: [], stderr: ["warning  \(event.text ?? "")"])
        case .overlap:
            // Already a lint line — `warning artboard-overlap  …` — so it carries its own
            // severity where the others take the gutter, and prints byte for byte what
            // `apply` prints for the same pair.
            return Transcript(stdout: [], stderr: [event.text ?? ""])
        }
    }

    /// The rows that close a text transcript: the completion value, then the revision.
    ///
    /// A run that ended in an error, and a rehearsal, name no revision — neither made
    /// one, and printing the one the document reached would name nothing on disk. A
    /// completion value of `null` prints no `result` row either: a row saying `null` is
    /// noise a caller has to filter, and its absence is the same fact.
    ///
    /// - Parameter report: The finished run.
    /// - Returns: Zero, one or two lines for standard output.
    static func tail(of report: ScriptRunReport) -> [String] {
        var lines: [String] = []
        if let result = report.result, result != .null, let text = try? compact(result) {
            lines.append("result  \(text)")
        }
        if let revision = report.documentRevision {
            lines.append("document  \(revision)")
        }
        return lines
    }

    /// The refusal a failed run ends with, for standard error.
    ///
    /// Location first, so a reader's eye lands on the line to open; the quoted source
    /// line under it; then the promise the transaction keeps, spelled out — a caller
    /// that has just seen write rows scroll past needs to be told, in words, that none
    /// of them landed.
    ///
    /// - Parameters:
    ///   - error: Why the run ended.
    ///   - file: The .pen file the run was against.
    /// - Returns: The lines to write to standard error.
    static func failure(_ error: ScriptError, file: String) -> [String] {
        var lines: [String] = []
        let place = location(of: error)
        lines.append(place.isEmpty ? error.message : "\(place)  \(error.message)")
        if let quoted = error.sourceLine, !quoted.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("\(quotedSourceIndent)\(quoted)")
        }
        lines.append("nothing was written; \(file) is byte for byte what it was.")
        return lines
    }

    /// The whole run as one JSON object.
    ///
    /// - Parameter report: The finished run.
    /// - Returns: The JSON text, sorted keys and pretty printed as every other report is.
    /// - Throws: Whatever `JSONEncoder` throws.
    static func json(_ report: ScriptRunReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(report), as: UTF8.self)
    }

    // MARK: - Private

    /// One write's rows: the row itself, then one per divergence, indented under it.
    private static func rows(for report: WriteReport, by member: ScriptWriteMember) -> [String] {
        [row(for: report, by: member)] + (report.divergences ?? []).map { divergence in
            divergenceIndent + divergence.reportLine
        }
    }

    /// One write's row: which member made it, where it landed, its id, and how much came
    /// into being with it.
    ///
    /// The member leads, padded to ``memberColumn``, because a
    /// ``Woodcase/WriteReport`` names what was touched and never what touched it: a `cp`
    /// and the three `override`s that fill the copy all report the *instance*, so without
    /// the first column four writes print four rows nobody can tell apart.
    ///
    /// `(+N)` counts the *descendants* a creating verb made, so a one-node `add` carries
    /// no marker and a `cp` of a frame with two children carries `(+2)`. A write whose
    /// subject is not a node — a variable, a theme axis — has a name and no id, and the
    /// row is that name: a row with nothing but a revision would read the same for every
    /// one of them.
    private static func row(for report: WriteReport, by member: ScriptWriteMember) -> String {
        let subject = if let path = report.path, let id = report.id {
            "\(path)  \(id)"
        } else {
            report.path ?? report.id ?? "document"
        }
        let created = (report.created ?? []).flatMap(\.allIDs).count
        let content = created > 1 ? "\(subject)  (+\(created - 1))" : subject
        let name = member.rawValue
        return name + String(repeating: " ", count: memberColumn - name.count) + content
    }

    /// Where an error happened, as `source:line:column`, dropping what is not known.
    ///
    /// An error with no line is one the host raised rather than one the engine caught —
    /// an unreadable source, a member `doc` does not have — and those name their own
    /// subject in the sentence. Repeating a path in front of a message that already ends
    /// in it reads as two different files, so the prefix is dropped when the message
    /// already says the name.
    private static func location(of error: ScriptError) -> String {
        guard let source = error.source else { return "" }
        guard let line = error.line else {
            return error.message.contains(source) ? "" : source
        }
        guard let column = error.column else { return "\(source):\(line)" }
        return "\(source):\(line):\(column)"
    }

    /// A completion value as one line of JSON.
    ///
    /// Encoded inside an array and unwrapped, because a script's answer is often a
    /// scalar — `result  0` — and a bare scalar is a JSON fragment rather than a
    /// document.
    private static func compact(_ value: AnyCodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text = try String(decoding: encoder.encode([value]), as: UTF8.self)
        return String(text.dropFirst().dropLast())
    }
}
