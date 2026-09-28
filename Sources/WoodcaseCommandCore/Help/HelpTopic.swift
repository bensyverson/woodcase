//
//  HelpTopic.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// A subject `woodcase help` can explain: the things the verbs assume rather than
/// the things one verb does.
///
/// A verb's `--help` says what that verb takes. It cannot say why a frame with no
/// `layout` key lays its children out horizontally, or why an address may step into a
/// component instance — every verb assumes those, and repeating them thirteen times
/// would be worse than saying them once. That is what a topic is for, and why it stays
/// dense: an agent reads it before it reads anything else, and an agent given no skill
/// file has nowhere else to learn any of it. ``schema`` is the one exception, and earns
/// it — a caller asks for one type at a time, and what comes back is generated rather
/// than written.
///
/// Adding a topic is a case, a ``summary`` and a ``body``.
enum HelpTopic: String, CaseIterable, ExpressibleByArgument {
    /// How .pen documents are laid out, named, addressed and edited.
    case design

    /// Every node type, and every property each one takes.
    ///
    /// The only topic with a body it does not write: the vocabulary is generated from
    /// the decoders by ``SchemaHelp``, and `woodcase schema` is the same answer as a
    /// verb. A topic that took an argument would be a second grammar, so the type goes
    /// after the topic word and ``Help`` routes it.
    case schema

    /// Copy-pasteable command sequences for what an agent actually does with a file.
    ///
    /// The body lives in `HelpTopic+Recipes.swift`, not here, because `RecipesTests`
    /// extracts and runs every command in it — a file worth reading on its own.
    case recipes

    /// What `generate react` recognises: components, pages, roles, parameters, states.
    ///
    /// The body lives in `HelpTopic+Codegen.swift`, beside the recipes it is built like:
    /// `HelpCommandTests` runs every command in it, so a verb that changes shape breaks
    /// this topic's own test rather than teaching a command that no longer works.
    case codegen

    /// The contract a `woodcase js` program runs under, and the `.d.ts` of `doc`.
    ///
    /// The body lives in `HelpTopic+Js.swift`. Two tests keep it honest, for the reason
    /// its own doc comment gives: `JsTopicTests` runs every snippet in it against the
    /// fixture the snippet names, and `JsDeclarationTests` checks the declaration against
    /// the prelude's own member table in both directions.
    ///
    /// It shadows `woodcase help js` as a route to the verb's screen, which is the right
    /// trade: an agent asking for help with `js` wants the contract, and the flags are
    /// one `woodcase js --help` away.
    case js

    /// The one line the topic list shows beside the name.
    var summary: String {
        switch self {
        case .design: "how .pen documents lay out, what things are called, and how to address them"
        case .schema: "every node type, and the properties and value shapes each one takes"
        case .recipes: "copy-pasteable sequences for starting, building and rebuilding a screen"
        case .codegen: "what `generate react` and `generate swiftui` read, and the package swiftui writes"
        case .js: "the rules a `woodcase js` program runs under, and the `.d.ts` of `doc`"
        }
    }

    /// The topic itself.
    var body: String {
        switch self {
        case .design: Self.designTopic
        case .schema: (try? SchemaHelp.text(for: nil)) ?? ""
        case .recipes: Self.recipesTopic
        case .codegen: Self.codegenTopic
        case .js: Self.jsTopic
        }
    }

    // MARK: - The topics

