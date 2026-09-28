//
//  HelpTopic+Js.swift
//  WoodcaseCommandCore
//

/// The body of ``HelpTopic/js``: the contract a `woodcase js` program runs under, and
/// the TypeScript declaration of everything it can reach.
///
/// Two tests hold this file to the code it describes, because a primer that teaches a
/// call which throws is worse than no primer. `JsTopicTests` extracts every snippet —
/// each is an indented block whose first line is the comment naming the command that
/// runs it — writes it to a file and runs it through the real binary against a fresh
/// copy of the fixture that comment names, requiring exit 0. `JsDeclarationTests` parses
/// the `declare const doc` block and checks it against
/// ``WoodcaseScripting/ScriptHost/members()`` in both directions: every member and
/// option key the prelude defines is declared here, and everything declared here exists
/// at runtime.
///
/// The declaration is written by hand rather than generated from that table. The table
/// knows a member's name, whether it is called, and its option keys — it knows nothing
/// of parameters, return types or what any of it means, so a generated `.d.ts` would be
/// a worse declaration than this one and still need the same test to stay honest. What
/// generation would have bought, the reflection test buys instead.
extension HelpTopic {
    static let jsTopic = #"""
    WHICH ROUTE
      A verb is often enough. `cp --each rows.jsonl` fans one template out over data;
      `apply` applies a fixed list of edits in one transaction; `find` asks a question — a
      JavaScript predicate over the rows `tree` prints — and exits 1 when the answer is
      none. Reach for `js` when control flow is the point: what to write depends on what a
      read just said, a loop carries a running total, a measurement decides whether to
      commit at all. That last one is what no batch can express.
      The exit codes differ because the questions do. A `find` predicate that throws exits
      2: the predicate IS the invocation, and a question that cannot be asked is malformed.
      A `js` script that throws exits 1: the script is the check, it ran, and the answer is
      no. Either way the file is untouched.

    THE THREE RULES
      ONE TRANSACTION. Nothing is written until the script ends without an uncaught
      error. A throw, a refusal you did not catch, the --timeout, a kill: the file is byte
      for byte what it was and the activity log gained nothing. There is no partial commit
      to reason about, and `undo` reverses the whole run as one step.
      EACH CALL IS ATOMIC. A call validates before it mutates, so a call that threw has
      changed nothing. Catch it and carry on: the document is consistent, and everything
      the run does afterwards still commits.
      READS SEE SETTLED LAYOUT. Every read after a write lays the document out again
      first, so a rect from `doc.tree` includes what you just wrote. Measure after the
      write, and throw rather than commit when the measurement is wrong.

    NO SESSION
      Nothing persists between runs and nothing is auto-loaded. A run is a process holding
      a file lock; when it ends, its globals end with it. Durable code is a file: -F
      repeats, and `woodcase js design.pen -F helpers.js -F run.js` evaluates the helpers
      first, in the same context, so a function defined in the first is callable from the
      second, and an error in the second reports that file's line rather than a line in a
      concatenation. Top-level const and let are shared across the sources, so declaring
      the same name in both is a syntax error — exit 2, naming the file and the line.

    SYNCHRONOUS, AND ALONE
      A script runs to completion in one pass. There is no event loop, so setTimeout,
      setInterval, fetch, require and top-level await each refuse with a sentence saying
      why, and a Promise as the last expression is a value nothing will ever resolve. The
      script sees `doc`, `console` and the language, and nothing else: no files, no
      network, no modules — what it needs comes in from the shell that runs it.

    WHAT COMES BACK
      Every write prints a row as it happens — the member, the path, the id, (+N) for the
      descendants it made, divergences indented under it — with console.log between the
      rows where you printed it and console.warn and console.error on stderr. The last
      expression of the last source is the run's `result`, as JSON: end with
      `({ rows: doc.tree('List'), lint: doc.lint() })` for a structured answer. No
      wrapping function, and no top-level return.

