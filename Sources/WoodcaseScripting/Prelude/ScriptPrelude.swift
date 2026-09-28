//
//  ScriptPrelude.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation

    /// The JavaScript the host evaluates before any script: `doc`, `console`,
    /// `WoodcaseError`, and the guards that say a script is synchronous.
    ///
    /// A Swift string constant, the way `WoodcaseViewer`'s `ViewerScript` is: it ships
    /// inside the binary, there is no resource to lose, and a test can evaluate it without
    /// a bundle.
    ///
    /// ## Two constants, one IIFE
    ///
    /// The source outgrew one readable file when the write members landed, so it is
    /// concatenated from this file's ``vocabulary`` — the error class, `console`, the
    /// synchrony guards, the member table and every argument check — and
    /// ``ScriptPreludeAPI/surface``, which defines `doc` and returns the helpers Swift
    /// calls back into. The split is textual, not structural: ``javaScript`` is one
    /// function expression, opened here and closed there, so everything stays in one
    /// lexical scope over the native bridge.
    ///
    /// ## What lives here rather than in Swift
    ///
    /// Everything that is about *the shape of a call*: which members `doc` has, which
    /// option keys each takes, what an argument must be. Two reasons. The sentence a
    /// mistake earns is best written where the mistake happens — `doc.setProps` is a
    /// property read, and only a `Proxy` can see one. And it keeps the Swift side honest:
    /// it receives shapes that have already been checked, so it validates *vocabulary*
    /// (is `clipped` a lint check?) and never *shape*.
    ///
    /// ## What crosses, and how
    ///
    /// Every native call takes one JSON string and returns one JSON string. No
    /// `toDictionary`, no `JSExport`, no object graph walked twice: the library's `Codable`
    /// values are encoded once, `JSON.parse` builds the JavaScript value, and the same
    /// road runs the other way. That is also why a script's values arrive *typed* — an
    /// integer written in JavaScript is stored as an integer, not as `10.0`, and a `$name`
    /// string stays a string.
    ///
    /// A write goes the same way, and goes further: the object a write member builds *is*
    /// a batch line — `{"op":"set","target":…,"props":{…}}` — so the JSONL grammar and the
    /// script grammar are one grammar with two surfaces rather than two tables to keep in
    /// step.
    ///
    /// ## Privacy
    ///
    /// The whole prelude is one IIFE over the native object. It defines the globals a
    /// script sees and returns the handful of helpers Swift calls back into; the host then
    /// deletes the native object from the global scope, so a script can neither reach the
    /// raw bridge nor replace the helpers under it.
    enum ScriptPrelude {
        /// The prelude source: the vocabulary, the row view and the surface, as one
        /// function expression.
        static var javaScript: String {
            vocabulary + rowView + ScriptPreludeAPI.surface
        }

        /// The row `doc.tree` hands back, bound inside the prelude's own scope.
        ///
        /// The same text ``RowPredicate`` evaluates, in the dialect a script reads: a
        /// refusal here says `props: ['kind.x']` where `find`'s says `--props kind.x`,
        /// and it is thrown as the `WoodcaseError` every other refusal is. Private by
        /// construction — it is a `const` inside the IIFE, so a script can neither reach
        /// the factory nor build itself an unguarded row.
        private static var rowView: String {
            """
              // ── The row a read hands back ────────────────────────────────────────────
              const makeRowView = \(RowViewPrelude.javaScript);

            """
        }

        /// The error class, `console`, the synchrony guards, the member table and the
        /// argument checks — everything `doc` is built *out of*.
        private static let vocabulary = #"""
        (function (native) {
          'use strict';

          // ── WoodcaseError ────────────────────────────────────────────────────────
          // Every refusal a script can catch is one of these: the sentence the verb
          // would have printed, the machine-readable `code`, and the nodes the sentence
          // named as values rather than as prose.
          class WoodcaseError extends Error {
            constructor(message, code, candidates) {
              super(message);
              this.name = 'WoodcaseError';
              this.code = code || 'scriptError';
              this.candidates = candidates || [];
            }
          }
          globalThis.WoodcaseError = WoodcaseError;

          function fail(message, code, candidates) {
            throw new WoodcaseError(message, code, candidates);
          }

          const HELP = '`woodcase help js` prints them';

          // ── Rendering a value for console ────────────────────────────────────────
          function render(value) {
            if (typeof value === 'string') return value;
            if (value === undefined) return 'undefined';
            if (value === null) return 'null';
            if (typeof value === 'function') {
              return '[function ' + (value.name || 'anonymous') + ']';
            }
            if (typeof value === 'symbol') return value.toString();
            if (value instanceof Error) {
              return value.name + ': ' + value.message;
            }
            try {
              const text = JSON.stringify(value);
              return text === undefined ? String(value) : text;
            } catch (error) {
              return '[unprintable: ' + (error && error.message ? error.message : 'circular') + ']';
            }
          }

          function emit(level, args) {
            const text = Array.prototype.map.call(args, render).join(' ');
            native.log(JSON.stringify({ level: level, text: text }));
          }

          globalThis.console = {
            log: function () { emit('log', arguments); },
            info: function () { emit('log', arguments); },
            debug: function () { emit('log', arguments); },
            warn: function () { emit('warn', arguments); },
            error: function () { emit('error', arguments); }
          };

          // ── There is no event loop ───────────────────────────────────────────────
          // JavaScriptCore runs a script to completion: no timers, no I/O, nothing to
          // resume a callback. Each of these is a mistake a model makes on day one, and
          // silence — or a bare TypeError — teaches nothing.
          const SYNCHRONOUS =
            'a woodcase script runs to completion in one pass, with no event loop, '
            + 'because the whole run is one file transaction and the file lock cannot '
            + 'outlive it';

          function synchronousOnly(name, remedy) {
            fail(name + ' is not available: ' + SYNCHRONOUS + ' — ' + remedy, 'synchronousOnly');
          }

          const INLINE = 'do the work inline, in the order you want it done';
          globalThis.setTimeout = function () { synchronousOnly('setTimeout', INLINE); };
          globalThis.setInterval = function () { synchronousOnly('setInterval', INLINE); };
          globalThis.setImmediate = function () { synchronousOnly('setImmediate', INLINE); };
          globalThis.queueMicrotask = function () { synchronousOnly('queueMicrotask', INLINE); };
          globalThis.clearTimeout = function () { synchronousOnly('clearTimeout', INLINE); };
          globalThis.clearInterval = function () { synchronousOnly('clearInterval', INLINE); };
          globalThis.fetch = function () {
            synchronousOnly(
              'fetch',
              'a script sees `doc`, `console` and the language, and nothing else; pass '
                + 'what it needs in from the shell that runs it'
            );
          };
          globalThis.XMLHttpRequest = function () {
            synchronousOnly('XMLHttpRequest', 'a script reaches no network');
          };
          globalThis.require = function () {
            synchronousOnly(
              'require',
              'there are no modules to load; put shared code in its own file and pass it '
                + 'first, `woodcase js file.pen -F helpers.js -F run.js`'
            );
          };

          // ── The members of doc ───────────────────────────────────────────────────
          // One table. The Proxy's sentences, the option checks and `woodcase help js`
          // all read it, so a member cannot exist without being teachable.
          //
          // `address` says what the first argument is; `options` is the keys the last
          // one takes; `retired` gives a better sentence for a CLI flag that has no
          // option form here. A `namespace` holds a table of its own and teaches at its
          // own level, so `doc.vars.reset` is as well answered as `doc.reset`.
          const TAG_IS_A_RETURN_VALUE =
            'a batch tag exists so a later JSONL line can name what an earlier one '
            + 'created; a program has the return value — `const hero = doc.add(…)`, then '
            + '`doc.set(hero.id, …)`';

          const MEMBERS = {
            rev: { kind: 'value' },
            tree: {
              kind: 'call',
              address: 'optional',
              options: {
                depth: 'wholeNumber',
                expand: 'boolean',
                props: 'propertyPaths',
                theme: 'theme'
              },
              retired: {
                absolute:
                  'every row already carries both `rect` and `absRect`, so there is '
                  + 'nothing to switch — read `r.absRect` for document space'
              }
            },
            get: {
              kind: 'call',
              address: 'required',
              options: { expand: 'boolean' },
              retired: {
                instances:
                  '`--instances` is a different report about a component, not an option '
                  + 'on this one'
              }
            },
            lint: {
              kind: 'call',
              address: 'optional',
              options: { exclude: 'strings', severity: 'string', theme: 'theme' },
              retired: {
                summary: '`--summary` counts the findings the CLI prints; count them '
                  + 'yourself with `doc.lint().length`',
                list: '`--list` is the catalogue of checks and reads no document'
              }
            },
            schema: { kind: 'call', address: 'typeName', options: {} },
            set: { kind: 'call', address: 'required', options: { rev: 'string' } },
            add: {
              kind: 'call',
              address: 'parent',
              options: { at: 'wholeNumber', rev: 'string' },
              retired: { tag: TAG_IS_A_RETURN_VALUE }
            },
            replace: { kind: 'call', address: 'required', options: { rev: 'string' } },
            cp: {
              kind: 'call',
              address: 'required',
              options: {
                at: 'wholeNumber',
                props: 'properties',
                each: 'propertyRows',
                rev: 'string'
              },
              retired: {
                tag: TAG_IS_A_RETURN_VALUE,
                name: "a copy's name is one of its properties — write "
                  + "props: { 'common.name': 'Chip 2' }",
                times: "`--times` is the CLI's way of writing a loop; write one, or pass "
                  + '`each` one row of properties per copy'
              }
            },
            mv: { kind: 'call', address: 'required', options: { at: 'wholeNumber', rev: 'string' } },
            rm: { kind: 'call', address: 'required', options: { detach: 'boolean', rev: 'string' } },
            override: {
              kind: 'call',
              address: 'required',
              options: { unset: 'strings', rev: 'string' }
            },
            vars: {
              kind: 'namespace',
              noun: "the document's variables",
              members: {
                set: { kind: 'call', options: {} },
                rm: { kind: 'call', options: { force: 'boolean' } }
              }
            },
            themes: {
              kind: 'namespace',
              noun: "the document's theme axes",
              members: {
                set: { kind: 'call', options: {} },
                rm: { kind: 'call', options: {} }
              }
            },
            imports: {
              kind: 'namespace',
              noun: "the document's library imports",
              members: {
                set: { kind: 'call', options: {} },
                rm: { kind: 'call', options: { force: 'boolean' } }
              }
            }
          };

          const MEMBER_NAMES = Object.keys(MEMBERS);

          // Reads that are not a member of doc but are not a mistake either: the ones
          // the language itself performs on any object it is handed.
          const PASSTHROUGH = ['toJSON', 'then', 'toString', 'valueOf', 'constructor', 'inspect'];

          // One member, by its name or by its dotted name inside a namespace.
          function specFor(member) {
            const dot = member.indexOf('.');
            if (dot === -1) return MEMBERS[member];
            const outer = MEMBERS[member.slice(0, dot)];
            return outer && outer.members ? outer.members[member.slice(dot + 1)] : undefined;
          }

          function unknownMember(where, name, known) {
            fail(
              where + ' has no ' + name + ' — its members are ' + known.join(', ')
                + '; ' + HELP,
              'unknownMember'
            );
          }

          function refuseAssignment(where, noun, name) {
            fail(
              where + ' is ' + noun + ', not a place to keep things — ' + String(name)
                + ' cannot be assigned. Use a variable of your own.',
              'unknownMember'
            );
          }

          // ── Checking one call's arguments ────────────────────────────────────────
          function optionKeys(member) {
            return Object.keys(specFor(member).options || {});
          }

          function checkOptions(member, options) {
            const spec = specFor(member);
            if (options === undefined || options === null) return {};
            if (typeof options !== 'object' || Array.isArray(options)) {
              fail(
                'doc.' + member + ' takes its options as an object, like { '
                  + (optionKeys(member)[0] || 'key') + ': … } — got ' + describe(options),
                'badArgument'
              );
            }
            const keys = optionKeys(member);
            for (const key of Object.keys(options)) {
              if (options[key] === undefined) continue;
              if (spec.retired && spec.retired[key]) {
                fail(
                  'doc.' + member + ' has no ' + key + ' option: ' + spec.retired[key] + '.',
                  'unknownOption'
                );
              }
              if (keys.indexOf(key) === -1) {
                fail(
                  keys.length === 0
                    ? 'doc.' + member + ' takes no options, and was given ' + key + '.'
                    : 'doc.' + member + ' has no option ' + key + ' — the options it takes are '
                      + keys.join(', ') + '; ' + HELP,
                  'unknownOption'
                );
              }
              check(member, key, spec.options[key], options[key]);
            }
            return options;
          }

          function describe(value) {
            if (value === null) return 'null';
            if (Array.isArray(value)) return 'an array';
            return 'a ' + typeof value;
          }

          function isPlainObject(value) {
            return value !== null && typeof value === 'object' && !Array.isArray(value);
          }

          const PROPERTY_EXAMPLE = "{ 'kind.content': 'Hello' }";

          function check(member, key, shape, value) {
            const where = 'doc.' + member + "'s " + key + ' option ';
            if (shape === 'boolean') {
              if (typeof value !== 'boolean') {
                fail(where + 'is true or false — got ' + describe(value) + '.', 'badArgument');
              }
            } else if (shape === 'wholeNumber') {
              if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
                fail(
                  where + 'counts levels below the root, so it is 0 or more — got '
                    + render(value) + '.',
                  'badArgument'
                );
              }
            } else if (shape === 'string') {
              if (typeof value !== 'string') {
                fail(where + 'is a string — got ' + describe(value) + '.', 'badArgument');
              }
            } else if (shape === 'strings') {
              if (!Array.isArray(value) || value.some(function (v) { return typeof v !== 'string'; })) {
                fail(where + 'is an array of strings — got ' + describe(value) + '.', 'badArgument');
              }
            } else if (shape === 'propertyPaths') {
              if (value === true) {
                fail(
                  where + 'takes an array of property paths, like '
                    + "['kind.fill', 'kind.content'] — the CLI's bare --props has no "
                    + 'form here, because an option key cannot be written bare.',
                  'badArgument'
                );
              }
              if (!Array.isArray(value) || value.some(function (v) { return typeof v !== 'string'; })) {
                fail(
                  where + 'is an array of property paths, like '
                    + "['kind.fill', 'kind.content'] — got " + describe(value) + '.',
                  'badArgument'
                );
              }
            } else if (shape === 'properties') {
              if (!isPlainObject(value)) {
                fail(
                  where + 'is an object of property paths, like ' + PROPERTY_EXAMPLE
                    + ' — got ' + describe(value) + '.',
                  'badArgument'
                );
              }
            } else if (shape === 'propertyRows') {
              if (!Array.isArray(value) || value.length === 0 || !value.every(isPlainObject)) {
                fail(
                  where + 'is one object of properties per copy, like '
                    + "[{ 'common.name': 'Chip 1' }, { 'common.name': 'Chip 2' }] — got "
                    + describe(value) + '.',
                  'badArgument'
                );
              }
            } else if (shape === 'theme') {
              if (!isPlainObject(value)) {
                fail(
                  where + "pins theme axes as an object, like { mode: 'dark' } — got "
                    + describe(value) + '.',
                  'badArgument'
                );
              }
              for (const axis of Object.keys(value)) {
                if (typeof value[axis] !== 'string' || value[axis] === '') {
                  fail(
                    where + 'gives every axis a non-empty option name; ' + axis + ' has '
                      + render(value[axis]) + '.',
                    'badArgument'
                  );
                }
              }
            }
          }

          const ADDRESS_FORMS =
            "an id, a name path, or an instance path, like 'Dashboard/Header/Title'";

          function checkAddress(member, value) {
            const spec = specFor(member);
            if (spec.address === 'required') {
              if (typeof value !== 'string' || value === '') {
                fail(
                  'doc.' + member + ' takes an address first — ' + ADDRESS_FORMS + '. Got '
                    + describe(value) + '.',
                  'badArgument'
                );
              }
              return value;
            }
            if (value === undefined || value === null) return null;
            if (typeof value !== 'string') {
              fail(
                'doc.' + member + ' takes an address first and its options second — '
                  + 'write doc.' + member + '(null, { … }) to '
                  + (member === 'lint' ? 'lint' : 'read') + ' the whole file. Got '
                  + describe(value) + ' where the address goes.',
                'badArgument'
              );
            }
            return value;
          }

          // A parent, where `null` means the document root — the same synonym the CLI
          // spells `document` and a batch line writes as "document".
          function checkParent(member, value) {
            if (value === undefined || value === null) return null;
            if (typeof value !== 'string' || value === '') {
              fail(
                'doc.' + member + ' takes the parent to write into — ' + ADDRESS_FORMS
                  + ' — or null for the document root. Got ' + describe(value) + '.',
                'badArgument'
              );
            }
            return value;
          }

          function checkProperties(member, value, required) {
            if (value === undefined || value === null) {
              if (required) {
                fail(
                  'doc.' + member + ' takes the properties to write as its second argument, '
                    + 'like ' + PROPERTY_EXAMPLE + " — property paths as keys, values in the "
                    + "file's own JSON shape. Got " + describe(value) + '.',
                  'badArgument'
                );
              }
              return {};
            }
            if (!isPlainObject(value)) {
              fail(
                'doc.' + member + ' writes properties from an object, like '
                  + PROPERTY_EXAMPLE + ' — got ' + describe(value) + '.',
                'badArgument'
              );
            }
            if (required && Object.keys(value).length === 0) {
              fail(
                'doc.' + member + ' was given no properties, so it would change nothing — '
                  + 'name at least one, like ' + PROPERTY_EXAMPLE + '.',
                'badArgument'
              );
            }
            return value;
          }

          function checkNode(member, value) {
            if (!isPlainObject(value)) {
              fail(
                'doc.' + member + ' takes a .pen subtree as its second argument: one JSON '
                  + 'object with a type and a name, and optional children, like '
                  + "{ type: 'frame', name: 'Hero' }. Got " + describe(value) + '.',
                'badArgument'
              );
            }
            return value;
          }

          function checkName(member, noun, value) {
            if (typeof value !== 'string' || value === '') {
              fail(
                'doc.' + member + " takes the " + noun + "'s name first, written without a "
                  + '$. Got ' + describe(value) + '.',
                'badArgument'
              );
            }
            return value;
          }

          function checkVariable(value) {
            if (!isPlainObject(value) || typeof value.type !== 'string'
                || !Object.prototype.hasOwnProperty.call(value, 'value')) {
              fail(
                "doc.vars.set takes the variable's definition second: an object with a "
                  + 'type — boolean, color, number or string — and a value, like '
                  + "{ type: 'color', value: '#FF6600' }. Got " + render(value) + '.',
                'badArgument'
              );
            }
            return value;
          }

          function checkAlias(member, value) {
            if (typeof value !== 'string' || value === '') {
              fail(
                'doc.' + member + " takes the import's alias first — the prefix every "
                  + "identifier the library defines takes, like 'V'. Got "
                  + describe(value) + '.',
                'badArgument'
              );
            }
            return value;
          }

          function checkImportPath(value) {
            if (typeof value !== 'string' || value === '') {
              fail(
                "doc.imports.set takes the library's path second, as a string — the file "
                  + "the alias resolves to, like './library.pen'. Got " + describe(value)
                  + '.',
                'badArgument'
              );
            }
            return value;
          }

          function checkAxisOptions(value) {
            if (!Array.isArray(value) || value.length === 0
                || value.some(function (v) { return typeof v !== 'string' || v === ''; })) {
              fail(
                "doc.themes.set takes the axis's options second, as a non-empty array of "
                  + "names, like ['light', 'dark'] — the first is the one that is active "
                  + 'when nothing pins the axis. Got ' + describe(value) + '.',
                'badArgument'
              );
            }
            return value;
          }

        """#
    }

#endif
