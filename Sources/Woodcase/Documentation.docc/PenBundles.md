# Bundles

Keep a document with its images, fonts and history in one `.umbra` directory.

## Overview

A **bundle** is a directory that holds one document and everything it uses:

```
Design.umbra/                    a directory; a package on macOS (one icon in Finder)
├── document.pen                 a plain .pen file, paths relative to this folder
├── images/                      image fills: "./images/5280ed5c223e2c4a.png"
├── fonts/                       declared fonts: "./fonts/Inter[wght].ttf"
├── converted-from.json          only in a bundle made from a bare .pen
├── history/                     the shared history: one log per writer, committed
│   ├── ben@grace.jsonl
│   └── claude@grace.jsonl
├── .gitignore                   ".woodcase/" — keeps the local state below out of Git
└── .woodcase/                   local state, never committed
    ├── views.jsonl              who read what, on this machine
    ├── cursors/                 the change feed's last looks
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
location.historyDirectory    // Design.umbra/history — the shared history
location.stateDirectory      // Design.umbra/.woodcase — local state and temporary files
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
  `new` in the bundle's own history.

## The history lives in the bundle

A bundle's history is `Design.umbra/history/`: one append-only file per writer —
`ben@grace.jsonl`, `claude@grace.jsonl` — where a writer (``HistoryWriter``) is an
identity on one device (``ActivityLog/Layout/perWriter``). It is there wherever the
bundle sits — in a repository or not — and whatever `$WOODCASE_HOME` says: the history is
part of the document, and **meant to be shared**. Commit it with the document, and sync it
through Dropbox or iCloud; each writer appends only to its own file, so neither a Git
merge nor a sync service ever sees two writers' lines in one file. Every reader —
`woodcase activity`, `undo`, `changes`, `serve`, ``PenFileFollower`` — merges the files by
time. The bundle never adds anything to the repository's `.gitignore`; its own
`.gitignore`, inside it, keeps its `.woodcase/` — views, cursors, temporary files — out of
Git.

Every row in a bundle's history is about its one document, so rows carry no path: a
reader names the document as it is now. Rename or move the bundle and its history,
`woodcase undo` and `woodcase activity` all carry on. A change the history cannot account
for — another editor saving `document.pen`, a hand edit, a Git merge of two branches' documents —
shows as a seam: the next writer records an `external` row from the last recorded
revision to the one it found. The details, and the wire format, are in
<doc:WoodcaseActivityLog>.

Because the history is shared, editing a bundle's `document.pen` by hand is discouraged
(Ben, 2026-10-23): it works, and leaves a seam rather than a record.

## Converting

- `woodcase bundle Design.pen` — ``PenBundle/convert(_:identity:)`` — converts in place:
  `Design.umbra/document.pen`, with every local image fill and declared font copied into
  `images/` and `fonts/` and its reference rewritten. A file already under the folder's
  `images/` or `fonts/` keeps its relative path; any other is copied in under its own
  name, numbered when two share one. The original is removed (Git sees a rename), the
  bundle's history starts with a `new` row, and the original's history stays in its old
  log.
- An app's Convert… — ``PenBundle/convert(_:to:identity:)`` — makes the same bundle
  wherever the user chose in a save panel and **keeps the original**. The original is
  only read, under a shared lock, and `converted-from.json` names it relative to the
  bundle's folder (`../project/Design.pen` one folder over). A file the process may not
  read — a sandboxed app without a grant for the original's folder — is left as it was
  and reported in ``PenBundle/Report/missing``, as a missing one is; an app asks first
  for the folders of the files ``PenBundle/localAssets(of:)`` lists that it cannot read.
- `woodcase unbundle Design.umbra` — ``PenBundle/export(_:to:identity:)`` — copies the
  document out into a plain folder, `Design/` beside the bundle by default: `Design.pen`
  with `images/` and `fonts/`, every reference relative to it, including any the bundle
  reached outside itself for — except a declared font file Apple made, which is neither
  copied nor declared (see below). The bundle is left as it is; nothing is overwritten.
- `woodcase embed Design.umbra`, or `bundle --embed` —
  ``PenBundle/embed(_:identity:fetcher:fonts:)`` — downloads every remote image fill and
  remote declared font into the bundle — each image under its content hash, as an added
  image is (below), so two addresses serving the same bytes share one file — and copies the Google Fonts file of every face
  the document draws into `fonts/`, declaring it in the root `fonts` array. The bundle
  then renders offline and the same everywhere. **It is explicit only**: nothing embeds
  on its own. The rewrite is one logged change (`replace` rows and a `set` row for
  `fonts`), so `woodcase undo` takes it back.

## Fonts in a Pen Folder

``PenBundle/export(_:to:identity:)`` carries the fonts the document already declares. An
app's Export ▸ Pen Folder can carry more: the fonts installed on this Mac that the
document draws, which Pen would otherwise silently replace. Which ones is the
designer's call, since the license is theirs to read, so Woodcase plans and the app asks:

1. ``PenBundle/exportFontPlan(_:fonts:)`` (or ``PenFolderFontPlan/make(for:relativeTo:fonts:)``
   for a document in memory) lists every family the document's text draws — instances
   expanded, rich-text runs included, every theme combination resolved — as a
   ``PenFolderFontPlan/Family`` with its ``PenFolderFontPlan/Source``: declared, the
   system's, Google Fonts', installed, or missing. Where a font's file is does not
   settle whether it is Apple's: SF Pro, SF Mono and New York installed from Apple's
   developer downloads live in `/Library/Fonts`, beside anyone's fonts, and judged by
   location alone they were offered as installed, bundleable and checked. A family is
   the system's when its file is under `/System/` (which holds
   `/System/Library/Fonts` and the downloadable fonts in `AssetsV2`) or
   `/Library/Apple/`, **or** when Apple made the font, wherever it is installed or
   declared. Who made it is read from the font itself (``PenFontMaker``): an OS/2
   vendor ID of `APPL`, or a manufacturer (name ID 8) or copyright (name ID 0) naming
   Apple Inc. or Apple Computer — never a list of family names, and never `fsType`:
   SF Pro, New York and Helvetica read 0 (installable), yet Apple's license forbids
   passing them on. Woodcase's default family, SF Pro, is the system's on a stock Mac
   too: without Apple's developer download there is no SF Pro family to find, and
   Woodcase draws it as the system UI font — the same design — rather than as a
   stand-in, so it is never listed as missing. Any *other* family this Mac lacks draws
   in the system font as a substitute, and is missing.
2. Each row says whether it ``PenFolderFontPlan/Family/startsChecked`` and why not, as a
   typed ``PenFolderFontPlan/Reason`` the app words: system fonts and Google Fonts (which
   Pen downloads by name) are unchecked and disabled; every other row with a file starts
   checked, and one whose ``PenFontEmbedding`` is restricted (2), preview-and-print (4) or
   unreadable is flagged rather than left out (Ben, 2026-10-15). Each
   ``PenFolderFontPlan/FontFile`` carries the font's own license from its name table
   (ID 13 and 14), when it has one, for the designer to consult.
3. ``PenBundle/export(_:to:identity:fontPlan:bundling:)`` takes the families left checked.
   Each installed one is declared file by file in the root `fonts` array under the
   font's **real family name** — Woodcase draws a declared file only under that name,
   though Pen accepts any — with its style and weight (`[min, max]` for a variable
   file); an unchecked declared one is left out. Then every local declared font is
   copied into `fonts/` and its url rewritten relative to the exported `.pen`
   (`./fonts/Brand-Bold.ttf`), as images are — Pen copies no font file and keeps a
   relative url as written, so anything else breaks there.

Apple's fonts are never bundled, wherever they are installed (Ben, 2026-10-15), and that
holds with or without a plan: ``PenBundle/export(_:to:identity:)`` — which an app falls
back to when it cannot plan — reads every local declared font file and leaves out the
declaration of one Apple made, so a document declaring `/Library/Fonts/SF-Pro.ttf`
exports without it. A declaration at a web address is kept as written.

The research and both rulings are in Penumbra's
`project/2026-10-15-bundling-fonts-in-pen-folders.md`.

## Adding an image

A dropped or pasted image is stored **by its content**, so the same image added twice is
one file that every fill showing it references (Ben, 2026-10-13):

```swift
let dropped = try PenBundle.storeImage(contentsOf: fileURL, in: bundle)    // a Finder drop
let pasted = try PenBundle.storeImage(pngData, fileExtension: "png", in: bundle) // a paste
// The same bytes: both "./images/5280ed5c223e2c4a.png", one file on disk.
```

- **The name** is ``PenBundle/imageFileName(for:fileExtension:)``: the first 16 hex digits
  of the bytes' SHA-256 (``PenBundle/imageHashLength``, 64 bits) and the extension their
  signature names — `png`, `jpg`, `gif`, `webp` — whatever the file was called; bytes no
  signature names keep their own extension (`svg`), or take `img`. At 64 bits two
  different images in one bundle collide with odds of about n² / 2⁶⁵, one in 3.7 × 10¹¹ for
  ten thousand images.
- **Reuse is checked byte for byte.** A file already at that name is reused only when it
  holds exactly these bytes; one that differs (that collision, or a file someone edited)
  is never overwritten, and the bytes go to the first of `<hash>-2.png`, `<hash>-3.png`…
  that holds them or is free.
- **No half-written image.** The bytes are written in the bundle's `.woodcase/` and
  hard-linked into `images/`, which fails rather than replaces when another writer got
  there first, so two processes adding one image end with one file.
- **A file already inside the bundle** is not copied: its own path comes back.
- **Pen reads it as it reads any image.** The reference is an ordinary relative path,
  `./images/<hash>.png`, inside a plain `document.pen`; nothing about the format changes,
  and nothing reads meaning into the name. Pen, `woodcase unbundle`'s Pen folder and every
  other `.pen` tool open it exactly as they open `./images/hero.png`.

A remote image ``PenBundle/embed(_:identity:fetcher:fonts:)`` downloads goes through the
same store. ``PenBundle/convert(_:identity:)`` and ``PenBundle/export(_:to:identity:)``
keep the names a document's files already have.

## Adding a font

``PenBundle/importAsset(_:as:into:)`` copies one file into the bundle's `fonts/` — an
installed font — under its own name, numbered (`Mono-2.ttf`) when the name is taken, and
returns the reference to write: `./fonts/Mono.ttf`. A file already inside the bundle is
not copied. Bytes with no file go through ``PenBundle/importAsset(_:named:as:into:)``.
Both still take `.image`, and then store under the file's own name; an app adding an
image calls ``PenBundle/storeImage(contentsOf:in:)`` instead.

## Two sources of truth

A bundle made from a bare file records it in `converted-from.json`
(``PenBundle/ConvertedFrom``): the original's path, relative to the folder holding the
bundle, its document revision and the date. It sits at the bundle's root, not in
`.woodcase/`, so it is committed and a collaborator is warned too. Any CLI command run
on a bare `.pen` that a bundle beside it was converted from warns on standard error (a
bundle converted into another folder is not found from the original, so it does not
warn):

```text
woodcase: Design.pen was converted to Design.umbra on 2026-10-05; edit that instead.
```

When the original's document has changed since, the warning adds that those changes are
not in the bundle.

## Topics

### Locations

- ``PenLocation``
- ``HistoryWriter``

### Adding files

- ``PenBundle/storeImage(_:fileExtension:in:)``
- ``PenBundle/storeImage(contentsOf:in:)``
- ``PenBundle/imageFileName(for:fileExtension:)``
- ``PenBundle/imageHashLength``
- ``PenBundle/importAsset(_:as:into:)``
- ``PenBundle/importAsset(_:named:as:into:)``

### Converting

- ``PenBundle``
- ``PenBundle/AssetKind``
- ``PenBundle/ConvertedFrom``
- ``PenBundleError``

### Fonts in a Pen Folder

- ``PenFolderFontPlan``
- ``PenFontEmbedding``
- ``PenFontMaker``
