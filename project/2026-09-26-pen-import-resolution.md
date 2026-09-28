# How Pen resolves a document's `imports` (2026-09-26)

Author: Claude (agent `readctx`, leaves `koyac9` / `ukfIU2`), for Ben's ruling of the same
day: every Woodcase read loads the libraries a document's own `imports` declares, as
read context, and `--library` goes. The ruling asked for Pen's actual behaviour to be
established first and mirrored. This is what Pen does, from its outputs only.

## Method

`pen` 0.3.9 (Homebrew), headless: `pen interactive --in <host.pen> --out <scratch.pen>`,
fed `get_app_state()` (its *Reusable components* line lists what resolved), a `Get`
visitor printing ids and refs, and `Export([...],'png',<dir>,{scale:1})`. Sandbox off
(the `pen` CLI needs the network to authenticate). Every probe host was a few lines of
JSON written for the question; the probes lived in the session scratchpad and are
reproduced inline below.

## Findings

1. **A bare name is the file beside the document, and nothing else.** A host importing
   `{"V": "kit.lib.pen"}` with `kit.lib.pen` beside it lists every `V:` component. The
   same host in a folder without the sibling — run from a working directory that *does*
   hold `kit.lib.pen` — logs `Cannot import 'kit.lib.pen'! Error: ENOENT … open
   '<host folder>/kit.lib.pen'`, then `Invalid ref 'V:b32gU'`, and lists no reusable
   components. One path is tried: no working-directory fallback, no libraries folder.
2. **`./`, `../`, absolute paths and `file:` URLs** all resolve against the host's folder
   or as they stand.
3. **`pencil:<name>` names a library bundled with Pen.** `pencil:shadcn.lib.pen` resolves
   with nothing beside the host; the CLI reads it from its own install
   (`…/@pen.dev/cli/dist/out/data/`, which holds `halo`, `lunaris`, `nitro` and `shadcn`
   `.lib.pen`; the desktop app keeps the same four inside its `app.asar`).
   `pencil:kit.lib.pen` with `kit.lib.pen` beside the host fails with ENOENT on
   `…/out/data/kit.lib.pen`: the document's own folder is never consulted for this form.
   This is very likely the "library named with no path" Ben suspected real files use.
4. **An unreadable file** (`not json`) logs `Cannot import … DocumentParseError`; the
   document still opens and the instances are invalid refs.
5. **A library's own imports are not followed.** `a.lib.pen` importing `{"B":
   "b.lib.pen"}`, with `b.lib.pen` beside both it and the host: Pen logs `Invalid ref
   'A:B:Bcmp1'` and never tries to load `b`. One level only.
6. **A document may import itself**, and is then its own library once (`S:Cmp01`
   resolves); the copy's imports are not followed (`S:S:Cmp01` is invalid). Finding 5
   makes a cycle impossible, so there is nothing to detect.
7. **Overrides through an import** — `K:Txt01`, `K:Cc001/K:Txt01` through the kit's own
   nested instance, and `Kin01/K:Txt01` through a host component holding a kit instance —
   all apply, and an imported variable (`$accent` → `$K:accent`) resolves. The fixture
   pair `Tests/WoodcaseTests/Fixtures/imports/{app,kit.lib}.pen` is that probe.

One more fact turned up on the way, unrelated to imports: **Pen applies a bare
`descendants` key to a node injected into a nested instance's slot.** A host instance of
`Scr01` (which holds `Ins0A`, an instance of `Slot1` that injects rectangle `Inj01` into
its slot) keyed `{"Inj01": {"fill": blue}}` draws blue in Pen; `{"Ins0A/Inj01": …}`
applies too. Woodcase applies only the second, and `lint` reports the first as
`override-target-not-found`. `banking.pen`'s eight remaining findings of that check are
exactly this shape (`2592p`, `G6llC`, `T2IOh`, `WKey6` on `#YGJ0d` and `#8ruxp`).

> **Update (2026-09-26, leaf `ILYyZi`):** the full rule is measured in
> [slot-override-keys](2026-09-26-slot-override-keys.md), and Woodcase now applies these
> keys and lints them clean.

## What Woodcase does with it

`PenLibraries.load(importedBy:at:)` mirrors findings 1–6: relative to the host's own
file, one read per distinct path, a self-import answered with the document in hand, a
library's own imports reported (`import-not-followed`) and never loaded, `pencil:` and
remote URLs reported (`import-not-found`) and never looked for on disk or fetched.
`PenFileTransaction` loads them once per read into `EditableDocument.readContext`, and
`EditableDocument.expanded(for:)` is the one expansion `tree`, `lint`, `shot`, `render`,
the viewer and scripts share. `generate` merges the libraries' components into its
output as before. The brief this answered asked for nested and cyclic imports to be
followed with cycle detection; finding 5 overturns that, and Woodcase follows Pen.
