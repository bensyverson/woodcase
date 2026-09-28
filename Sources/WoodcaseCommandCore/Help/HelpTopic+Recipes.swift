//
//  HelpTopic+Recipes.swift
//  WoodcaseCommandCore
//

/// The body of ``HelpTopic/recipes``: copy-pasteable command sequences.
///
/// Each recipe is a few commands and ends with the read that verifies it —
/// `tree`, `lint` or a scoped `get`/`tree` — so an agent can paste one, watch
/// it exit 0, and see the state it produced. `RecipesTests` extracts every
/// `  woodcase …` line (and the JSON of every `<<'TAG'` heredoc it opens) from
/// this exact string and runs it, in order, against one scratch file, so a
/// verb that changes shape breaks this file's own test rather than rotting
/// silently. A heredoc terminator is the tag alone, flush left, exactly as a
/// shell reads one.
extension HelpTopic {
    static let recipesTopic = """
    STARTING A FILE
      woodcase new design.pen
      woodcase add design.pen document -F - --as ana <<'JSON'
    {"type":"frame","name":"Home","layout":"vertical","width":390,"height":844,"padding":16,"gap":12}
    JSON
      woodcase tree design.pen
      # Home  0,0 390×844 — the one root there is, so it needs no x or y at all.

    BUILDING A SCREEN, ROOT DOWN
      One `apply` batch tags what an earlier line creates, so a later line can
      address it — @header — before it has an id.
      woodcase apply design.pen -F - --as ana <<'JSONL'
    {"op":"add","parent":"Home","tag":"header","node":{"type":"frame","name":"Header","layout":"horizontal","height":56}}
    {"op":"add","parent":"@header","tag":"title","node":{"type":"text","name":"Title","content":"Home","fill":"#111111"}}
    {"op":"add","parent":"Home","tag":"list","node":{"type":"frame","name":"List","layout":"vertical","gap":8}}
    JSONL
      woodcase tree design.pen Home

    A COMPONENT, THEN AN INSTANCE
      Marking a node reusable turns the next `cp` of it into an instance — a `ref`
      — that stores nothing of its own. A nested property on that `cp` is written
      as one of the instance's overrides, in the same write, so placing a
      component and titling it is one command. `override` changes one later;
      everything else keeps following the definition.
      woodcase set design.pen Header common.reusable=true --as ana
      woodcase cp design.pen Header List common.name=Section Title/kind.content=Section --as ana
      woodcase override design.pen List/Section/Title content=Section --as ana
      woodcase tree design.pen Home --expand --props kind.content
      # Header/Title still reads "Home"; List/Section/Title reads "Section" —
      # the one property overridden, and only it.

    REPEATING A NODE
      --times needs {n} in common.name, so the copies stay addressable by path.
      woodcase cp design.pen Header List common.name='Item {n}' --times 5 --as ana
      woodcase tree design.pen List

    A COMPONENT WITH A HOLE IN IT
      A frame with a "slot" key is a hole a definition leaves for its instances.
      The instance fills it by overriding that frame's `children` with .pen
      subtrees — refs with their own overrides included — so a component can hold
      whole composites, not only text. Every injected node needs an "id": the
      instance stores them, and the document has none to mint.
      woodcase add design.pen document -F - --as ana <<'JSON'
    {"id":"Card0","type":"frame","name":"Card","reusable":true,"layout":"vertical",
     "gap":8,"padding":8,"width":200,"height":"fit_content","children":[
       {"id":"CTtl0","type":"text","name":"Card Title","content":"Card","fill":"#111111"},
       {"id":"CSlt0","type":"frame","name":"Body","slot":["text","frame","ref"],
        "layout":"vertical","gap":4,"width":"fit_content","height":"fit_content"}]}
    JSON
      woodcase cp design.pen Card List common.name=Filled --as ana
      woodcase override design.pen Filled/Body -F - --as ana <<'JSON'
    {"children":[{"id":"Nte01","type":"text","name":"Note",
      "content":"filled from the instance","fill":"#111111"}]}
    JSON
      woodcase tree design.pen Filled --expand --props kind.content
      # Body holds Note under the instance; the definition's own slot is still
      # empty, and `lint` leaves an empty slot alone because that is the point.

    ONE COPY PER ROW
      --each reads a JSONL file — one object per copy, keys exactly the ones `cp`
      takes on argv — so a list comes from data instead of from a loop, and a row
      naming nothing refuses the whole run before anything is written.
      woodcase cp design.pen Card List --each - --as ana <<'JSONL'
    {"common.name":"Row Acme","Card Title/kind.content":"Acme"}
    {"common.name":"Row Globex","Card Title/kind.content":"Globex"}
    JSONL
      woodcase tree design.pen List --expand --props kind.content

    THEMED VARIABLES
      A --theme pin registers the axis and option it names, so a themed value
      never needs a `vars axis add` first.
      woodcase vars set design.pen --theme mode=light --as ana -- '--surface=#ffffff'
      woodcase vars set design.pen --theme mode=dark --as ana -- '--surface=#111111'
      woodcase set design.pen Header 'kind.fills=$--surface' --as ana
      woodcase tree design.pen Header --theme mode=dark --props kind.fills
      # kind.fills  #111111 — the dark option, resolved.

    THE LOOP
      `lint` before `shot`: a clean read is worth more than a picture.
      woodcase lint design.pen
      woodcase shot design.pen Home --out home.png --theme mode=dark
      woodcase tree design.pen Home/Header

    REBUILDING IN PLACE
      `replace` keeps List's id, its parent and its position; only what is under
      it changes.
      woodcase replace design.pen List -F - --as ana <<'JSON'
    {"type":"frame","name":"List","layout":"vertical","gap":8,"children":[
      {"type":"text","name":"Empty","content":"Nothing yet","fill":"#111111"}
    ]}
    JSON
      woodcase lint design.pen
    """
}