    WHEN A CALL REFUSES
      Every refusal is a WoodcaseError: the sentence the verb would have printed, a `code`
      to branch on, and `candidates` when the sentence listed any. `doc.setProps` names
      doc's real members; an unknown option key names the keys that member takes;
      variableInUse and importInUse refuse to strand a reference, and `{ force: true }`
      opts into it; revisionConflict is a stale `rev` on a node and
      documentRevisionConflict a stale one on a root-level add or cp; timeout is the budget
      spent, and every later call refuses the same way. An uncaught one prints its source,
      line, column and the source line, then the promise the transaction keeps:
      `nothing was written; <file> is byte for byte what it was.`

    A FAN-OUT: one copy per row, then the read that proves it
        // woodcase js batch.pen -F fan-out.js --as ana
        const rows = [
          { name: 'Chip Alpha', label: 'alpha' },
          { name: 'Chip Beta', label: 'beta' }
        ];
        for (const row of rows) {
          doc.cp('Component', 'Board', {
            props: { 'common.name': row.name, 'Label/kind.content': row.label }
          });
        }
        doc.tree('Board').filter(r => r.depth === 1).map(r => r.address)

    A MEASUREMENT: write, settle, and refuse to commit a design that overflows
        // woodcase js banking.pen -F measure.js --as ana
        doc.override('banking-home/transactions-section/t1/info/merchant', {
          content: 'Coffee at the corner shop'
        });
        const tall = doc.tree('banking-home/transactions-section')
          .filter(r => r.depth === 1 && r.rect.height > 64);
        if (tall.length) {
          throw new Error(`${tall.length} rows overflow: ${tall.map(r => r.address).join(', ')}`);
        }
        doc.tree('banking-home/transactions-section')
          .filter(r => r.depth === 1).map(r => r.rect.height)

    A CAUGHT CONFLICT: a rev read in an earlier command, re-read and retried
        // woodcase js batch.pen -F retry.js --as ana
        const pinned = '9c1b04e6f2a71d38';
        try {
          doc.set('Canvas/Title', { 'kind.content': 'Hello' }, { rev: pinned });
        } catch (error) {
          if (error.code !== 'revisionConflict') throw error;
          console.warn(`Canvas/Title moved since ${pinned} — re-reading and retrying`);
          doc.set('Canvas/Title', { 'kind.content': 'Hello' },
            { rev: doc.get('Canvas/Title').revision });
        }
        doc.get('Canvas/Title').node.content

    A ONE-LINE QUESTION: no file, no script, nothing written
        $ echo 'doc.lint().length' | woodcase js batch.pen -F -

    THE doc OBJECT
      Property paths are the prefixed vocabulary `set` takes — common.name, kind.content,
      null to clear one — except on override, which takes the raw .pen names an instance's
      descendants map holds. An address is an id, a name path, or a path stepping into an
      instance; a parent may be null, meaning the document root. Values arrive typed: an
      integer written here is stored as an integer, and a $name string stays a string.

      declare const doc: {
        /** The document's revision, live: it changes after every write. */
        readonly rev: string;

        /** One row per node under `address`, or the whole file — `tree --json`. */
        tree(address?: string | null, options?: TreeOptions): TreeRow[];
        /** One node as the file stores it, with its revision — `get --json`. */
        get(address: string, options?: GetOptions): NodeReport;
        /** What is wrong with the document as it stands now — `lint --json`. */
        lint(address?: string | null, options?: LintOptions): LintFinding[];
        /** Every property a node type takes, or the overview — `schema --json`. */
        schema(type?: string | null): Schema;

        set(address: string, props: Props, options?: RevOptions): WriteReport;
        add(parent: string | null, node: PenNode, options?: PlaceOptions): WriteReport;
        replace(address: string, node: PenNode, options?: RevOptions): WriteReport;
        cp(source: string, parent: string | null, options?: CpOptions): WriteReport;
        mv(address: string, parent: string | null, options?: PlaceOptions): WriteReport;
        rm(address: string, options?: RmOptions): WriteReport;
        override(address: string, props: RawProps, options?: OverrideOptions): WriteReport;

        vars: {
          set(name: string, variable: PenVariable): WriteReport;
          rm(name: string, options?: ForceOptions): WriteReport;
        };
        themes: {
          set(axis: string, options: string[]): WriteReport;
          rm(axis: string): WriteReport;
        };
        imports: {
          set(alias: string, path: string): WriteReport;
          rm(alias: string, options?: ForceOptions): WriteReport;
        };
      };

