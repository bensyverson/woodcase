# 2026-10-05 — A bundle format for .pen documents

**Status: decided 2026-10-05 (Ben), including imports across bundles (below).** Woodcase owns the format and the CLI; Penumbra adopts it. This closes the "Open Decision: Bundle Format" in Penumbra's [April vision](../../Penumbra/project/2026-04-02-penumbra-vision.md), §10.

## Why now

Two problems showed up at once, and a bundle solves both.

- **Saving got fragile in the App Sandbox.** The activity log lives at `<repo>/.woodcase/activity.jsonl`, or in the file's folder outside a repository (`ActivityLogLocation`). Penumbra's save also writes a temporary file beside the document. A sandboxed app is granted only the file the user opened, so Penumbra has to ask for the repository root, a folder the user never chose (Penumbra leaf QnusK6, `ffa218f`). A Release build may also hide `.git` from the sandbox, so the log would land in the wrong place; that is unverified.
- **Assets don't travel.** Image fills and declared fonts are paths relative to the `.pen` file. Copy or send the `.pen` alone and they break, and so does its history: the log stays behind.

## The principle: Woodcase works on both

**Bare `.pen` stays first-class.** Pen.app files, agents creating files with the CLI, Linux, and every existing fixture and test work exactly as today. **The bundle is a container Woodcase also understands.** Given a bundle path, every read, write, log and lock goes to the `.pen` inside it. Woodcase never requires a bundle, and never converts a file unless asked.

This works because the format already resolves everything relative to the `.pen` file's own folder: image fills (`"./images/hero.png"`, DocC `PenRemoteImages.md`), declared fonts (the root `fonts` array, `PenGoogleFonts.md` ▸ Declared fonts) and imports (`PenImportNamespaces.md`). A bundle is that folder, made into a package.

## Layout

```
Design.umbra/                    a directory; a package on macOS (one icon in Finder)
├── document.pen                 a plain .pen file, paths relative to this folder
├── images/                      image fills: "./images/hero.png"
├── fonts/                       declared fonts: "./fonts/Inter[wght].ttf"
└── .woodcase/
    ├── activity.jsonl           this document's activity log
    └── (lock and temporary files)
```

- **Compatibility is structural.** Copy the bundle's contents into a folder and Pen.app, or any .pen tool, opens `document.pen` with every image and font in place. Penumbra's File ▸ Export ▸ Pen Folder does exactly that.
- **The log lives in the bundle**, so history travels with the document. A bundle inside a repository uses its own log, not the repository's.
- **Git:** `document.pen` stays diffable, and assets are ordinary files (LFS if the project wants it). Woodcase already adds `.woodcase/` to the repository's `.gitignore`. That pattern has no leading slash, so it matches at any depth, including inside bundles. The log stays out of Git, as today.
- **Linux and other platforms:** a bundle is an ordinary directory. Nothing needs macOS.

## What changes where

**Woodcase:**
- Path resolution: a `PenLocation` (name to be decided) that turns a user-given path into the `.pen` to read and write, the folder relative paths resolve against, and where the log and lock live. Every CLI verb, `PenParser.parse(contentsOf:)`, `PenFileTransaction`, `ActivityLogLocation` and file-following go through it.
- `woodcase new Design.umbra` creates a bundle; `woodcase new Design.pen` still creates a bare file.
- `woodcase bundle <file.pen>` converts in place: makes the bundle, moves the `.pen` in, and copies the local images and fonts it references into `images/` and `fonts/`, rewriting their paths. `woodcase unbundle` is the reverse.
- `--embed` (on `bundle`, and as `woodcase embed`) also downloads remote images and Google Fonts into the bundle, so it renders offline and the same everywhere. Explicit only, never automatic (Ben, 2026-10-05).
- DocC: a new article for the bundle, plus updates to `WoodcaseActivityLog.md`, `Session.md` ("Saving from an app") and `WoodcaseCLI.md`.

**Penumbra:**
- A package document type exported by the app: a UTI conforming to `com.apple.package`, with the extension below. `NSDocument` opens it as one item, so the sandbox grants the whole bundle and there is no folder prompt.
- Dropping or pasting an image copies it into `images/` and writes a relative fill. Fonts work the same way.
- The convert sheet and view-only mode for bare `.pen` files (Decided, item 4). `DocumentFolderAccess` (QnusK6) remains only for imports outside the bundle.
- File ▸ Export ▸ Pen Folder, and an explicit command that embeds remote images and Google Fonts into the bundle, making it self-contained (Ben, 2026-10-05: Save or Export, never automatic).

**RapidPro:** nothing. It receives resolved images and registered fonts, as today.

## Migration

None needed. Penumbra is pre-launch with no users. Bare `.pen` keeps working, so fixtures and tests don't change.

## Decided (Ben, 2026-10-05)

1. **Extension: `.umbra`.**
2. **The inner file is always `document.pen`**, because the user can rename the bundle at any time.
3. **Embedding remote assets is explicit only**, in both Woodcase and Penumbra: a command that copies every remote image and Google Font into the bundle, making it self-contained. Nothing is embedded automatically.

4. **A bare `.pen` in Penumbra converts, explicitly, or opens view-only.** Opening one shows a sheet before anything opens: "Penumbra keeps history, images and fonts, and collaboration in a bundle. Convert “Design.pen” to “Design.umbra”?", with **Convert…**, **View Only** and **Cancel**.
   - **Convert…** opens a save panel already pointed at the same folder and named `Design.umbra`. The panel is also what gives the sandbox permission to create the bundle. The bundle gets `document.pen` plus copies of the local images and fonts the file uses, with their paths rewritten. The original is left untouched; if a spike shows the sandbox allows it, the sheet offers to move it to the Trash.
   - **View Only** opens the file read-only. That needs only the read access the user's choice already grants. Editing is disabled, and the window shows a "View Only" badge with a Convert… button. File-following still merges outside writes, so the window can watch an agent working on a bare `.pen` live.
   - Penumbra never edits a bare `.pen` in place, so nobody ends up on a path without history and collaboration. Penumbra's folder-access prompt (QnusK6) remains only for imports outside a bundle.
   - **Woodcase prevents two sources of truth.** The bundle records the file it was converted from, with that file's revision. The CLI, run on a `.pen` with such a bundle beside it, warns: "Design.pen was converted to Design.umbra on <date>; edit that instead."
   - **`woodcase bundle Design.pen` converts in place** from the terminal: no sandbox, so it moves the file and Git sees a rename. Agents create bundles from the start (`woodcase new X.umbra`), and the agent-facing docs say to prefer them.

## Imports across bundles (decided, Ben, 2026-10-05)

`"imports": {"kit": "../Kit.umbra"}` reaches outside the granted bundle, so Penumbra's sandbox needs a grant for the library too. **Penumbra asks once per library folder and keeps an app-scoped bookmark**, so every document importing that library reuses the grant. It is the mechanism `DocumentFolderAccess` (Penumbra QnusK6) already uses for the log root. Rejected: a document-scoped bookmark per document, which asks again for each document that imports the same library. Woodcase needs nothing for this; it resolves the relative path as today.
