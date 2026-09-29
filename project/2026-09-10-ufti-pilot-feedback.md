# 2026-09-10 — Feedback from an agent building a full landing page in Woodcase

Findings from one Opus agent that built a ten-section landing page as a `.pen` through the `woodcase` CLI, with no human in the loop, as a pilot beside five agents building the same page in HTML. The run is Nobedan's UFTI design experiment ([design doc](../../nobedan/project/2026-09-10-ufti-design-experiment.md), pilot output at `nobedan/project/2026-09-10-ufti-design/raw/pilot-1/`, its own report in `transcript.md` there). The agent was told only how to work (`woodcase help design`, then `recipes`, then `schema`; render after every meaningful change; `lint` for structure) and what to deliver: two artboards at 1440 and 390, a light/dark theme axis, Google Fonts by family name, named section frames.

Everything below is the agent's own account, reported here as filed. Two claims are marked for verification because the CLI's help text says otherwise.

> **Verified 2026-09-26** against the code at `6503024`: defects 2 and 3 are real render bugs, defect 1's proxy half is real (its "silent" half could not be checked), and the `$` override trap does not reproduce. Each item carries its own note below; the fixes are filed under job root `1DLDgE`.

## The cost, against HTML

| | Turns | Minutes | Cost |
|---|---|---|---|
| Woodcase pilot | 119 | 25 | $11.28 |
| HTML baseline, mean of five | 89 | 19 | $8.24 |
| HTML baseline, range | 71 to 119 | 14 to 29 | $5.85 to $12.31 |

Figures from each agent's `result.json` (`claude -p --output-format json`). So the `.pen` route cost about a third more than the HTML mean and matched the most expensive HTML agent. The agent had never seen the format before the run; the turns it spent on the three defects below are part of that number, so the tool tax with those fixed is lower than this table shows. A `help schema` count was not captured because the JSON envelope records no tool calls; the next pilot should run with `stream-json`.

What it delivered in those turns: two `fit_content` artboards (Desktop 1440 × 7400, Mobile 390 × 11261), ten named section frames each carrying a heading, a `mode` theme axis with sixteen color variables and two deliberate hard-coded colors, three Google families by name, and six reusable components instanced twenty-four times across both boards so the two widths cannot drift in copy. It drew a QR as a real 21 × 21 module path with finder patterns and a release form on a phone in a fictional studio's teal. `lint` was clean at delivery. Renders are at `raw/pilot-1/shots/{light,dark}/page-{Desktop,Mobile}.png`.

## Three defects that cost turns

1. **Font download ignores the proxy inside the Claude Code sandbox.** The Swift HTTP layer does not honor `HTTPS_PROXY`, so every Google family silently fell back to SF Pro and every measured text width was wrong. The agent's workaround was to `curl` the TTFs from `raw.githubusercontent.com/google/fonts/main/ofl/<family>/` into `~/.woodcase/fonts/<family>/` with filenames verbatim. Two things to consider: honoring the proxy variables, and a loud diagnostic when a named family resolves to the fallback, since a silent substitution is the expensive part. Note that `woodcase tree` already prints a fallback warning for an uncached family (seen on `nanoshoot-mobile.pen` with Fraunces); the agent's account suggests `render` does not, or the download failed after the warning.

   > **Correction (2026-09-26):** the proxy was only the first of three failures. The sandbox also has no DNS, not even for `localhost`. Worse, it denies the certificate-trust service (`com.apple.trustd.agent`), so no Apple TLS client inside it can verify any server. `URLSessionDataFetcher` now honors the proxy variables, and the render warning names the real cause. But a render still downloads fonts in the sandbox only with `sandbox.enableWeakerNetworkIsolation: true`. `render` did warn before, but only as "could not be resolved", with no cause. See [the finding](2026-09-26-sandbox-font-downloads.md).

2. **`render` never draws a reusable definition, only its refs.** The agent built components whose first visible instance *was* the definition. Those nodes vanished from every render while `shot` and `tree` still showed them, and the board rendered 511 pt short. The workaround was to park every definition in an `enabled: false` frame and make every visible slot a ref. If that is the intended contract, `lint` should say so when a definition sits in visible flow; if it is not, it is a render bug.

   > **Verified 2026-09-26: a render bug.** `RenderCommand` was the one verb expanding refs with `keepReusables: false`; `shot`, `tree`, `lint` and the viewer all keep definitions. No lint rule is needed. Leaf `DZ4F7D`.

3. **`render` emits only the theme axis's first option unless the option is named.** *Marked for verification:* `woodcase render --help` says it writes one image per theme combination when the document defines axes. The agent says it reproduced the single-option behavior on a two-node file and had to pass `--theme mode=dark` explicitly to get the dark renders. Either the help text or the behavior is wrong; a two-node fixture with a `mode` axis settles it.

   > **Verified 2026-09-26: the behavior is wrong, the help text right.** `ThemeCombination.frameMatches` let an artboard with no `theme` match only the default combination, so the dark pass found no frames and wrote nothing; pinning `--theme` worked only because a single combination disables that rule. Leaf `IG6B8s`.

One smaller trap: a `$` in plain text content renders literally, but the same `$` inside a component **override** lints as an unresolved variable and has to be written `\$`. Overrides and content should agree on escaping.

> **Not reproduced 2026-09-26.** A `content` override has shared text content's forgiveness since `ff8b232` (2026-09-08). The pilot's own `page.pen` with `\$29.99` and `\$6.99` unescaped lints clean with the 2026-09-20 build. Which key or build the agent hit is unrecoverable; not filed.

## What the pilot says about Woodcase as an agent surface

The agent's report reads like a designer's, not a tool-fighter's: it chose components for the reason a designer would (two widths that cannot drift), drew the thing it wanted rather than describing it, and its two "things worth knowing" were both about the tool rather than the format. That is the good news. The turn count says the format is learnable in one session from `help` alone. The three defects above are where the extra third of the cost went, and all three are fixable at the source.

Ben's read of the delta (2026-09-10): a third more turns is easily worth it where human editability matters. The HTML agents delivered a file nobody will hand-edit; the pilot delivered a document a person can open and adjust, components that keep two widths in step, a real theme axis, and named frames a script can crop. Those are the things a client or a designer touches afterwards, and the comparison should be remembered that way rather than as "a third more expensive."

**An observation, not a result (Ben, 2026-09-10):** the pilot's visual design is noticeably nicer than the five HTML baselines. One strong hero, more air, one object per band, and none of the stat rows and feature grids the HTML pages reach for. A plausible mechanism is that a `.pen` carries no browser furniture: no default cards, shadows, pill buttons or three-column grids come free, so every element is a placed decision, where HTML hands the model its most probable page for nothing. If that holds, the tool is itself a form constraint, a lever rather than a surface. One page against five cannot show it; the test is three pilots on the same brief dropped blind into the contact sheet beside the HTML pages, and Ben's pick.

The next pilot worth running, once the three are addressed: the same brief, `stream-json` to count `help` calls, and a second agent on a multi-screen mobile flow, which is the surface a single web page cannot test.
