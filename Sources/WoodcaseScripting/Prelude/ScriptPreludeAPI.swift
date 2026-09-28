//
//  ScriptPreludeAPI.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation

    /// The second half of the prelude: `doc` itself, and the helpers Swift calls back into.
    ///
    /// Split from ``ScriptPrelude/javaScript``'s first half only because one file of both
    /// stopped being readable when the write members landed. It is not a separate script:
    /// ``ScriptPrelude/javaScript`` concatenates the two, so this text continues inside the
    /// function expression the other opens — and closes it — and everything the first half
    /// defines is in scope here.
    ///
    /// The division of labour is real even if the seam is textual. The first half is the
    /// *vocabulary*: what a member is, what an argument must be, what a mistake earns. This
    /// half is the *surface*: thirteen writes and five reads, each one a few lines that
    /// check their arguments through that vocabulary and hand a JSON string to a native.
    enum ScriptPreludeAPI {
        /// `doc`, its three nested objects, and the helper object the host keeps.
        static let surface = #"""
          // ── doc ──────────────────────────────────────────────────────────────────
          // Every write builds a batch line and sends it across: the JSONL grammar and
          // the script grammar are the same grammar. `undefined` fields disappear in
          // JSON.stringify, which is exactly what an omitted batch field means.
          function write(line) {
            return JSON.parse(native.write(JSON.stringify(line)));
          }

          function unwrite(call) {
            return JSON.parse(native.remove(JSON.stringify(call)));
          }

          const vars = {
            set: function (name, variable, options) {
              checkOptions('vars.set', options);
              return write({
                op: 'var',
                name: checkName('vars.set', 'variable', name),
                value: checkVariable(variable)
              });
            },
            rm: function (name, options) {
              const line = checkOptions('vars.rm', options);
              return unwrite({
                kind: 'variable',
                name: checkName('vars.rm', 'variable', name),
                force: line.force
              });
            }
          };

          const themes = {
            set: function (axis, axisOptions, options) {
              checkOptions('themes.set', options);
              return write({
                op: 'theme-axis',
                name: checkName('themes.set', 'axis', axis),
                options: checkAxisOptions(axisOptions)
              });
            },
            rm: function (axis, options) {
              checkOptions('themes.rm', options);
              return unwrite({
                kind: 'themeAxis',
                name: checkName('themes.rm', 'axis', axis)
              });
            }
          };

          const imports = {
            set: function (alias, path, options) {
              checkOptions('imports.set', options);
              return write({
                op: 'import',
                alias: checkAlias('imports.set', alias),
                path: checkImportPath(path)
              });
            },
            rm: function (alias, options) {
              const line = checkOptions('imports.rm', options);
              return unwrite({
                kind: 'importAlias',
                name: checkAlias('imports.rm', alias),
                force: line.force
              });
            }
          };

          // A nested object of doc teaches at its own level: `doc.vars.reset` earns the
          // same sentence `doc.reset` does, naming the members vars actually has.
          function nested(name, implementation) {
            const known = Object.keys(MEMBERS[name].members);
            const noun = MEMBERS[name].noun;
            return new Proxy({}, {
              get: function (target, key) {
                if (typeof key === 'symbol') return undefined;
                if (Object.prototype.hasOwnProperty.call(implementation, key)) {
                  return implementation[key];
                }
                if (PASSTHROUGH.indexOf(key) !== -1) return undefined;
                unknownMember('doc.' + name, key, known);
              },
              set: function (target, key) { refuseAssignment('doc.' + name, noun, key); },
              has: function (target, key) { return known.indexOf(key) !== -1; },
              ownKeys: function () { return known.slice(); },
              getOwnPropertyDescriptor: function (target, key) {
                if (known.indexOf(key) === -1) return undefined;
                return { configurable: true, enumerable: true, writable: false };
              }
            });
          }

          const api = {
            tree: function (address, options) {
              const asked = checkOptions('tree', options);
              const rows = JSON.parse(native.tree(JSON.stringify({
                address: checkAddress('tree', address),
                options: asked
              })));
              // The guarded row a find predicate sees, so the spelling one route teaches
              // is the spelling the other reads: r.props refuses a path this call did not
              // ask for rather than answering undefined to a filter that then keeps
              // nothing.
              return rows.map(makeRowView(asked.props || [], 'js', fail));
            },
            get: function (address, options) {
              return JSON.parse(native.get(JSON.stringify({
                address: checkAddress('get', address),
                options: checkOptions('get', options)
              })));
            },
            lint: function (address, options) {
              return JSON.parse(native.lint(JSON.stringify({
                address: checkAddress('lint', address),
                options: checkOptions('lint', options)
              })));
            },
            schema: function (type, options) {
              checkOptions('schema', options);
              if (type !== undefined && type !== null && typeof type !== 'string') {
                fail(
                  "doc.schema takes a node type name, like 'text', or nothing at all for "
                    + 'the overview. Got ' + describe(type) + '.',
                  'badArgument'
                );
              }
              return JSON.parse(native.schema(JSON.stringify({
                type: type === undefined ? null : type
              })));
            },
            set: function (address, props, options) {
              const line = checkOptions('set', options);
              return write({
                op: 'set',
                target: checkAddress('set', address),
                props: checkProperties('set', props, true),
                rev: line.rev
              });
            },
            add: function (parent, node, options) {
              const line = checkOptions('add', options);
              return write({
                op: 'add',
                parent: checkParent('add', parent),
                node: checkNode('add', node),
                at: line.at,
                rev: line.rev
              });
            },
            replace: function (address, node, options) {
              const line = checkOptions('replace', options);
              return write({
                op: 'replace',
                target: checkAddress('replace', address),
                node: checkNode('replace', node),
                rev: line.rev
              });
            },
            cp: function (address, parent, options) {
              const line = checkOptions('cp', options);
              return write({
                op: 'cp',
                source: checkAddress('cp', address),
                parent: checkParent('cp', parent),
                at: line.at,
                props: line.props,
                each: line.each,
                rev: line.rev
              });
            },
            mv: function (address, parent, options) {
              const line = checkOptions('mv', options);
              return write({
                op: 'mv',
                target: checkAddress('mv', address),
                parent: checkParent('mv', parent),
                at: line.at,
                rev: line.rev
              });
            },
            rm: function (address, options) {
              const line = checkOptions('rm', options);
              return write({
                op: 'rm',
                target: checkAddress('rm', address),
                detach: line.detach,
                rev: line.rev
              });
            },
            override: function (address, props, options) {
              const line = checkOptions('override', options);
              return write({
                op: 'override',
                target: checkAddress('override', address),
                props: checkProperties('override', props, false),
                unset: line.unset,
                rev: line.rev
              });
            },
            vars: nested('vars', vars),
            themes: nested('themes', themes),
            imports: nested('imports', imports)
          };

          globalThis.doc = new Proxy({}, {
            get: function (target, name) {
              if (typeof name === 'symbol') return undefined;
              if (name === 'rev') return JSON.parse(native.rev('{}'));
              if (Object.prototype.hasOwnProperty.call(api, name)) return api[name];
              if (PASSTHROUGH.indexOf(name) !== -1) return undefined;
              unknownMember('doc', name, MEMBER_NAMES);
            },
            set: function (target, name) {
              refuseAssignment('doc', 'the document', name);
            },
            has: function (target, name) {
              return MEMBER_NAMES.indexOf(name) !== -1;
            },
            ownKeys: function () {
              return MEMBER_NAMES.slice();
            },
            getOwnPropertyDescriptor: function (target, name) {
              if (MEMBER_NAMES.indexOf(name) === -1) return undefined;
              return { configurable: true, enumerable: true, writable: false };
            }
          });

          // ── What Swift calls back into ───────────────────────────────────────────
          return {
            // Builds a real WoodcaseError, so `catch (e) { e instanceof WoodcaseError }`
            // works for a refusal raised on the Swift side too.
            makeError: function (json) {
              const it = JSON.parse(json);
              return new WoodcaseError(it.message, it.code, it.candidates);
            },
            // Decides whether the last source's completion value can cross into the run's
            // result, and says why when it cannot. Done here because JSON.stringify is
            // the crossing, and the value belongs to this context.
            result: function (value) {
              if (value === undefined) return JSON.stringify({ kind: 'empty' });
              const kind = typeof value;
              if (kind === 'function') {
                return JSON.stringify({
                  kind: 'unstringifiable',
                  message:
                    "the script's last expression is a function, which cannot cross into "
                    + 'the result — call it, and end with what it returns.'
                });
              }
              if (kind === 'symbol') {
                return JSON.stringify({
                  kind: 'unstringifiable',
                  message:
                    "the script's last expression is a symbol, which JSON cannot carry — "
                    + 'end with a value JSON can: an object, an array, a string, a number.'
                });
              }
              if (value !== null && kind === 'object' && typeof value.then === 'function') {
                return JSON.stringify({
                  kind: 'unstringifiable',
                  message:
                    "the script's last expression is a Promise, and nothing will ever "
                    + 'resolve it: ' + SYNCHRONOUS + ' — end with a plain value instead.'
                });
              }
              try {
                const text = JSON.stringify(value);
                if (text === undefined) {
                  return JSON.stringify({
                    kind: 'unstringifiable',
                    message:
                      "the script's last expression is a value JSON cannot carry — end "
                      + 'with an object, an array, a string, a number or a boolean.'
                  });
                }
                return JSON.stringify({ kind: 'value', json: text });
              } catch (error) {
                const cyclic = /circular|cyclic/i.test(String(error && error.message));
                return JSON.stringify({
                  kind: 'unstringifiable',
                  message: cyclic
                    ? "the script's last expression contains a cycle, which JSON cannot "
                      + 'carry — end with a value that does not refer back to itself.'
                    : "the script's last expression could not be encoded as JSON ("
                      + String(error && error.message) + ') — end with a value JSON can carry.'
                });
              }
            },
            // The member table, flattened, for the reflection test that keeps the shipped
            // .d.ts honest. A namespace is listed itself and then its members, each under
            // the dotted name a caller writes.
            members: function () {
              const out = [];
              for (const name of MEMBER_NAMES) {
                const spec = MEMBERS[name];
                out.push({
                  name: name,
                  kind: spec.kind,
                  options: spec.options ? Object.keys(spec.options) : []
                });
                for (const inner of Object.keys(spec.members || {})) {
                  out.push({
                    name: name + '.' + inner,
                    kind: spec.members[inner].kind,
                    options: spec.members[inner].options
                      ? Object.keys(spec.members[inner].options)
                      : []
                  });
                }
              }
              return JSON.stringify(out);
            }
          };
        })(__woodcaseNative);
        """#
    }

#endif