    /// Everything a verb assumes about the format, and nothing one verb owns.
    ///
    /// The sections are ordered the way a build goes: how a document lays out, what
    /// things are called, how to address them, how a component works, what a value
    /// means, how to read one back, and the loop that ties the four steps together.
    /// It ends by naming the verb whose own `--help` carries each thing this leaves
    /// out, because the Quill run's agents stopped reading here and never found them.
    private static let designTopic = """
    FLEX FIRST
      A frame with no "layout" key lays its children out horizontally, in order. Only a root — a
      node the document holds directly — is placed by coordinates. So a node added to a laid-out
      parent takes no x or y: leave them off and let the parent place it. kind.width and
      kind.height each take a number, "fill_container", or "fit_content".

    ARTBOARDS DO NOT OVERLAP
      A root added or copied with neither x nor y lands \(PenRect.number(RootOverlap.margin)) points past the
      rightmost root, level with the topmost, so it cannot land on one. A root you place
      yourself goes where you say, even on top of another: the write succeeds but prints
      one `artboard-overlap` line (in "warnings" under --json), and `lint` reports the pair.

    NAMES
      Everything woodcase creates has to be named: an unnamed node cannot be addressed by path
      afterwards, so `add` and `replace` refuse a subtree containing one. Nodes woodcase did not
      create may be unnamed, and a read prints those as their id marker instead. Name a node for
      what it is — Title, Body, Footer, not "Masthead Top Row Title" — and keep it
      unique among its siblings. Siblings are the only scope that matters, and the only one
      `lint` checks: two same-named cousins cost one more segment and nothing else. An additive
      name buys nothing the path does not already carry, and you retype it on every write.

    IDS
      You never have to invent one: leave "id" out of an `add` subtree and it is
      generated for you. An id you do write is kept — handy when a script already knows
      what to call a node — as long as it has no "/" in it, is not already in the file,
      and is not repeated in the subtree; otherwise the line is refused. `replace` reads
      one the same way, keeps the target's id, parent and index, and frees the ids it
      swaps out for reuse. `cp` always draws fresh ids, so a copy cannot collide.

    ADDRESSES
      ALu8G                   an id
      Dashboard/Header/Title  a path of names, from any ancestor — not only from a root
      Orders/Value            a path stepping into a component instance
      #ALu8G                  an id, forced, when a name could be read as one
      @hero                   inside one `apply` batch: what an earlier line created
      @hero/Title             a tag, then a path down from it — the same steps as above
      document                where a parent is expected: the document root
      A path matching nothing is an error listing near misses; a path matching several
      is an error listing every candidate by its full path, and one more segment on the
      front of yours picks one out. Neither is ever a silent no-op.

    TWO PROPERTY VOCABULARIES
      set, cp   codec paths — common.name, kind.width, kind.fills. null clears one.
      override  raw .pen names — content, not kind.content — because that is what a
                component instance's descendants map holds in the file.
      Each verb points at the other when it is handed the other's target.

    COMPONENTS AND INSTANCES
      `set <node> common.reusable=true` makes a definition; the next `cp` of it is an
      instance — a `ref` — storing nothing but what it overrides. A ref can also be
      written inline in an `add` subtree, as {"type":"ref","ref":"<definition id>",
      "descendants":{…}} — so a whole board is one command, not a cp and an override
      per node.
        override Inst/Child key=val  a node inside the instance, in raw .pen names
        override Inst key=val        the instance itself: the component ROOT's own
                                     properties, as this instance shows them
        set Inst common.x=…          the ref node: where it sits, whether it draws
        override … --unset key       REMOVES an override; key=null does not — a null
                                     is stored, and clears the property where it draws
        get <definition> --instances every ref that draws it, with the rev to pin
      Overrides are keyed by the definition's child ids, never their names, so renaming a
      definition's children is free. `replace` on a live definition mints fresh ids, and every
      override whose id the replacement does not carry forward is dropped — no warning, no lint.
      Edit a definition in place instead: `set` a child, `add` or `cp` one in, `rm` one out.
      VARIANTS. `override Inst/Child enabled=false` takes that child out of this
      instance's layout and no other's. One superset definition plus one line per
      instance is the variant mechanism; there is no variant component to build.
      SLOTS. A frame with a "slot" key is a hole a definition leaves for its instances. Fill it
      with `override Inst/Slot children=[…]` — .pen subtrees, refs with their own overrides
      included. Give every injected node an "id": those are addresses —
      `get Inst/Note0` reads one, `override Inst/Note0 content=Hi` writes into the slot's
      children (Pen ignores a key naming one) — but the slot holds one value: add or remove a
      child by writing the whole children array again, and read it back with `tree --expand`.

    VALUES
      kind.lineHeight is a multiple of kind.fontSize, not a length: 1.4, not 21. It is the one
      number in the schema that is not points.
      A string that must hold a literal $ escapes it: '\\$120,000', and a \\$ anywhere else in
      the string loses its backslash the same way ('Total: \\$30' draws Total: $30). A bare $name
      is a variable reference. Text content forgives one that names no variable in the document,
      restoring the literal it probably was — whichever verb wrote it, `set kind.content=` and
      `override content=` alike — but a name the document DOES define substitutes, and stays a
      finding when nothing resolves it. In any other property a bare $name naming nothing stays
      a dangling reference, drawing nothing and reported by `lint` as unresolved-variable.
      A variable name that starts with a dash — every name in a design-token file — needs a
      bare -- before it, or the parser reads it as an option:
        woodcase vars set f.pen -- --accent=#e0561a

    READ BEFORE YOU RENDER
      woodcase get Inst --expand    the whole instance as it renders, in one read
      woodcase tree Card --props kind.content,common.name   properties as columns
      woodcase tree Card --absolute rects in document space
      woodcase shot Home --out h.png --json   every rect it drew, --outline targets too
      A rect is parent-relative — an offset inside its own parent — unless --absolute;
      --json carries rect and absRect both. Pass a vision model's own longest-edge limit
      as `shot --max`, read pixels=, and tile a board too tall for one look with
      `shot --crop x,y,w,h`; `shot --extent painted` frames strokes, shadows, overhangs.

    FONTS AND WIDTHS
      A family neither installed nor cached measures in SF Pro, and the read says so on
      stderr — every text width there is the fallback's. Fonts cache in $WOODCASE_HOME/fonts
      (~/.woodcase/fonts by default); reads never download, so `woodcase shot` once fills it.

    BATCHES, QUERIES AND PROGRAMS
      `apply` reads one JSON operation per line. A failed line is skipped, lines that
      depend on it are cascaded, every other line still applies, and one status line
      comes back per operation; --atomic opts into all-or-nothing. A line may tag what
      it creates ("tag":"hero") so later lines address it as @hero before an id exists.
      `woodcase apply --help` prints the grammar.
      `find` is a question: a JavaScript predicate over the rows `tree` prints, in tree's own
      format, exit 1 for no matches. `js` is a loop-shaped task: a program with a `doc` object
      whose members are these verbs, reading, deciding and writing inside one transaction, so
      it can measure what it just made and throw rather than commit. `woodcase help js` is that
      contract — the rules, the `.d.ts` of `doc`, and every sentence the host throws.

    PINNING WHAT YOU READ
      A node's `rev` — from `woodcase get`, or a --json tree row — covers everything that node
      renders: its whole subtree, and the definitions its instances draw. Quote it back as
      --rev <rev>, which fails the write if that node moved at all, or as --guard <rev> /
      --guard <node>=<rev> / --guard document=<rev>, which fails it only if someone ELSE moved
      what you read: guards are checked once, before line 0 of a batch runs, so a batch never
      trips its own. Both are opt-in and both exit 3. A guard fits a short structural batch
      whose premise you read a moment before, not a session-long lease: nothing renews one.
      Every write verb takes --dry-run: the same lock, guards, edit and settle, then the lint
      findings it would introduce, and nothing written — no revision, because none was made.

    THE LOOP: read, write, verify, attribute
      woodcase tree design.pen                       # addresses, and the revision
      woodcase set design.pen Card/Title kind.content=Hi --rev <rev> --as ana
      woodcase tree design.pen Card                  # the layout as it settled
      woodcase lint design.pen && woodcase shot design.pen Card --out card.png
      woodcase activity design.pen                   # who wrote what, in order
      A read settles the layout first, so what tree and lint report is what renders, and a
      write answers with the name → id tree of what it made, so the next command needs no
      lookup. `woodcase undo design.pen --as ana` reverses YOUR last command — all of it,
      however many rows it logged — and refuses when another writer has edited that node
      since; --all opts into crossing identities, --event steps one logged row at a time.
      Edit .pen files through woodcase and nothing else: a write that finds the file
      changed behind the log's back says so, records it, and cannot undo past it.
      When the next step is to run this loop again — write, read the settled rect, adjust,
      write again — that loop is a `js` program: one transaction that measures what it just
      wrote and throws rather than commit. `woodcase help js`.

    SEE ALSO
      This topic is what every verb assumes; what one verb does is on its own screen:
        override --help  the whole override contract  cp --help    --each rows.jsonl
        apply --help     the batch grammar and guards  shot --help  sizing and tiling
        replace --help   what a rebuild drops          lint --help  every check it runs
        add --help       subtrees, ids and placement   get --help   --expand, --instances
        vars set --help  several pairs, --theme, --type
      `woodcase schema <type>` prints every property a node type takes, and
      `woodcase help recipes` is the same ground as worked, runnable sequences.
      `woodcase help codegen` is what the emitters read; `woodcase help js` is `doc`.
      `woodcase lint --list` names every check, with no file; --summary counts them.
    """
}
