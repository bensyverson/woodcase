# Component Loops

Components that contain each other are a design error: an edit that would make one is
refused, and a file that already holds one reads with that nesting ignored.

## Overview

A **component loop** is a set of components that render each other: `Card` holds an
instance of `Badge` and `Badge` holds one of `Card`, or `Row` holds an instance of
itself — through any chain, a repointed nested `ref` and an instance written as slot
content included. Drawn faithfully, a loop never ends. Ben ruled on 2026-10-05 that a
loop is a design error, so Woodcase does three things with one:

- **Writes refuse it.** Every operation that could close a loop — ``EditOperation/insertNode(_:)``,
  ``EditOperation/moveNode(_:)``, ``EditOperation/replaceSubtree(_:)``, a property patch or
  retype that sets a `ref` or `reusable`, a descendant or root override whose value names a
  component — throws ``EditingError/wouldCloseComponentLoop(path:)`` before it writes,
  naming the loop as component ids in render order: `["Badge", "Card", "Badge"]`. Batches,
  scripts and every CLI verb go through the same guard; the CLI exits non-zero, saying
  `this would make components contain each other: Badge (CmpB1) → Card (CmpA1) → Badge (CmpB1)`.
- **Reads ignore its nesting.** A file that arrives with a loop still opens. A `ref` is
  not expanded when its component, or any member of its component's loop, is already on
  the expansion chain, so no member of a loop is ever expanded inside another member.
- **Reads say so.** ``EditableDocument/componentLoops`` lists the loops a document holds;
  a read through ``PenFileTransaction`` records them on ``PenReadContext/componentLoops``
  — what an editor shows on open. The library prints nothing; the `woodcase` CLI writes
  one `woodcase: error:` line per loop to standard error, once per file per command, from
  that read context, so every verb that reads the file says it. `woodcase lint` reports
  each loop as a `component-loop` error.

## The graph

Each component is a vertex, with an edge to every component an instance anywhere in its
subtree renders: the `ref` it names, and every `ref` its
`descendants` and root overrides write, at any depth. A loop is a group of that graph's
vertices that all reach each other (a strongly connected component), or one vertex that
reaches itself. ``ComponentLoop`` reports one: its ``ComponentLoop/members`` — id and
display name — start with a cycle in render order from the member with the lowest id,
then any other member of a tangled group.

## The expansion rule

The older rule was "not a component already on the chain". It stopped a loop, but it let
a group of tangled components expand along every path through it: a chain of 223
components each holding the next two drew a Fibonacci number of nodes, and fuzz seeds
12456 and 13964 detached and overrode instances whose expansions held 12 million and
80 thousand nodes. The rule now is that the chain holds each loop at most once. It reads
only the document, never the place the expansion started, and every walk that has to agree
with the expansion asks the same question — ``PenRefExpander``, the override-key
resolver, the descendant keys, ``TreeView``'s instance rows, the address resolver and
``EditableDocument/componentPlacement(of:onChain:)``.

A definition drawn where it is written — a reusable root on the canvas — counts as its
component entered, so its loop stops at once there, exactly as in its instances.

## The write guard

The guard reads the graph as the edit would leave it, through an overlay of the flat
store, and refuses the edit when a component it writes into gains a component that renders
it back. It runs only for an edit that places an instance, a component, or override
content naming one; a nudge or a rename never reads the graph. An edge between two
members of a loop the document already holds closes nothing new, so a file that arrived
with a loop takes every other edit, its fix, and a detach inside the loop — which turns
`Card → Badge → Card` into `Card → Card`.

Replaying history is the one exception: a ``DocumentSession`` undo, redo or rollback
returns to a state the document held, so it runs with the guard off, and undoing a loop's
fix puts the loop back. A merge's operations run the same way (<doc:MergingDocuments>):
the merge checks its result as a whole.

## Merges

A three-way merge whose two sides together would close a loop keeps the local side and
leaves the external change out, reporting it as
``MergeConflict/Kind/wouldCloseComponentLoop``. The rule and its subjects are in
<doc:MergingDocuments>.

## Revisions

A component in a loop has the revision of its group, defined once and memoized — see
<doc:EditingDocuments>.

## Topics

### Loops

- ``ComponentLoop``
- ``EditableDocument/componentLoops``
- ``EditableDocument/recordComponentLoopsOnRead()``
- ``PenReadContext/componentLoops``

### Refusals and reports

- ``EditingError/wouldCloseComponentLoop(path:)``
- ``MergeConflict/Kind/wouldCloseComponentLoop``
- ``LintCheck/componentLoop``
