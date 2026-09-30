## Reading

### 1. Baseline resemblance

- **The story is the same, beat for beat.** Title, then the gap, the loop, tree, the script, "built with its users," one engine, this deck, and install. That is the running order of both baselines. The draft splits the loop across slides 3 and 4 and moves the Pen positioning from slide 7 to slide 9, but the story is the same.
- **Many headlines are the baselines' headlines.**
  - Slide 1: "The design layer for agents." Both baselines use it.
  - Slide 2: "Agents write the code. / They can't see the design." Both have it (baseline-2 says "can write").
  - Slide 3: "Command, view, iterate." Both have it.
  - Slide 6: "Built with its users. / The users were agents." Baseline-1 has "Designed with its users. / Its users are agents."
  - Slide 7: "One engine, many outlets." Baseline-1 uses it as a headline and baseline-2 as a section label.
  - Slide 8: "This deck is a .pen file." Baseline-1 has it. "An agent built it through the CLI" is baseline-2's second line almost word for word.
- **The two-tone headline.** Slides 2 and 8 put a dark statement over a gray rejoinder. Baseline-1's slide 2 does the same thing, and baseline-2 does it throughout with an italic second line.
- **Slide 3's verb triad.** It uses the same three verbs (shot, tree, set) as both baselines, with the same one-line glosses: "for the last mile," "guarded by its revision," "the settled layout, as text."
- **Slide 4's tree table.** It is the same `woodcase tree … --props kind.content` output, with the same five rows, as slide 3 of both baselines.
- **Slide 5's script.** Like both baselines, it measures and throws, sets the `throw` line in the accent red, and ends with "nothing was written; banking.pen is byte for byte what it was." That line is verbatim from baseline-1.
- **Slide 6's sample error.** A red refusal plus an `[exit N]` echoes baseline-2's slide 5, which shows an error and `echo $?` → 2. The paragraph lists the same four features baseline-1 turns into cards: errors that teach, exit codes, the primer, and attribution with undo.
- **Slide 7's content.** The pipeline parse → resolve → expand → layout → render and the outlets PNG, PDF, CGContext, React + Tailwind and SwiftUI are baseline-1's slide 6 and baseline-2's slide 6. "One page per top-level frame, as this deck is" is baseline-1's "Like this one."
- **Slide 8 as the dark slide.** It is a dark inversion carrying the activity log of the deck's own file. Both baselines go dark on slide 8 for the same reveal, with the same log.
- **Slide 9's ending.** A display-size mono `brew install bensyverson/tap/woodcase` and a mono spec strip ("Swift 6 · macOS 15+ and iOS 18+ for rendering · MIT licensed") make the same ending as both baselines.
- **The grid.** Headlines start top-left at the 120px margin on slides 2, 5, 6 and 8, the same grid and position as the baselines.
- **The type system.** Mono is kept for commands, and one accent color marks the verbs (blue here, orange-red in the baselines). Red means error.

### 2. Baseline departures

- **An exploded layer stack is the deck's signature object.** It is an isometric stack of real content: the JSON, the token swatches, the component boxes, the wireframe and the rendered banking screen. It appears on slides 1, 3, 5, 7, 8 and 9. Neither baseline has any image at all.
- **The deck shows actual design.** A rendered phone screen appears on the title slide. Both baselines introduce a design tool without showing a single design.
- **Slide 1 labels the pipeline on the stack.** The labels render / layout / expand / resolve / parse sit on the stack's layers, so the pipeline is an object rather than a row of words.
- **Slide 2's JSON runs off the frame.** It is raw, unboxed and cropped at the bottom edge, so it reads as endless.
- **Slide 3's loop diagram.** The agent is a node (a `>_` disc). Arrows return from the render layer (shot) and from the layout layer (tree), and one goes out to the parse layer (set). The verbs are tied to places in the pipeline.
- **Slide 4 draws the tree rows as a wireframe.** The header row is highlighted in both the table and the drawing, and an arrow links them. It is the best data-to-picture move in the deck.
- **Slide 5 brackets the whole stack as "one transaction,"** with a stop mark on the bracket.
- **Slide 6 pairs the refusal with the fix.** A red error and a blue corrected command both reach a pipeline diagram.
- **Slide 7 fans out.** One point on the highlighted render layer branches into five outlets, and each outlet carries a real command or code fragment.
- **Slide 8 stacks the deck's own slides isometrically.** The log leaves out slide 8's own write, and the caption says so.
- **Slide 9 closes the motif.** The stack is collapsed to a closed, compressed block, so the motif has an arc.
- **The palette and type are the deck's own.** It uses a cool gray-white gradient, electric blue and a grotesque sans. Both baselines use warm cream, a condensed serif and orange-red.
- **No running chrome.** There is no header marker, section label or "0N / 09" folio on every slide.
- **Code sits on the page background** rather than in dark terminal boxes.

### 3. Copy in conflict with design

- **Slide 2.** The copy's claim is about absence: "What those numbers look like never comes back." The slide shows only presence, the JSON. Nothing pictures the missing return. The blue highlight on `"fill": "$ink"` suggests a point that the copy never makes.
- **Slide 3.**
  - The headline says "Command, view, iterate," but the diagram reads top to bottom as shot, tree, set, which is view, view, command.
  - The subtitle is about tree versus screenshots rather than the loop, and it is repeated verbatim as slide 4's headline.
- **Slide 6.**
  - "Built with its users" is a claim about process. The form shows one error message.
  - The paragraph lists five features, and the design carries one of them.
  - The edge-on bars (render … parse), with the red arrow stopped at "parse," make a claim the copy never names.
