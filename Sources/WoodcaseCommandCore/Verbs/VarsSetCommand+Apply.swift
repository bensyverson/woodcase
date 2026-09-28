//
//  VarsSetCommand+Apply.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// What `vars set` does inside the transaction: register the pin, write every pair,
/// read the result back.
///
/// Split from the command itself because the two halves answer different questions —
/// the command is the grammar and the answer's shape, this is the edit — and because
/// the file was at the size where a reader stops holding it in their head.
extension VarsSet {
    /// Registers whatever the pin names, then writes every pair.
    ///
    /// The pre-state is read once, before anything is written: the reference counts a
    /// caller is warned with are the counts the *old* value had, and the axes have to be
    /// registered before the values that pin them land.
    ///
    /// - Parameters:
    ///   - assignments: The `name=value` pairs as typed, in order.
    ///   - declaredType: `--type`, when it was given. It applies to every pair.
    ///   - pin: The `--theme` axes and options, empty for unpinned values. It applies to
    ///     every pair, and is registered once for the call rather than once per pair.
    ///   - document: The document being edited.
    ///   - recorder: The recorder every write goes through, so the activity log gets a
    ///     `theme` event for each axis touched and a `var` event for each variable, all
    ///     sharing the transaction's batch id.
    ///   - effect: Whether this is a rehearsal, which is what decides whether the
    ///     findings are collected and the revision dropped.
    /// - Returns: What the write made.
    /// - Throws: ``CommandFailure`` when a value is not of its variable's type, and
    ///   whatever the operations themselves throw. A pair that throws takes the whole
    ///   call with it: the transaction is the unit of the write.
    static func apply(
        _ assignments: [VariableAssignment],
        declaredType: PenVariableType?,
        pinnedTo pin: [String: String],
        to document: EditableDocument,
        through recorder: ActivityRecorder,
        effect: WriteEffect
    ) throws -> Report {
        let findings = try effect.preview(of: document)
        let names = distinctNames(of: assignments)
        let previous = VariableFormatter.rows(for: names, in: document)

        let axes = try register(pin, in: document, through: recorder)
        for assignment in assignments {
            try write(assignment, declaredType: declaredType, pinnedTo: pin, to: document, through: recorder)
        }

        let written = VariableFormatter.rows(for: names, in: document)
        guard written.count == names.count else {
            let missing = Set(names).subtracting(written.map(\.name)).sorted()
            throw CommandFailure(
                message: "\(missing.joined(separator: ", ")) was written but could not be read back.",
                exitCode: .environment
            )
        }
        return try Report(
            variables: written,
            previous: previous,
            axes: axes,
            revision: document.documentRevision,
            dryRun: effect == .dryRun,
            lint: findings?.introduced(in: document) ?? []
        )
    }

    // MARK: - Private

    /// The names the call touches, each once, in the order they were first written.
    private static func distinctNames(of assignments: [VariableAssignment]) -> [String] {
        var seen: Set<String> = []
        return assignments.map(\.name).filter { seen.insert($0).inserted }
    }

    /// Writes one pair, adding the variable or updating it.
    ///
    /// - Parameters:
    ///   - assignment: The `name=value` as typed.
    ///   - declaredType: `--type`, when it was given.
    ///   - pin: The `--theme` axes and options, empty for an unpinned value.
    ///   - document: The document being edited.
    ///   - recorder: The recorder the operation goes through.
    /// - Throws: ``CommandFailure`` when the value is not of the variable's type.
    private static func write(
        _ assignment: VariableAssignment,
        declaredType: PenVariableType?,
        pinnedTo pin: [String: String],
        to document: EditableDocument,
        through recorder: ActivityRecorder
    ) throws {
        let existing = document.variables?[assignment.name]
        let type = try resolvedType(assignment, declared: declaredType, existing: existing, in: document)
        guard let value = VariableTyping.value(of: assignment.literal, as: type) else {
            throw CommandFailure(
                message: """
                Cannot set \(assignment.name) to \(assignment.literal): \(assignment.name) is a \
                \(type.rawValue) variable and that is not a \(type.rawValue) value \
                (\(VariableTyping.example(of: type)) is). Give a \(type.rawValue), or pass \
                --type to declare a different type.
                """,
                exitCode: .usage
            )
        }
        let variable = PenVariable(
            type: type,
            value: VariableValueEditor.merged(existing: existing?.value, setting: value, pinnedTo: pin)
        )
        if existing == nil {
            try recorder.apply(.addVariable(EditOperation.AddVariable(name: assignment.name, variable: variable)))
        } else {
            try recorder.apply(.updateVariable(EditOperation.UpdateVariable(name: assignment.name, variable: variable)))
        }
    }

    /// The type this write stores the variable under.
    ///
    /// - Parameters:
    ///   - assignment: The `name=value` as typed.
    ///   - declared: `--type`, when it was given.
    ///   - existing: The variable as it stands, when it already exists.
    ///   - document: The document, for a `$reference`'s target.
    /// - Returns: The type to store.
    /// - Throws: ``CommandFailure`` when the value references a variable the document
    ///   does not define, which is the one case nothing can be inferred from.
    private static func resolvedType(
        _ assignment: VariableAssignment,
        declared: PenVariableType?,
        existing: PenVariable?,
        in document: EditableDocument
    ) throws -> PenVariableType {
        if let declared { return declared }
        if let existing { return existing.type }
        if let inferred = VariableTyping.inferredType(of: assignment.literal) { return inferred }
        let referenced = String(assignment.literal.dropFirst())
        if let target = document.variables?[referenced] { return target.type }
        throw CommandFailure(
            message: """
            Cannot type \(assignment.name): its value \(assignment.literal) names a variable this \
            document does not define. Pass --type boolean|color|number|string, or define \
            \(referenced) first.
            """,
            exitCode: .usage
        )
    }

    /// Creates or widens whatever axes a pin names.
    ///
    /// The rule — create an axis the document lacks, append an option it lacks — lives
    /// in ``Woodcase/ThemeAxisRegistrar``, because the batch `var` line has to grow a
    /// theme the same way this verb does.
    ///
    /// - Parameters:
    ///   - pin: The axes and options the values are pinned to.
    ///   - document: The document being edited.
    ///   - recorder: The recorder the theme operations go through.
    /// - Returns: The axes this call created or added an option to, in axis order.
    /// - Throws: Whatever the theme operations throw.
    private static func register(
        _ pin: [String: String],
        in document: EditableDocument,
        through recorder: ActivityRecorder
    ) throws -> [VariableFormatter.Axis] {
        let registrations = ThemeAxisRegistrar.registrations(
            for: pin.mapValues { [$0] }, in: document
        )
        for registration in registrations {
            try recorder.apply(registration.edit)
        }
        return registrations.map { VariableFormatter.Axis(name: $0.name, options: $0.options) }
    }
}
