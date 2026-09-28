//
//  ScriptContext.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import JavaScriptCore
    import Woodcase

    /// Builds the world a script wakes up in: the native bridge, the prelude, and the
    /// handful of helpers Swift keeps a handle on.
    ///
    /// Every native takes one JSON string and returns one JSON string. Uniform on
    /// purpose: one marshalling road to test, no `JSExport` protocol to keep in step with
    /// a Swift signature, and no `toDictionary()` walking an object graph a second time.
    enum ScriptContext {
        /// The name the native bridge is installed under while the prelude runs, and
        /// deleted from after.
        private static let bridgeName = "__woodcaseNative"

        /// Installs the bridge, evaluates the prelude, and takes the helpers away from the
        /// script.
        ///
        /// The prelude is one IIFE over the bridge: it captures the natives lexically and
        /// returns the helpers, so once the global is deleted a script can neither call
        /// the raw bridge nor replace `makeError` under a refusal.
        ///
        /// - Parameters:
        ///   - runner: The run to bind the natives to.
        ///   - context: The context to build in.
        /// - Returns: The prelude's helper object, or `nil` if the prelude itself failed —
        ///   which is a bug in woodcase, not in anyone's script.
        static func install(runner: ScriptRunner, into context: JSContext) -> JSValue? {
            guard let bridge = JSValue(newObjectIn: context) else { return nil }
            for (name, block) in natives(of: runner) {
                bridge.setObject(block, forKeyedSubscript: name as NSString)
            }
            context.setObject(bridge, forKeyedSubscript: bridgeName as NSString)

            context.exception = nil
            let internals = context.evaluateScript(
                ScriptPrelude.javaScript,
                withSourceURL: URL(fileURLWithPath: "<woodcase prelude>")
            )
            guard context.exception == nil, let internals, !internals.isUndefined else {
                context.exception = nil
                return nil
            }
            context.globalObject.deleteProperty(bridgeName)
            return internals
        }

        // MARK: - The natives

        /// Every native, keyed by the name the prelude calls it under.
        ///
        /// - Parameter runner: The run the natives read and record against.
        /// - Returns: The blocks, ready to install.
        private static func natives(
            of runner: ScriptRunner
        ) -> [(String, @convention(block) (String) -> Any?)] {
            [
                ("rev", bridge(runner) { runner, _ in try ScriptBridge.rev(runner) }),
                ("tree", bridge(runner) { runner, json in try ScriptBridge.tree(json, runner) }),
                ("get", bridge(runner) { runner, json in try ScriptBridge.get(json, runner) }),
                ("lint", bridge(runner) { runner, json in try ScriptBridge.lint(json, runner) }),
                ("schema", bridge(runner) { runner, json in try ScriptBridge.schema(json, runner) }),
                ("log", bridge(runner) { runner, json in try ScriptBridge.log(json, runner) }),
                // Two natives for eleven write members, because the members divide in
                // two: nine are batch operations, and the two removals are the writes
                // the batch grammar deliberately has no verb for.
                ("write", bridge(runner) { runner, json in try ScriptWrite.apply(json, runner) }),
                ("remove", bridge(runner) { runner, json in try ScriptWrite.remove(json, runner) }),
            ]
        }

        /// Wraps one read as a block the prelude can call.
        ///
        /// Three things happen here and nowhere else, so no read has to remember them:
        /// the deadline is checked before any work, a Swift throw becomes a
        /// `WoodcaseError` the script can catch, and a read that answers nothing returns
        /// `undefined` rather than a string nobody parses.
        ///
        /// - Parameters:
        ///   - runner: The run to bind to.
        ///   - body: The read, taking the request JSON and answering with response JSON.
        /// - Returns: The block.
        private static func bridge(
            _ runner: ScriptRunner,
            _ body: @escaping (ScriptRunner, String) throws -> String?
        ) -> @convention(block) (String) -> Any? {
            { request in
                guard let context = JSContext.current() else { return nil }
                do {
                    try runner.checkDeadline()
                    return try body(runner, request)
                } catch {
                    context.exception = runner.raise(error, in: context)
                    return nil
                }
            }
        }
    }

#endif
