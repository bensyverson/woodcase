//
//  ScriptHost.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import JavaScriptCore
    import Woodcase

    /// Runs JavaScript against an open document.
    ///
    /// One synchronous call: a `JSContext` is created, the prelude is evaluated, `doc` and
    /// `console` are installed, each ``ScriptSource`` is evaluated in turn *in the same
    /// context*, and the whole run comes back as a ``ScriptRun``.
    ///
    /// ```swift
    /// let run = ScriptHost.run(
    ///     [.file(helpers), .file(script)],
    ///     over: document,
    ///     timeout: .seconds(30)
    /// ) { event in print(event) }
    /// ```
    ///
    /// ## Isolation
    ///
    /// No global actor appears anywhere in this target, and none is needed. `JSContext` is
    /// not `Sendable` and neither is ``Woodcase/EditableDocument``; the whole run lives
    /// inside one synchronous function, so nothing it holds ever crosses an isolation
    /// boundary and the compiler can prove it. Call it from the main actor, from an actor
    /// of your own, or from nowhere in particular — it runs where you call it.
    ///
    /// ## Time
    ///
    /// The only runaway protection here is a deadline that every bridged call checks:
    /// past it, the call throws a `WoodcaseError` with `code: 'timeout'`, which the script
    /// may catch. That covers every script that does work.
    ///
    /// It does not cover `while (true) {}`. The public JavaScriptCore headers on macOS 15
    /// carry no execution-time limit and no interrupt — checked 2026-09-07,
    /// `grep -ri 'TimeLimit\|Interrupt'` over the framework's `Headers` finds only license
    /// text — so there is nothing to ask the engine for. A hard bound on a pure loop is a
    /// process-ending watchdog, and that is the CLI's to install: a library host that
    /// called `exit` inside Penumbra would kill the editor.
    ///
    /// Memory is unbounded for the same reason: JavaScriptCore publishes no memory limit
    /// either. A script that allocates without end is the operating system's to stop.
    ///
    /// ## Reading and writing
    ///
    /// `doc` exposes `rev`, `tree`, `get`, `lint` and `schema` for reading, and `set`,
    /// `add`, `replace`, `cp`, `mv`, `rm`, `override`, `vars` and `themes` for writing.
    /// Every write is one ``Woodcase/BatchOperation`` through
    /// ``Woodcase/BatchApplier/applyOne(_:to:recorder:log:file:)``, so the divergence
    /// detection, the revision guard and the activity log are the verbs' own. The host
    /// adds no editing semantics of its own.
    ///
    /// Each call is atomic: `applyOne` validates before it mutates and unwinds a line
    /// that fails part way, so a call that throws has changed nothing and a script that
    /// catches it carries on from a consistent document. Whether the *run* is committed
    /// is the caller's: ``run(_:over:remedy:diagnostics:recorder:deadline:sink:)`` never
    /// writes a file, and the `js` verb wraps the whole run in one
    /// ``Woodcase/PenFileTransaction`` so an uncaught error leaves the file and the log
    /// untouched.
    public enum ScriptHost {
        /// Runs a script against a document, bounded by an absolute deadline.
        ///
        /// Never throws: everything that can go wrong is part of the answer. A source that
        /// will not parse, a refusal from the editing layer, an uncaught throw and a
        /// deadline all come back as ``ScriptRun/error``, with the location and the
        /// sentence.
        ///
        /// - Parameters:
        ///   - sources: The sources to evaluate, in order, in one context. Top-level
        ///     `const` and `let` from an earlier source are visible to a later one — and
        ///     redeclaring the same name is the syntax error it would be in one file.
        ///   - document: The open document. The host reads and writes it in place; what
        ///     becomes of it afterwards belongs to whoever opened it.
        ///   - remedy: Which grammar a refusal's remedy is written in. The `js` verb passes
        ///     ``Woodcase/RemedyDialect/command(file:)`` with the path it was given, so a
        ///     refused address suggests the `woodcase` command to run; a caller with no
        ///     file on disk leaves the default.
        ///   - diagnostics: Diagnostics collected when the file was parsed. `doc.lint`
        ///     reports these alongside its own checks, exactly as `woodcase lint` does —
        ///     the parse happened before the host was handed a document, so they can only
        ///     come from the caller.
        ///   - recorder: The enclosing transaction's ``Woodcase/ActivityRecorder``, so
        ///     every write the script makes is logged exactly as the matching verb logs
        ///     it. `nil` logs nothing — a library caller running a script over an
        ///     in-memory document has no log to write into, and gets the same reports.
        ///   - deadline: When bridged calls should start refusing. `nil` for no bound.
        ///   - sink: Called synchronously with each ``ScriptRun/Event`` as it happens, for
        ///     a live transcript. The same events come back in ``ScriptRun/events``.
        /// - Returns: The whole run.
        public static func run(
            _ sources: [ScriptSource],
            over document: EditableDocument,
            remedy: RemedyDialect = .batch,
            diagnostics: [PenDiagnostic] = [],
            recorder: ActivityRecorder? = nil,
            deadline: ContinuousClock.Instant? = nil,
            sink: ((ScriptRun.Event) -> Void)? = nil
        ) -> ScriptRun {
            ScriptRunner(
                document: document,
                remedy: remedy,
                diagnostics: diagnostics,
                recorder: recorder,
                deadline: deadline,
                sink: sink
            ).run(sources)
        }

        /// Runs a script against a document, bounded by a budget measured from now.
        ///
        /// The same call as ``run(_:over:remedy:diagnostics:recorder:deadline:sink:)``
        /// with the deadline computed for
        /// you — which is what a caller holding a `--timeout` in seconds has.
        ///
        /// - Parameters:
        ///   - sources: The sources to evaluate, in order, in one context.
        ///   - document: The open document.
        ///   - timeout: How long the run may take before bridged calls start refusing.
        ///   - remedy: Which grammar a refusal's remedy is written in.
        ///   - diagnostics: Diagnostics collected when the file was parsed.
        ///   - recorder: The enclosing transaction's recorder, or `nil` to log nothing.
        ///   - sink: Called synchronously with each event as it happens.
        /// - Returns: The whole run.
        public static func run(
            _ sources: [ScriptSource],
            over document: EditableDocument,
            timeout: Duration,
            remedy: RemedyDialect = .batch,
            diagnostics: [PenDiagnostic] = [],
            recorder: ActivityRecorder? = nil,
            sink: ((ScriptRun.Event) -> Void)? = nil
        ) -> ScriptRun {
            run(
                sources,
                over: document,
                remedy: remedy,
                diagnostics: diagnostics,
                recorder: recorder,
                deadline: ContinuousClock.now.advanced(by: timeout),
                sink: sink
            )
        }
    }

#endif
