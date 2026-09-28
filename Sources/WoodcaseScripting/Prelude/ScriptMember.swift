//
//  ScriptMember.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import JavaScriptCore
    import Woodcase

    /// One member of `doc`, as the prelude actually defines it.
    ///
    /// Read back from the running prelude rather than written down a second time in Swift.
    /// `woodcase help js` prints a `.d.ts` declaration of `doc`, and a declaration that
    /// drifts from the runtime is worse than none: it teaches a call that throws. So the
    /// help topic's test asks ``ScriptHost/members()`` what exists and checks it against
    /// the `.d.ts` in both directions.
    public struct ScriptMember: Friendly {
        /// Names a member.
        ///
        /// - Parameters:
        ///   - name: The member's name on `doc`, dotted for one inside a namespace.
        ///   - kind: Whether it is read, called, or an object holding more members.
        ///   - options: The option keys it accepts, in declaration order.
        public init(name: String, kind: Kind, options: [String]) {
            self.name = name
            self.kind = kind
            self.options = options
        }

        /// The member's name on `doc`, as a caller writes it.
        ///
        /// Dotted for a member inside a namespace: `vars.rm`, `themes.set`. The
        /// namespace itself is listed too, immediately before its members, so a reader
        /// walking the list in order sees the shape the `.d.ts` has.
        public let name: String

        /// Whether the member is read or called.
        public let kind: Kind

        /// The keys its options object accepts, in the order the prelude declares them.
        /// Empty for a member that takes no options.
        public let options: [String]

        /// What a member is.
        public enum Kind: String, Friendly, CaseIterable {
            /// Read, not called: `doc.rev`.
            case value

            /// Called: `doc.tree(…)`.
            case call

            /// An object holding more members: `doc.vars`, `doc.themes`.
            ///
            /// It takes no options and is never called; the members under it are listed
            /// separately, under their dotted names.
            case namespace
        }
    }

    public extension ScriptHost {
        /// Every member `doc` exposes, with the option keys each one takes.
        ///
        /// Evaluates the prelude in a context of its own and asks it — so this is the
        /// runtime's answer, not a list kept beside it. Reads no document and runs no
        /// script.
        ///
        /// - Returns: The members, in the order the prelude declares them, each namespace
        ///   followed by its own members; empty only if the prelude itself failed to
        ///   evaluate, which is a bug in woodcase.
        static func members() -> [ScriptMember] {
            guard let context = JSContext() else { return [] }
            // The prelude closes over the bridge, and this asks it nothing that needs one.
            context.setObject(JSValue(newObjectIn: context), forKeyedSubscript: "__woodcaseNative" as NSString)
            guard let internals = context.evaluateScript(ScriptPrelude.javaScript),
                  let json = internals.invokeMethod("members", withArguments: [])?.toString(),
                  let table = try? JSONDecoder().decode([ScriptMember].self, from: Data(json.utf8))
            else { return [] }
            return table
        }

        /// The members `doc` itself exposes, without the ones nested inside a namespace.
        ///
        /// The list an unknown-member sentence names, and the top level of the shipped
        /// `.d.ts`.
        ///
        /// - Returns: The top-level members, in declaration order.
        static func topLevelMembers() -> [ScriptMember] {
            members().filter { !$0.name.contains(".") }
        }
    }

#endif
