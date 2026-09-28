//
//  ScriptWrite.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import Woodcase

    /// The write side of `doc`: one batch operation in, one ``Woodcase/WriteReport`` out.
    ///
    /// The prelude turns `doc.set('Card/Title', { 'kind.content': 'Hi' }, { rev })` into
    /// the JSONL object `{"op":"set","target":"Card/Title","props":{…},"rev":…}` and sends
    /// it across, so what arrives here is a batch line and the only thing to do with it is
    /// decode it and hand it to ``Woodcase/BatchApplier/applyOne(_:to:recorder:log:file:)``.
    /// That is deliberate to the point of being the whole design: the grammar a batch file
    /// is written in and the grammar a script is written in are one grammar with two
    /// surfaces, and a translation table in Swift would be a second place for them to
    /// disagree.
    ///
    /// So there is no `@tag` here. A tag exists so a later JSONL line can name what an
    /// earlier one created; a program has the return value, and `doc.set(hero.id, …)`
    /// needs nothing invented.
    ///
    /// Guards are not here either. A ``Woodcase/BatchGuard`` is asserted at *transaction
    /// entry*, and the transaction is the `js` verb's, checked once before the script
    /// starts — so `applyOne` is called with no log and no file, because the only thing
    /// they feed is a guard conflict's "who moved it" clause and no call from here carries
    /// a guard. `rev` is the per-call pin, and it travels on the operation.
    enum ScriptWrite {
        /// Applies one operation and answers with the report the verb prints.
        ///
        /// - Parameters:
        ///   - request: The batch operation, as JSON.
        ///   - runner: The run, for the recorder, the timeline and the settled-tree cache.
        /// - Returns: The ``Woodcase/WriteReport``, as JSON.
        /// - Throws: ``ScriptThrow`` carrying whatever the editing layer refused it with.
        static func apply(_ request: String, _ runner: ScriptRunner) throws -> String {
            let operation = try operation(from: request)
            let document = runner.document
            do {
                let subject = try ScriptWriteReport.subject(of: operation, in: document)
                let result = try BatchApplier.applyOne(
                    operation, to: document, recorder: runner.recorder
                )
                runner.invalidate()
                let report = ScriptWriteReport.report(
                    of: operation, result, subject: subject, in: document
                )
                runner.record(.write(member: ScriptWriteMember(operation.verb), report))
                return try ScriptJSON.encode(report)
            } catch {
                throw runner.editingFailure(error)
            }
        }

        /// Removes a variable, a theme axis or an import alias — the three writes the
        /// batch grammar has no verb for.
        ///
        /// The grammar leaves all three out on purpose: an optional payload on `var` or
        /// `import` would turn a dropped field into a silent delete. So these go where
        /// `woodcase vars rm` and `woodcase imports rm` go, straight to the
        /// ``Woodcase/EditOperation``, through the recorder when there is one.
        ///
        /// - Parameters:
        ///   - request: The removal, as JSON.
        ///   - runner: The run.
        /// - Returns: The ``Woodcase/WriteReport``, as JSON.
        /// - Throws: ``ScriptThrow`` for a name the document does not have, and for a
        ///   variable or an alias something still references.
        static func remove(_ request: String, _ runner: ScriptRunner) throws -> String {
            let call = try ScriptJSON.decode(RemoveRequest.self, from: request)
            let document = runner.document
            do {
                switch call.kind {
                case .variable:
                    try refuse(
                        NameInUse.variable(call.name, in: document),
                        unless: call.force ?? false,
                        present: document.variables?[call.name] != nil,
                        code: ScriptErrorCode.variableInUse
                    )
                    try runner.applyDirect(
                        .removeVariable(EditOperation.RemoveVariable(name: call.name))
                    )
                case .themeAxis:
                    try runner.applyDirect(
                        .removeThemeAxis(EditOperation.RemoveThemeAxis(name: call.name))
                    )
                case .importAlias:
                    try refuse(
                        NameInUse.importAlias(call.name, in: document),
                        unless: call.force ?? false,
                        present: document.imports?[call.name] != nil,
                        code: ScriptErrorCode.importInUse
                    )
                    try runner.applyDirect(
                        .removeImport(EditOperation.RemoveImport(alias: call.name))
                    )
                }
                let report = WriteReport(
                    path: call.name, documentRevision: document.documentRevision
                )
                runner.record(.write(member: call.kind.member, report))
                return try ScriptJSON.encode(report)
            } catch {
                throw runner.editingFailure(error)
            }
        }

        // MARK: - Private

        /// The operation the request carries.
        ///
        /// The prelude has already checked every shape it can see, so a failure here is
        /// one of the two things it cannot: a subtree the .pen format will not read, or
        /// an address that is a string but not an address. Both are the caller's mistake
        /// and both get named, rather than surfacing as the host's own bug.
        ///
        /// - Parameter request: The operation, as JSON.
        /// - Returns: The decoded operation.
        /// - Throws: ``ScriptThrow`` with ``ScriptErrorCode/badArgument``.
        private static func operation(from request: String) throws -> BatchOperation {
            do {
                return try JSONDecoder().decode(BatchOperation.self, from: Data(request.utf8))
            } catch {
                let named = (try? ScriptJSON.decode(VerbOnly.self, from: request))
                    .map { ScriptWriteMember($0.op).qualifiedName } ?? "this write"
                throw ScriptThrow(
                    message: """
                    \(named) could not read what it was given (\(reason(of: error))). A subtree \
                    is one JSON object with a `type` and a `name`, and optional `children`; an \
                    address is an id, a path of names (`Dashboard/Header/Title`), or an id \
                    forced with `#`.
                    """,
                    code: ScriptErrorCode.badArgument
                )
            }
        }

        /// The clause a decoding failure contributes to a sentence.
        private static func reason(of error: any Error) -> String {
            guard let decoding = error as? DecodingError else { return "\(error)" }
            switch decoding {
            case let .keyNotFound(key, _): return "no \(key.stringValue)"
            case let .typeMismatch(_, context), let .valueNotFound(_, context),
                 let .dataCorrupted(context):
                return context.debugDescription
            @unknown default: return "\(error)"
            }
        }

        /// Refuses to remove a name something still resolves through.
        ///
        /// The same decision `woodcase vars rm` and `woodcase imports rm` make, over the
        /// same library fact — ``Woodcase/NameInUse`` — because it is a decision rather
        /// than a rule of the format: ``Woodcase/EditableDocument`` removes either name
        /// happily, and a node whose fill is `$brand` does not fail afterwards, it renders
        /// the unresolved reference. That silent breakage is what is worth refusing. Only
        /// the remedy belongs to the caller, and ``Woodcase/RemedyDialect/script`` is how
        /// this one says it: a script has no `--force`.
        ///
        /// A name the document does not hold is *not* refused here — the edit itself
        /// raises `variableNotFound` or `importNotFound`, which is the sentence a caller
        /// wants for a typo.
        ///
        /// - Parameters:
        ///   - inUse: What the document still refers the name by.
        ///   - force: Whether the caller opted into the consequence.
        ///   - present: Whether the document holds the name at all.
        ///   - code: The ``ScriptErrorCode`` a refusal carries.
        /// - Throws: ``ScriptThrow`` with `code`.
        private static func refuse(
            _ inUse: NameInUse,
            unless force: Bool,
            present: Bool,
            code: String
        ) throws {
            guard !force, present, !inUse.isEmpty else { return }
            throw ScriptThrow(message: inUse.sentence(in: .script), code: code)
        }

        // MARK: - Requests

        /// Just the verb, for naming the member when the rest of a line would not decode.
        private struct VerbOnly: Decodable {
            /// The `"op"` field.
            let op: BatchOperation.Verb
        }

        /// What `doc.vars.rm`, `doc.themes.rm` and `doc.imports.rm` send across.
        private struct RemoveRequest: Decodable {
            /// Which table the name lives in.
            let kind: Table

            /// The variable's, axis's or alias's name.
            let name: String

            /// Whether the removal was forced past the references it would strand.
            let force: Bool?

            /// The three tables a name can be removed from.
            enum Table: String, Decodable {
                /// `doc.vars.rm`.
                case variable

                /// `doc.themes.rm`.
                case themeAxis

                /// `doc.imports.rm`.
                case importAlias

                /// The member of `doc` that removes from this table, for the row the
                /// transcript prints.
                var member: ScriptWriteMember {
                    switch self {
                    case .variable: .varsRemove
                    case .themeAxis: .themesRemove
                    case .importAlias: .importsRemove
                    }
                }
            }
        }
    }

#endif