- **Slide 7.**
  - The subtitle says "The core is a Swift library; the CLI is a thin consumer of it." The diagram shows no library and no CLI; the CLI is not among the outlets.
  - Two captions are raw CLI output dressed as copy: "Generated 98 file(s) to react" and "Generated 116 file(s) + 1 icon font(s) + 1 text font(s) to swiftui."
- **Slide 8.**
  - The caption says "Every write is attributed and logged, and undo replays the log." The log shows eight rows with the identical timestamp 10:17:03 and one author. That reads as a single batch dump, not a history, and nothing shows undo.
- **Slide 9.**
  - "Woodcase is agent-first, with no GUI at all" arrives on the last slide.
  - Slide 1's lush rendered screen, and the stack imagery throughout, could let a reader assume this is a visual design app.
  - ".pen" is used from slide 2 onward but not explained until here.

## Notes

### What's working

- **You found an object, and it earns its keep.** The exploded layer stack is this deck's own. It makes an invisible pipeline tangible, and it shows real design rather than talking about design. A deck about a design tool that shows no design is the default failure; you avoided it on the first slide. The stack is also built from real material (JSON, tokens, boxes, a rendered screen), so it doubles as proof.
- **The motif has an arc.**
  - It opens exploded on the title.
  - It becomes terrain for the loop on slide 3.
  - It gets bracketed as a transaction on slide 5.
  - It fans out into outlets on slide 7.
  - It turns into the deck itself on slide 8 and compresses shut on slide 9.

  That recursion on slide 8 is the smartest idea in the draft. The reader realizes they have been looking at the product all along.
- **Slide 4 is the deck at its best.** The rows are drawn as boxes, and one highlighted row is linked to its box. The slide doesn't claim that tree is readable; it lets the reader check. This is the standard for the other slides: evidence the reader can verify with their eyes.
- **The visual language escapes the default.** Cool gray, a single electric blue and a grotesque sans, with no running header or folio. It feels like an engineering instrument rather than an editorial magazine. Blue works especially well as "the tool's annotation layer": it marks what Woodcase knows about the design. Protect that meaning.
- **Showing the refusal and the fix together** (slide 6) is the right instinct for this reader. Developers trust a tool by watching it fail well.

### What's not

- **Cover the pictures and read only the headlines. Could this deck be told apart from any other deck about the product?** Right now the skeleton, the order and most of the headlines are shared with the most generic version of this story. Your images are original, but the words are not yet. Try writing each headline last, as a caption the picture has earned. What would you say about slide 3 or slide 7 that only this slide can show?
- **Slide 2 is the problem slide, and the whole deck hangs on it. Does the reader *feel* the gap?** The copy is about something missing: the design never comes back to the agent. The slide shows only what's present. How could the form make the absence felt? Consider the stack you've already built, a return path that isn't there, or a render the agent never sees. Treat the unexplained blue highlight on `fill` the same way: if it means something, the reader should be told; if not, it's noise.
- **What does the stack mean, and does it keep meaning it?**
  - On slides 1, 3, 5 and 7 it is the pipeline.
  - On slide 6 it collapses into five gray bars that read like a progress chart.
  - On slide 8 it is a pile of slides.

  A recurring motif is a promise. The reader learns it once and expects it to hold. When it changes meaning, the slide has to announce the change. On slide 6 in particular: what is the reader meant to understand from the red arrow stopping at "parse"? If you can't say it in one sentence, the diagram may not belong there.
- **Slides 3 and 4: what does the reader get from 3 that 4 doesn't give them?**
  - Slide 3's subtitle is slide 4's headline.
  - Slide 3's diagram reads top to bottom as view, view, command, against a headline that says command, view, iterate.
  - Its labels float between crossing arrows, so it takes work to pair each verb with its path.

  Either give slide 3 a job that is clearly its own (the loop as a cycle the eye can travel), or fold the two into one stronger slide.
- **Where should the eye land first on each slide?** Several slides split into three or four equal zones:
  - slide 5: prose, code, bracket and terminal
  - slide 7: stack, fan and five captions
  - slide 6: paragraph, two commands and bars

  At the same time, large empty areas are left over rather than designed: slide 2 lower left, slide 5 lower left, slide 6 upper right. A reader alone with a PDF gives each slide a few seconds. Pick the one thing, make it dominant, and let the rest support it. And ask whether the headline position is a system or a habit: bottom-left on 1, 3 and 7, top-left elsewhere. What rule decides it?
- **Every string on a slide is a design decision, including the ones the tool printed.**
  - "Generated 98 file(s) to react" is raw log text, set as a caption.
  - The CGContext snippet has lost its indentation.
  - Slide 8's log shows eight writes in the same second from one author. That reads as a batch dump, which undercuts "every write is attributed and logged," and nothing on the slide shows undo.

  Evidence convinces only if it looks deliberate. Also check the small type at the size the reader will actually meet it, a PDF on a laptop. The outlet snippets, the metadata under shot/tree/set, the layer labels and the wireframe labels (which collide with their boxes on slide 4) will turn to texture. Decide for each one whether it is meant to be read or felt, then commit either way.
- **When does the reader learn what Woodcase is, and what it isn't?**
  - ".pen" appears from slide 2.
  - The title slide shows a lush rendered phone screen, which invites the assumption that this is a visual design app.
  - "Agent-first, with no GUI at all" and the relationship to Pen arrive on the final slide, after the reader has formed their picture.

  Where in the sequence does that fact change how the rest of the deck is read? The dark inversion on slide 8 is the most predictable "reveal" move there is. Is it earning its place, or would the recursion land harder if it stayed in the deck's own light?
