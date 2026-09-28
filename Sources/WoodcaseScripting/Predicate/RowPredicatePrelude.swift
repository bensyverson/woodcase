//
//  RowPredicatePrelude.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation

    /// The JavaScript a `find` predicate wakes up inside.
    ///
    /// One function taking the requested property paths and returning the three helpers
    /// ``RowPredicate`` calls: `isFunction`, `kindOf` and `match`. It captures the paths
    /// lexically, so nothing a predicate can reach lets it widen its own view of a row.
    ///
    /// The row itself is ``RowViewPrelude``'s, which `doc.tree` hands a script too — the
    /// spelling `find` teaches has to be the spelling a script reads. What is *not*
    /// shared is how a refusal is thrown, and this file holds this route's answer twice
    /// over: a row's refusal is branded with `woodcaseFind` so ``RowPredicate`` can tell
    /// its own sentence from a throw out of the predicate's code — a JavaScriptCore
    /// `Error` records the line it was *constructed* on, and one built in here would
    /// locate the failure in this prelude rather than in what the caller typed — and
    /// `doc`, which a predicate has no business reaching, refuses with the same brand.
    enum RowPredicatePrelude {
        /// The source, evaluated once per predicate and called with the requested
        /// property paths.
        static var javaScript: String {
            """
            (function (PATHS) {
              'use strict';

              function refuse(message, code) {
                const error = new Error(message);
                error.code = code;
                error.woodcaseFind = true;
                throw error;
              }

              const rowView = \(RowViewPrelude.javaScript)(PATHS, 'find', refuse);

              Object.defineProperty(globalThis, 'doc', {
                get: function () {
                  refuse(
                    'doc is not available here: find is a read, and its predicate sees one row '
                      + 'at a time and nothing else. `woodcase js` is where doc lives — it runs '
                      + 'a whole program inside one file transaction.',
                    'unknownMember'
                  );
                }
              });

              return {
                isFunction: function (value) {
                  return typeof value === 'function';
                },
                kindOf: function (value) {
                  return value === null ? 'null' : typeof value;
                },
                match: function (predicate, rowsJSON) {
                  const rows = JSON.parse(rowsJSON);
                  const matched = [];
                  for (let index = 0; index < rows.length; index += 1) {
                    try {
                      if (predicate(rowView(rows[index]))) {
                        matched.push(index);
                      }
                    } catch (error) {
                      return { matched: matched, index: index, error: error };
                    }
                  }
                  return { matched: matched, index: -1, error: null };
                }
              };
            })
            """
        }
    }

#endif