      interface TreeOptions { depth?: number; expand?: boolean; props?: string[]; theme?: Theme }
      interface GetOptions { expand?: boolean }
      interface LintOptions { exclude?: string[]; severity?: string; theme?: Theme }
      interface RevOptions { rev?: string }
      interface PlaceOptions { at?: number; rev?: string }
      interface CpOptions { at?: number; props?: Props; each?: Props[]; rev?: string }
      interface RmOptions { detach?: boolean; rev?: string }
      interface OverrideOptions { unset?: string[]; rev?: string }
      interface ForceOptions { force?: boolean }

      type Props = { [path: string]: any };     // common.name, kind.content, Child/kind.fill
      type RawProps = { [name: string]: any };  // content, not kind.content — override only
      type Theme = { [axis: string]: string };  // { mode: 'dark' }

      /** A settled tree row — what `tree --json` and `find --json` print. */
      interface TreeRow {
        id: string; address: string; rev: string; depth: number;
        type: string; name: string | null;
        rect: Rect | null; absRect: Rect | null;   // the parent's space, and the document's
        clip: 'none' | 'partial' | 'full';
        overflowAxes: ('horizontal' | 'vertical')[];
        isReusable: boolean; isInstance: boolean; isSlot: boolean; childCount: number;
        properties?: Props;     // only the paths the `props` option asked for
        props?: Props;          // the same bag under find's spelling — one guarded view
      }
      interface Rect { x: number; y: number; width: number; height: number }

      /** What every write answers with, `vars`, `themes` and `imports` included. */
      interface WriteReport {
        id?: string;              // absent for a variable, a theme axis, an alias
        path?: string;            // the name path, or the name that was written
        nodeRevision?: string;    // absent when the node no longer exists
        documentRevision?: string;
        created?: CreatedNode[];  // add, replace and cp: the subtree that came to be
        divergences?: Divergence[];
        node?: PenNode;           // the stored node, children stripped
      }
      interface CreatedNode { id: string; name?: string; children: CreatedNode[] }
      interface Divergence { kind: string; severity: 'divergence' | 'note'; target: string;
        requested: string; applied: string; note: string }
      interface NodeReport { revision: string; node: PenNode; props?: object[] }
      interface LintFinding { check: string; severity: string; message: string;
        nodeID?: string; path?: string }
      interface Schema { type?: string; summary?: string; properties?: object; [key: string]: any }
      type PenNode = { type: string; name?: string; children?: PenNode[]; [key: string]: any };
      type PenVariable = { type: 'boolean' | 'color' | 'number' | 'string'; value: any };

      /** Thrown by every member. `instanceof WoodcaseError` holds for all of them. */
      declare class WoodcaseError extends Error {
        code: string;
        candidates: { id: string; path: string }[];
      }

      The host's own codes are timeout, syntaxError, unknownMember, unknownOption,
      badArgument, synchronousOnly, unknownNodeType, sourceUnreadable, variableInUse,
      importInUse and scriptError. Every other is the editing layer's own case name,
      unchanged — addressNotFound, ambiguousAddress, revisionConflict,
      documentRevisionConflict, unknownProperty and the rest — so a script branches on the
      same word a --json report carries.

    SEE ALSO
      `woodcase help design` is what every verb assumes: layout, names, addresses,
      components, values and the read-write-verify loop. `woodcase find --help` is the
      read-only sibling, and `woodcase js --help` the flags: --guard, --dry-run, --timeout,
      --as, --json. A row is one value on both routes: r.props and r.properties read the
      same bag, and each refuses a path the `props` option did not ask for.
    """#
}
