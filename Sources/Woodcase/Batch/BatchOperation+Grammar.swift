//
//  BatchOperation+Grammar.swift
//  Woodcase
//

import Foundation

public extension BatchOperation {
    /// The batch grammar, in the form a CLI prints for `apply --help` and `schema`.
    ///
    /// This is the single source of truth for the wire format: the DocC on each
    /// operation explains *why*, this says *what to type*. Anything that
    /// documents the grammar to a user should print this rather than restate it.
    static let grammar: String = """
    A batch is JSONL: one operation per line, applied in order. Blank lines are
    skipped. Nodes are named by address — an id (ALu8G), a name path from any
    ancestor (Dashboard/Header/Title), a path into a component instance
    (Orders/Value), or a batch tag (@hero) naming what an earlier line created.

      {"op":"set","target":ADDR,"props":{PATH:VALUE,…},"rev":REV,"guard":GUARD}
      {"op":"add","parent":ADDR,"node":SUBTREE,"at":N,"tag":NAME,"rev":REV}
      {"op":"replace","target":ADDR,"node":SUBTREE,"rev":REV}
      {"op":"cp","source":ADDR,"parent":ADDR,"at":N,"tag":NAME,"props":{…},"each":[{…}],"rev":REV}
      {"op":"mv","target":ADDR,"parent":ADDR,"at":N,"rev":REV}
      {"op":"rm","target":ADDR,"detach":BOOL,"rev":REV}
      {"op":"override","target":ADDR,"props":{NAME:VALUE,…},"unset":[NAME,…],"rev":REV}
      {"op":"var","name":NAME,"value":VARIABLE}
      {"op":"theme-axis","name":NAME,"options":[STRING,…]}
      {"op":"import","alias":ALIAS,"path":PATH}

    Every line takes "rev" and "guard"; only set shows both above, to keep the
    shapes readable.

    var, theme-axis and import each ADD or CHANGE what they name; none of them
    removes it. An optional payload would turn a dropped field into a silent
    delete, and a dropped variable or import breaks what refers to it without
    failing. Removal is `woodcase vars rm` and `woodcase imports rm`, which
    refuse while anything still references the name and take --force.

    A var's VARIABLE is what the .pen file stores: {"type":TYPE,"value":VALUE},
    where TYPE is boolean|color|number|string and VALUE is either one value or
    the themed list — one {"value":V,"theme":{AXIS:OPTION,…}} per option, plus an
    optional entry with no "theme" as the fallback. That is the whole token
    layer in one line per token:

      {"op":"var","name":"--accent","value":{"type":"color","value":[
        {"value":"#e0561a","theme":{"mode":"light"}},
        {"value":"#ff8a5c","theme":{"mode":"dark"}}]}}   (written on ONE line)

    A themed var registers what it pins, exactly as `vars set --theme` does: an
    axis the document lacks is created, an option an axis lacks is appended, so a
    var line never needs a theme-axis line before it. The line replaces the whole
    value — write every variant you want to keep. Merging one option into what is
    already there is `woodcase vars set <file> NAME=VALUE --theme AXIS=OPTION`.

    Fields
      parent    omit it, or write "document", to act on the document root — the
                same word the command line takes
      at        position among the parent's children; omit to append
      tag       labels the node this line creates, so later lines can say @tag
      detach    rm only: detach every instance before deleting a component
      unset     override only: keys to REMOVE, so the component's own value shows
                again. Not the same as writing null, which stores a null and
                clears the property while the override stays. A line may carry
                "props", "unset" or both; one with neither is refused.
      rev       the revision the caller last observed. It guards `target` where
                there is one, otherwise `parent` — or the whole document when
                there is no parent either. A stale rev fails that line and
                changes nothing.
      guard     a premise, checked once before line 0 runs. See below.

    Guards
      "guard" asserts that what you read has not been moved BY ANYONE ELSE. It
      takes the same revision "rev" takes, in one of three shapes:

        "guard":"REV"                      pins this line's own target
        "guard":{"node":ADDR,"rev":"REV"}  pins that node's whole subtree
        "guard":{"node":"document","rev":"REV"}   pins the whole file
        "guard":[GUARD,…]                  several premises on one line

      Every guard in the batch is checked ONCE, at transaction entry, before
      any line has run — so a batch never trips its own guards: line 30 may
      guard a frame that line 3 rewrote. That is the whole difference from
      "rev", which each line checks as it is applied.

      A moved premise refuses the WHOLE batch before a single line applies,
      with exit 3, naming the node, both revisions and who moved it. Guards are
      entry gates, not per-line statuses, so they never appear in the report.
      A guard cannot name @tag: nothing a line creates exists at entry.

    Properties come in two vocabularies, because the file format has two.
      set   props are NodePropertyCodec paths: "common.name", "kind.width",
            "kind.fills". null clears a property.
      cp    props are the same paths, applied to the copy, never to the source. A
            key written as a name path — "Header/Title/kind.content" — lands on
            that node INSIDE the copy, and becomes an override when the copy is a
            component instance, exactly as `woodcase cp` does on the command line.
      override
            props are raw .pen property names — "content", not "kind.content" —
            because that is what the format writes into an instance's descendants map.
            A target that names the INSTANCE ITSELF, with no path after it, writes
            the component ROOT's properties as that instance shows them; "set" on
            the same address still writes the ref node's own.

    Creating nodes
      add    the subtree is .pen JSON. Ids are optional: one you write is kept,
             one you leave out is generated. A supplied id must have no "/" in
             it, must not already be in the document, and must not appear twice
             in the subtree — otherwise the line is refused and changes nothing.
             Every node must have a "name": an unnamed node cannot be addressed
             by path, and the line is refused.
      replace
             swaps the target's whole subtree for this one, keeping the target's
             id, its parent and its index among its siblings. Ids follow the add
             rule, with one addition: an id the replaced subtree holds today is
             free to reuse, because it goes away with it. The subtree's own root
             id, if written, must be the target's — it is kept either way, and a
             different one is refused. Changing the root type of a reusable
             definition that instances point at is refused.
      cp     copying a reusable component makes a ref to it, as Pen does.
             Copying anything else deep-copies it with fresh ids — always fresh,
             since a copy must not collide with its source. A ref inside the
             copy follows it; one pointing outside still points outside. A
             copied subtree is not required to be named — the source may be a
             file we did not write.
             "each" makes one copy PER ROW instead of one copy: each row is a
             props object of its own, laid over "props", with {n} replaced by the
             1-based row number in every value it appears in. "at" walks with the
             rows, "rev" guards the first copy only, and a row key naming nothing
             inside the source refuses the whole line before anything is written.
             A line with "each" takes no "tag": a tag names one node.
             It is `woodcase cp --each rows.jsonl`, inline.

    Placement
      A root-level add or cp whose node declares neither x nor y is placed in
      empty space to the right of the existing roots. A node added to a
      laid-out parent takes no coordinates: leave x and y off and let the
      parent's layout place it.

    Results
      One report line per operation: applied, failed, or cascaded. A failed line
      changes nothing and does not stop the batch; a line that depends on a
      failed one — by tag, or by addressing what it would have created — is
      cascaded rather than attempted. --atomic discards everything on the first
      failure. Retrying re-runs only the failed and cascaded lines.

      An applied line that stored something other than what it said carries a
      divergence sentence indented underneath it — a value resolved as a
      variable, a number stored as text, an override of a property the
      definition does not set, a placement or a detachment the line implied. A
      themed var line carries a `note` instead, echoing every option's value and
      any axis it grew, since its own status line says only `document`.
      --json carries them per line as `divergences`, with the post-state `node`.
    """
}
