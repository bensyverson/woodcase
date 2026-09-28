//
//  RowViewPrelude.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import Woodcase

    /// The row a caller filters, in JavaScript: a `Proxy` over one ``Woodcase/TreeRow``
    /// that refuses a member the row does not have.
    ///
    /// ## Why a row is a `Proxy`
    ///
    /// The mistake this whole file exists for is `r.fontSize` written for
    /// `r.props['kind.fontSize']`. On a plain object that reads `undefined`, and
    /// `undefined < 12` is `false` — so the run succeeds, filters nothing, and the answer
    /// looks like "no rows match" rather than "you asked the wrong question". A silent
    /// wrong answer is the worst outcome a query tool has, and on the *write* side it is
    /// worse still: a filter that matches nothing is a script that writes nothing and
    /// exits 0. So every row is a `Proxy` that refuses a member the row type does not
    /// have, and the refusal lists the members it does. The same trap guards `r.props`,
    /// which refuses a property path nobody asked for.
    ///
    /// ## Why one source for two routes
    ///
    /// `woodcase find` teaches `r.props['kind.fontSize']`, and the next thing a reader
    /// writes is that spelling over `doc.tree` in a script. While the two routes had two
    /// row types the second answered `undefined` to the spelling the first taught. Both
    /// evaluate this text now and differ in exactly three arguments: the property paths
    /// this call asked for, which dialect a remedy is spelled in — `--props kind.x` at a
    /// shell prompt, `props: ['kind.x']` in a script — and how a refusal is thrown.
    /// ``RowPredicate`` brands its own so it can tell them from a predicate's throw; the
    /// script host raises the `WoodcaseError` every other refusal is.
    ///
    /// The member list is read off ``Woodcase/TreeRow`` itself, so a member added to the
    /// row is a member both routes may read the same day.
    enum RowViewPrelude {
        /// Every key a row can carry, read off the row type itself.
        ///
        /// Derived from an encoded ``Woodcase/TreeRow`` rather than written out, so the
        /// sentence a mistake earns can never list a member that no longer exists.
        static let memberNames: [String] = {
            let sample = TreeRow(
                id: "", address: "", rev: "", depth: 0, type: "", name: "",
                rect: .zero, absRect: .zero, clip: .none, overflowAxes: [.horizontal],
                isReusable: false, isInstance: false, isSlot: false, childCount: 0,
                properties: [:]
            )
            guard let data = try? JSONEncoder().encode(sample),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return [] }
            return object.keys.sorted()
        }()

        /// The member list as a JavaScript array literal.
        private static var members: String {
            "[" + memberNames.map { "'\($0)'" }.joined(separator: ", ") + "]"
        }

        /// The source: a function expression taking this call's property paths, the
        /// dialect its remedies are spelled in (`'find'` or `'js'`) and the route's own
        /// `refuse(message, code)`, and returning the function that wraps one row.
        static var javaScript: String {
            #"""
            (function (PATHS, DIALECT, refuse) {
              'use strict';

              const MEMBERS = \#(members);

              // Members of Object.prototype the engine and ordinary code reach for on
              // their own — JSON.stringify asks every object for `toJSON` — so they pass
              // through instead of being read as a mistake. Everything a row crosses back
              // out through depends on it: a result, a console.log, a spread.
              const PASSTHROUGH = [
                'toJSON', 'toString', 'valueOf', 'constructor', 'hasOwnProperty',
                'isPrototypeOf', 'propertyIsEnumerable', 'then', 'inspect'
              ];

              // The one thing the two routes differ in: how a reader asks for a column.
              const REMEDY = {
                find: {
                  asked: 'find',
                  named: '--props',
                  addColumn: function (path) {
                    return 'Add `--props ' + path + '` and the same predicate reads it.';
                  },
                  readColumn: function (path) {
                    return 'with --props ' + path + ' on the command line';
                  }
                },
                js: {
                  asked: 'doc.tree',
                  named: 'the props option',
                  addColumn: function (path) {
                    return "Pass `props: ['" + path + "']` in doc.tree's options and the "
                      + 'same filter reads it.';
                  },
                  readColumn: function (path) {
                    return "with props: ['" + path + "'] in doc.tree's options";
                  }
                }
              }[DIALECT];

              function propsView(row, spelling) {
                return new Proxy(row.properties || {}, {
                  get: function (bag, key) {
                    if (typeof key === 'symbol' || PASSTHROUGH.indexOf(key) >= 0) {
                      return bag[key];
                    }
                    const read = 'r.' + spelling + "['" + key + "']";
                    if (PATHS.length === 0) {
                      refuse(
                        read + ' needs a column: this ' + REMEDY.asked + ' asked for none, '
                          + 'so no row carries a property bag. ' + REMEDY.addColumn(key),
                        'unknownMember'
                      );
                    }
                    if (PATHS.indexOf(key) < 0) {
                      refuse(
                        read + ' is not a column of this ' + REMEDY.asked + ', which asked '
                          + 'for ' + PATHS.join(', ') + '. A row carries the paths '
                          + REMEDY.named + ' named and no others; property paths are '
                          + 'prefixed, like kind.fontSize or common.name.',
                        'unknownMember'
                      );
                    }
                    return bag[key];
                  }
                });
              }

              return function (row) {
                return new Proxy(row, {
                  get: function (target, key) {
                    if (typeof key === 'symbol' || PASSTHROUGH.indexOf(key) >= 0) {
                      return target[key];
                    }
                    // `properties` is the row's own key — what tree --json prints — and
                    // `props` the shorthand the primer teaches. One view behind both, so a
                    // path nobody asked for is refused whichever way it is spelled.
                    if (key === 'props' || key === 'properties') {
                      return propsView(target, key);
                    }
                    if (MEMBERS.indexOf(key) >= 0) {
                      return target[key];
                    }
                    refuse(
                      'a row has no ' + key + '. Its members are ' + MEMBERS.join(', ')
                        + ", and a property of the node itself is read as r.props['kind."
                        + key + "'] " + REMEDY.readColumn('kind.' + key) + '.',
                      'unknownMember'
                    );
                  }
                });
              };
            })
            """#
        }
    }

#endif
