# Bundles

Keep a document with its images, fonts and history in one `.umbra` directory.

## Overview

A **bundle** is a directory that holds one document and everything it uses:

```
Design.umbra/                    a directory; a package on macOS (one icon in Finder)
├── document.pen                 a plain .pen file, paths relative to this folder
├── images/                      image fills: "./images/hero.png"
├── fonts/                       declared fonts: "./fonts/Inter[wght].ttf"
├── converted-from.json          only in a bundle made from a bare .pen
└── .woodcase/
    ├── activity.jsonl           this document's activity log
    └── (temporary files)
```

Woodcase works on **both** a bundle and a bare `.pen`, and never requires a bundle. Pen
files, fixtures and agents' bare files work exactly as they always have. Prefer a
bundle for a new document: copy or send it and its images, fonts and history go with it.
The design is in `project/2026-10-05-pen-bundle-format.md`.

The inner file is always `document.pen`, because the bundle may be renamed at any time.
Its relative paths resolve against the bundle, the way a bare file's resolve against its
folder — so copying the bundle's contents into any folder gives Pen, or any `.pen` tool,
a document whose images and fonts are all in place.

## One rule for every path

``PenLocation`` turns whatever path someone named into the document to open:

```swift
let location = PenLocation(URL(fileURLWithPath: "Design.umbra"))
location.document            // Design.umbra/document.pen — read and written
location.resourceDirectory   // Design.umbra — relative paths resolve here
location.stateDirectory      // Design.umbra/.woodcase — log and temporary files
location.containingDirectory // the folder holding Design.umbra — renders go here
```

The answer comes from the path alone: a path ending in `.umbra` is a bundle, and so is
the `document.pen` directly inside one, so naming either reaches the same document. Any
other path is a bare file and comes back exactly as given.

Everything that takes a document's path resolves it there:
``PenParser/parse(contentsOf:diagnostics:)``, every ``PenFileTransaction`` entry point —
`run`, `read`, `create`, `save`, `migrate` — ``ActivityLogLocation``,
``ActivityEvent/canonicalPath(for:)``, ``FileWatcher``, imports (`"../Kit.umbra"` reads
that bundle's document), and every CLI verb. So `woodcase tree Design.umbra`,
`PenFileTransaction.save(_:changes:to:log:timeout:)` with a bundle URL, and
`DocumentSession(file: bundleURL)` all just work.

- **Writes** stage their temporary file in the bundle's `.woodcase/`, never beside
  `document.pen`, then rename it into place.
- **The lock** is the same `flock(2)` on the `.pen` file a bare file uses — here
  `document.pen` — so a bundle and a bare file are locked the same way.
- **Creating** a bundle — `PenFileTransaction.create(at: "Design.umbra", …)`, which is
  `woodcase new Design.umbra` — makes the directory and its `document.pen`, and records
  `new` in the bundle's own log.

## The log lives in the bundle

A bundle's activity log is `Design.umbra/.woodcase/activity.jsonl`
(``ActivityLog/Origin/bundle(root:repository:)``), wherever the bundle sits — in a
repository or not — and whatever `$WOODCASE_HOME` says: the history is part of the
document. A bundle inside a repository still adds `.woodcase/` to that repository's
`.gitignore` on its first write, so the log stays out of Git, as every log does.

Every row in a bundle's log is about its one document, so a reader asking about that
document takes every row, whatever path it was written under
(``ActivityLog/Origin/holdsOneDocument``). Rename or move the bundle and its history,
`woodcase undo` and `woodcase activity` all carry on. Rows name a bundle by its
`document.pen`.

## Converting

- `woodcase bundle Design.pen` — ``PenBundle/convert(_:identity:)`` — converts in place:
  `Design.umbra/document.pen`, with every local image fill and declared font copied into
  `images/` and `fonts/` and its reference rewritten. A file already under the folder's
  `images/` or `fonts/` keeps its relative path; any other is copied in under its own
  name, numbered when two share one. The original is removed (Git sees a rename), the
  bundle's log starts with a `new` row, and the original's history stays in its old log.
- `woodcase unbundle Design.umbra` — ``PenBundle/export(_:to:identity:)`` — copies the
  document out into a plain folder, `Design/` beside the bundle by default: `Design.pen`
  with `images/` and `fonts/`, every reference relative to it, including any the bundle
  reached outside itself for. The bundle is left as it is; nothing is overwritten.
- `woodcase embed Design.umbra`, or `bundle --embed` —
  ``PenBundle/embed(_:identity:fetcher:fonts:)`` — downloads every remote image fill and
  remote declared font into the bundle, and copies the Google Fonts file of every face
  the document draws into `fonts/`, declaring it in the root `fonts` array. The bundle
  then renders offline and the same everywhere. **It is explicit only**: nothing embeds
  on its own. The rewrite is one logged change (`replace` rows and a `set` row for
  `fonts`), so `woodcase undo` takes it back.

## Two sources of truth

A bundle made from a bare file records it in `converted-from.json`
(``PenBundle/ConvertedFrom``): the original's path, relative to the folder holding the
bundle, its document revision and the date. It sits at the bundle's root, not in
`.woodcase/`, so it is committed and a collaborator is warned too. Any CLI command run
on a bare `.pen` that a bundle beside it was converted from warns on standard error:

```text
woodcase: Design.pen was converted to Design.umbra on 2026-10-05; edit that instead.
```

When the original's document has changed since, the warning adds that those changes are
not in the bundle.

## Topics

### Locations

- ``PenLocation``

### Converting

- ``PenBundle``
- ``PenBundle/ConvertedFrom``
- ``PenBundleError``
