# Import Namespaces

How Woodcase namespaces imported library components to prevent identifier collisions.

## Overview

When a `.pen` document imports a component library, every identifier in the library is prefixed with the import alias to create a separate namespace. This prevents collisions when the host document and library contain components with the same ID, and ensures that library components reference each other correctly regardless of what the host document contains.

For a library imported with alias `V`, the prefixing creates two namespaces in the merged document:

| Namespace | Example ID | Source |
|-----------|-----------|--------|
| Local | `AstK1` | Host document |
| Library | `V:AstK1` | Imported library |

These are treated as **distinct components** — even if they share the same base ID, the local and library versions may have diverged.

## Where the libraries come from

A document names its libraries itself: `"imports": {"V": "kit.lib.pen"}`. Every read
of a file — `tree`, `lint`, `get`, `shot`, `render`, `generate`, the viewer, a `js`
script, and each write's preview — loads them once, as ``PenFileTransaction`` parses
the file, with ``PenLibraries/load(importedBy:at:)``. There is no flag to add or
override one. The rules are Pen's, established with its own CLI
(`project/2026-09-26-pen-import-resolution.md`):

| Import path | Where it is read from |
|---|---|
| `kit.lib.pen`, `./kit.lib.pen`, `../shared/icons.pen` | Relative to the importing document's own folder. Nowhere else is tried — not the working directory, not a libraries folder |
| `/abs/path/kit.lib.pen`, `file:///…/kit.lib.pen` | As it stands |
| ``PenLibraries/bundledScheme``, then `:shadcn.lib.pen` | A library bundled with Pen, which Pen reads from its own install. Woodcase does not ship Pen's libraries, so this is never read — not even from beside the document |
| `https://…` | Never fetched |

Resolution is **one level deep**, as in Pen: a library's own `imports` are not
followed, so a component of the library that reaches through one draws nothing in
either tool, and a cycle cannot occur. A document may import itself; it is then its own
library, once.

Nothing here fails a read. Each import that brought nothing in is a
``PenImportProblem`` on the document's ``PenReadContext``: `lint` reports it
(`import-not-found`, `import-unreadable`, `import-not-followed` — see <doc:WoodcaseLint>),
`shot` and `render` print it as a warning (and `render --strict` fails on it), and every
instance through that alias draws nothing, exactly as in Pen.

## Read context, not document

The loaded libraries ride on ``EditableDocument/readContext`` and are never written
back: ``EditableDocument/materialize()`` produces the file's own bytes, `imports`
table included, and nothing from a library. Every reader expands through
``EditableDocument/expanded(for:)``, which hands the imported components to
``PenRefExpander`` as extra registry entries (``PenImportedDefinitions``) and merges
their variables and theme axes into the document — so an instance of `V:Button`
expands, and `V:Button` itself never becomes an artboard of the importing document.
The walks that follow an instance into its component — override keys, name paths,
addresses such as `screen/card/badge/label`, `tree --expand` — step into imported
components the same way. Editing an import (`woodcase imports set`) repoints the alias;
a newly named library is read on the next command, not mid-transaction.

Code generation wants the other shape: ``PenImportResolver/resolve(_:libraries:)`` merges
each imported component into the tree as a root, so it becomes code beside the file's
own. ``EditableDocument/materializeForGeneration()`` is that merge over the read
context's libraries, and both of its readers call it — `generate` and the viewer's code
panel — so the panel shows exactly the code the verb writes.

## What Gets Prefixed

``PenImportResolver`` delegates prefixing to `PenImportPrefixer`, which transforms every identifier within extracted library nodes:

| Identifier type | Before | After |
|----------------|--------|-------|
| Node IDs | `"btnBase"` | `"V:btnBase"` |
| Ref targets | `"ref": "icon1"` | `"ref": "V:icon1"` |
| Variable references | `"$accent"` | `"$V:accent"` |
| Theme axis names | `"scheme"` | `"V:scheme"` |
| Descendant override keys | `"header"` | `"V:header"` |
| Fill/stroke variable refs | `"fill": "$paper"` | `"fill": "$V:paper"` |

## Descendant Override Values

Ref nodes can carry **descendant overrides** — property patches or full node replacements applied to descendants of the referenced component. These overrides have **keys** (which descendant to patch) and **values** (what to patch it with).

Both keys and values are prefixed. This matters because override values can contain **entire node trees**, and those trees can themselves carry further overrides. For example, a library component might override a descendant's children with a new ref node that carries its own descendant override:

```json
{
  "ref": "UaaFD",
  "descendants": {
    "pPeGt": {
      "children": [
        { "id": "Y2hF6", "type": "ref", "ref": "rKzoF",
          "descendants": { "EpasF": { "content": "+8%" } } }
      ]
    }
  }
}
```

After prefixing, every identifier in the override value is namespaced — including the
nested `descendants` dictionary one level down:

```json
{
  "ref": "V:UaaFD",
  "descendants": {
    "V:pPeGt": {
      "children": [
        { "id": "V:Y2hF6", "type": "ref", "ref": "V:rKzoF",
          "descendants": { "V:EpasF": { "content": "+8%" } } }
      ]
    }
  }
}
```

The prefixer recursively walks override values, handling:
- `"ref"` strings (component reference targets)
- `"id"` strings (node identifiers)
- `"children"` arrays (recurse into each child node)
- `"descendants"` dictionaries (prefix keys and recurse into values)
- `$`-prefixed strings (variable references)

## How It Interacts with Ref Expansion

After import resolution, ``PenRefExpander`` builds a registry of all reusable components. The registry contains both local and library components:

```
Registry:
  "AstK1"    → local version of the component
  "V:AstK1"  → library version of the component
```

When expanding a ref:
- A **local** ref with target `"AstK1"` resolves to the local component.
- A **library** ref with target `"V:AstK1"` resolves to the library component.

Because all identifiers within library nodes are consistently prefixed, library components form a self-contained namespace — they reference each other via `V:`-prefixed IDs without any awareness of the host document's local components.

## Coexistence of Local and Library Versions

A document can contain both a local component and an imported version of the same component. This is common when a document's local component artboard contains components that were originally derived from the library but have since been customized.

The two versions are fully independent:
- Local refs resolve to the local version
- Library refs resolve to the library version
- Editing one does not affect the other

This enables a workflow where you import a design system, customize some components locally, and continue receiving updates to the library's versions without overwriting your local changes.

## Editing the import table

`woodcase imports <file>` lists the aliases a document declares, with the number of
nodes that reach into each namespace; `woodcase imports set <file> <alias> <path>` adds
one or repoints it, and `woodcase imports rm <file> <alias>` drops it — refused, by
``NameInUse``, while any `ref`, override key or `$alias:` binding still needs it, since
a stranded reference resolves to nothing rather than failing. A batch writes the same
add-or-repoint as `{"op":"import","alias":ALIAS,"path":PATH}`; there is no removal line,
for the reason there is none for a variable.

## Topics

### Pipeline Stages

- ``PenImportResolver``
- ``PenRefExpander``

### Reading the libraries

- ``PenLibraries``
- ``PenImportProblem``
- ``PenImportedDefinitions``
- ``PenReadContext``
