# 2026-10-11 — What Pen keeps on a note, a prompt and a context

Evidence for decision 2 of [the post-it design](2026-10-04-post-it-design.md) and leaf `upM3W0`. Every claim is the headless `pen` CLI engine's observable output (`pen 0.3.11`): what `Get` reports after loading a probe file, and what `save()` writes. Pen.app itself was not opened; [the text-style report](2026-09-26-what-pen-drops-from-a-file.md) found Pen.app's load and save matched this engine's for text nodes, but that is not re-checked here for notes. How Pen *draws* a note (criterion `VUA`, a reference PNG) is not covered and needs Pen.app.

## Method

Two hand-written probe files (format `2.20`), run from a scratch directory with the Bash sandbox off:

```
pen interactive --in probe.pen --out saved.pen < cmds.txt
#   cmds.txt: execute({ input: 'Get(n=>{if(["note","prompt","context"].includes(n.type)){Print(JSON.stringify(n))}})' })
#             save()
#             exit()
```

then a key-by-key diff of the input against the saved file (`2.21`).

- **Probe 1:** a frame holding a card, a note with every post-it metadata key, an unsized note, a `prompt` with metadata and `model`, and a `context` with metadata. The note's metadata: `type: postit`, `kind`, `state`, `author`, `tint`, `leaf`, `stage`, plus keys not yet in the convention (`anchor`, `replyTo`, a `mentions` array, and a nested object holding an array with `true`, `null` and a string). Its content had markdown and an `@mention`.
- **Probe 2:** one note with `width`, `height`, `fill`, `fontFamily`, `fontSize`, `fontWeight`, `fontStyle`, `lineHeight`, `letterSpacing`, `textAlign`, `textGrowth`, `rotation` and `opacity`.

## Findings

| On a note | Kept through load and save |
|---|---|
| `metadata`, every key, nested objects and arrays included, values unchanged | **yes** |
| `width`, `height` | yes |
| `rotation`, `opacity`, `x`, `y`, `name`, `content` (markdown and `@` untouched) | yes |
| `fill` | **no** |
| `fontFamily`, `fontSize`, `fontWeight`, `fontStyle`, `lineHeight`, `letterSpacing`, `textAlign`, `textGrowth` | **no** (all eight) |

- **Prompt and context keep their metadata too** (`state`, `requestedBy` on the prompt; `type`, `kind` on the context), and the prompt keeps `model`.
- **An unsized note, prompt or context gains `width: 0`, `height: 0`** on save.

## What it means for the design

- **Decision 2 holds:** the tint belongs in `metadata.tint`, as a note `fill` does not survive.
- **The design's model premise is wrong for current Pen.** It gives notes "the full TextStyle set", reading Pen's schema (Note extends Entity, Size, TextStyle), but Pen strips all of it on load. A font size or family set on a note — which Penumbra's inspector edits and its resize scales (spec §5.9 item 9) — would be lost the first time the board is saved in Pen. Where the note's text style should live instead (for example in metadata, like the tint) is a decision for Ben, recorded on `upM3W0`.
- **Everything else a post-it needs survives**: kind, state, author, tint, the anchor to a node, replies and mentions in metadata, and markdown in `content`.

## Rich text (styled runs)

Asked by Ben the same day: can a word be bold in Pen? No. Pen's schema (`read_skill({ path: "pen-schema.md" })`, format 2.21) gives `TextContent = StringOrVariable`: one string in one style per text node. Up to 2.10, `content` could be an array of styled runs (`PenRichTextMigrationRule`), and 2.17 dropped it.

**Probe 3:** a `text` node and a `note`, each with the 2.10 run array as `content` (`[{"content": "Make this "}, {"content": "bold", "fontWeight": "700"}, {"content": " please"}]`), loaded and saved the same way. Pen dropped `content` outright on both: the saved text node and note have **no words at all**. So reviving the old array shape would make a Pen round-trip delete the text, not just its styling.
