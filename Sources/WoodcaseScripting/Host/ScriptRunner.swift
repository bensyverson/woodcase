//
//  ScriptRunner.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import JavaScriptCore
    import Woodcase

    /// One run of ``ScriptHost``: the context, the timeline and the document, alive for
    /// exactly as long as the call that made them.
    ///
    /// A class rather than a struct because the native blocks installed into the context
    /// need somewhere to record events, and because they must all see the same settled-tree
    /// cache. Not `Sendable`, and it never needs to be: everything happens inside one
    /// synchronous function, so nothing here ever crosses an isolation boundary.
    final class ScriptRunner {
        /// Prepares a run.
        ///
        /// - Parameters:
        ///   - document: The document the script reads.
        ///   - remedy: Which grammar a refusal's remedy is written in.
        ///   - diagnostics: Diagnostics the caller collected when the file was parsed.
        ///   - recorder: The transaction's recorder, or `nil` for a run that logs
        ///     nothing.
        ///   - deadline: When bridged calls start refusing, or `nil` for no bound.
        ///   - sink: Called with each event as it is recorded.
        ///   - settled: The settled-tree cache the run reads through.
        init(
            document: EditableDocument,
            remedy: RemedyDialect,
            diagnostics: [PenDiagnostic],
            recorder: ActivityRecorder?,
            deadline: ContinuousClock.Instant?,
            sink: ((ScriptRun.Event) -> Void)?,
            settled: SettledTreeCache = SettledTreeCache()
        ) {
            self.settled = settled
            self.document = document
            self.remedy = remedy
            self.diagnostics = diagnostics
            self.recorder = recorder
            self.deadline = deadline
            self.sink = sink
        }

        /// The document under the script.
        let document: EditableDocument

        /// Which grammar a refusal's remedy is written in.
        let remedy: RemedyDialect

        /// Diagnostics from the parse, which `doc.lint` reports alongside its own checks.
        let diagnostics: [PenDiagnostic]

        /// The transaction's recorder, or `nil` when nothing is being logged.
        ///
        /// Optional because ``Woodcase/BatchApplier/applyOne(_:to:recorder:log:file:)``
        /// is: a library caller running a script over an in-memory document has no
        /// activity log to write into, and gets exactly the same reports back.
        let recorder: ActivityRecorder?

        /// When bridged calls start refusing.
        let deadline: ContinuousClock.Instant?

        /// The settled trees this run has paid for, and the hook that marks them stale.
        let settled: SettledTreeCache

        /// The roots that already overlapped when the run started.
        ///
        /// Taken once, before the first line, so the run warns about the overlaps *it*
        /// created and leaves the rest to `lint` — and so a write that breaks the layout
        /// and a later one that repairs it net out to nothing.
        ///
        /// Measured with ``Woodcase/RootOverlap/baseline(in:textSizes:)``, which measures
        /// the roots alone rather than settling the document, so a script that only
        /// writes never pays for a settle it does not read — and measures their texts
        /// through the run's text sizes, so the check at the end and every settle between
        /// typeset only what changed. `nil` until the run starts.
        private var overlapping: RootOverlap.Baseline?

        /// The live transcript, if the caller wanted one.
        private let sink: ((ScriptRun.Event) -> Void)?

        /// The timeline, in the order it happened.
        private(set) var events: [ScriptRun.Event] = []

        /// The prelude's helper object, once the context is built.
        private var internals: JSValue?

        /// Every source evaluated so far, so a failure can quote the right line even when
        /// the throw came from a helper file an later source called.
        private var evaluated = ScriptFailure.Evaluated()

        // MARK: - Recording

        /// Records an event and hands it to the sink, in that order, synchronously.
        ///
        /// The sink sees exactly what ``ScriptRun/events`` ends up holding, in the same
        /// order, so a live transcript and a report built afterwards cannot disagree.
        ///
        /// - Parameter event: What happened.
        func record(_ event: ScriptRun.Event) {
            events.append(event)
            sink?(event)
        }

        /// Marks the settled trees stale, so the next read lays out again the roots the
        /// write could have moved.
        ///
        /// The hook every write calls, without exception: a read that came back with a
        /// stale rect after a write would be the one failure a script cannot see.
        func invalidate() {
            settled.invalidate()
        }

        /// Applies an operation the batch grammar has no verb for, logging it when there
        /// is a log.
        ///
        /// There are exactly two: removing a variable and removing a theme axis. The
        /// batch grammar leaves both out on purpose — an optional payload would turn a
        /// dropped field into a silent delete — so `doc.vars.rm` and `doc.themes.rm` go
        /// where `woodcase vars rm` goes, straight to the ``Woodcase/EditOperation``,
        /// and the recorder makes it one logged event exactly as the verb does.
        ///
        /// - Parameter operation: The operation to apply.
        /// - Throws: Whatever the document refuses it with.
        func applyDirect(_ operation: EditOperation) throws {
            if let recorder {
                try recorder.apply(operation)
            } else {
                try document.apply(operation)
            }
            invalidate()
        }

        // MARK: - Failing

        /// Refuses because the run is out of time.
        ///
        /// Checked before every bridged call rather than by an interrupt, because there is
        /// no interrupt to ask for: the public JavaScriptCore headers carry no
        /// execution-time limit (checked 2026-09-07). A script may catch this and tidy up;
        /// every later call refuses the same way, so it cannot catch its way past the
        /// budget.
        ///
        /// - Throws: ``ScriptThrow`` with ``ScriptErrorCode/timeout`` when the deadline has
        ///   passed.
        func checkDeadline() throws {
            guard let deadline, ContinuousClock.now >= deadline else { return }
            throw ScriptThrow(
                message: """
                this script has run past its time budget, so doc refuses the rest of it — \
                nothing has been written. Do less work in one run, or raise the budget \
                with `--timeout`.
                """,
                code: ScriptErrorCode.timeout
            )
        }

        /// An editing failure, in the words the matching verb would have printed.
        ///
        /// - Parameter error: What the editing layer threw.
        /// - Returns: The refusal to throw into the script.
        func editingFailure(_ error: any Error) -> ScriptThrow {
            if let already = error as? ScriptThrow { return already }
            return ScriptThrow.editing(error, in: document, remedy: remedy)
        }

        /// A Swift error as the `WoodcaseError` the script catches.
        ///
        /// Built through the prelude's own constructor rather than
        /// `JSValue(newErrorFromMessage:in:)` so that `catch (e) { e instanceof
        /// WoodcaseError }` holds for a refusal raised on the Swift side, exactly as it
        /// does for one the prelude raised.
        ///
        /// - Parameters:
        ///   - error: The failure.
        ///   - context: The context to build the value in.
        /// - Returns: The error value to assign to `context.exception`.
        func raise(_ error: any Error, in context: JSContext) -> JSValue? {
            let thrown = error as? ScriptThrow ?? ScriptThrow.editing(error, in: document, remedy: remedy)
            let payload = Payload(
                message: thrown.message,
                code: thrown.code,
                candidates: thrown.candidates
            )
            guard let json = try? ScriptJSON.encode(payload),
                  let made = internals?.invokeMethod("makeError", withArguments: [json]),
                  !made.isUndefined
            else {
                return JSValue(newErrorFromMessage: thrown.message, in: context)
            }
            return made
        }

        /// What the prelude's `makeError` helper takes.
        private struct Payload: Encodable {
            let message: String
            let code: String
            let candidates: [NodeAddressCandidate]
        }

        // MARK: - The run

        /// Evaluates every source in one context and reports what happened.
        ///
        /// - Parameter sources: The sources, in order.
        /// - Returns: The whole run.
        func run(_ sources: [ScriptSource]) -> ScriptRun {
            overlapping = RootOverlap.baseline(in: document, textSizes: settled.textSizes)
            guard let context = JSContext() else {
                return finish(error: ScriptError(
                    message: "a JavaScript context could not be created; this is a bug in woodcase.",
                    code: ScriptErrorCode.scriptError
                ))
            }
            guard let internals = ScriptContext.install(runner: self, into: context) else {
                return finish(error: ScriptError(
                    message: "the script host's prelude did not evaluate; this is a bug in woodcase.",
                    code: ScriptErrorCode.scriptError
                ))
            }
            self.internals = internals

            var completion: JSValue?
            for source in sources {
                let body: String
                switch source {
                case let .file(url):
                    guard let read = try? String(contentsOf: url, encoding: .utf8) else {
                        return finish(error: ScriptError(
                            message: "\(url.path) could not be read as UTF-8 text — check the "
                                + "path and the file's encoding, then run it again.",
                            code: ScriptErrorCode.sourceUnreadable,
                            source: url.path
                        ))
                    }
                    body = read
                case let .text(text, _):
                    body = text
                }
                let url = URL(fileURLWithPath: source.name)
                evaluated.add(body, name: source.name, url: url)

                context.exception = nil
                completion = context.evaluateScript(body, withSourceURL: url)
                if let thrown = context.exception {
                    context.exception = nil
                    return finish(error: ScriptFailure.describe(thrown, in: source, sources: evaluated))
                }
            }

            let result = completion.flatMap {
                ScriptCompletion.value(of: $0, internals: internals) { self.record(.warning($0)) }
            }
            return finish(result: result)
        }

        // MARK: - Private

        /// The run as it stands, having reached the end of the last source.
        ///
        /// ``ScriptRun/Commit/wrote`` when the timeline holds at least one write and
        /// ``ScriptRun/Commit/unchanged`` otherwise. The host answers for *the script*:
        /// it knows what the script asked the document to do and nothing about the file,
        /// which is the transaction's to know. A caller running the host inside a
        /// ``Woodcase/PenFileTransaction`` — the `js` verb — has the real outcome in
        /// ``Woodcase/PenFileTransaction/Outcome/commit`` and maps it over this one: a
        /// dry run reports ``ScriptRun/Commit/previewed``, and writes that cancelled out
        /// so the bytes did not change report ``ScriptRun/Commit/unchanged``, which the
        /// host cannot see because it never encodes the file.
        private func finish(result: AnyCodable?) -> ScriptRun {
            let wrote = events.contains { if case .write = $0 { true } else { false } }
            if wrote { recordOverlaps() }
            return ScriptRun(
                events: events,
                result: result,
                documentRevision: document.documentRevision,
                commit: wrote ? .wrote : .unchanged,
                error: nil
            )
        }

        /// Records one event per pair of roots this run left overlapping.
        ///
        /// At the end of the run and only for a run that reached it: an uncaught error
        /// rolls the whole transaction back, so an overlap it made never reaches the
        /// file, and warning about one would send a reader to look for something that is
        /// not there. Called only when the run wrote: a run that wrote nothing moved
        /// nothing, so it settles nothing to find out.
        private func recordOverlaps() {
            guard let overlapping else { return }
            for overlap in RootOverlap.introduced(since: overlapping, in: document) {
                record(.overlap(overlap.finding(in: document, file: remedy.file)))
            }
        }

        /// The run as it stands, ended by a failure.
        ///
        /// ``ScriptRun/Commit/rolledBack`` rather than `unchanged`, whether or not writes
        /// landed on the document first: the whole run is one transaction, so an uncaught
        /// error means the file is byte for byte what it was and the log gained nothing.
        /// The writes are still on ``events`` — they are what the script did, and a
        /// reader debugging the failure wants to see how far it got — but they were not
        /// committed, and `commit` is the field that says so.
        private func finish(error: ScriptError) -> ScriptRun {
            ScriptRun(
                events: events,
                result: nil,
                documentRevision: document.documentRevision,
                commit: .rolledBack,
                error: error
            )
        }
    }

#endif
