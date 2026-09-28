//
//  HelpTopic+Codegen.swift
//  WoodcaseCommandCore
//

/// The body of ``HelpTopic/codegen``: how to build a component `generate react` and
/// `generate swiftui` recognise, and what the SwiftUI package is and how to build and run it.
///
/// The body lives here rather than in `HelpTopic.swift` because it is held to the same
/// bar as the recipes topic — `HelpCommandTests` extracts every bare `  woodcase …` line
/// from this exact string and runs it, in order, against one scratch file, then reads the
/// `.tsx` it produced. A command line that is a *form* rather than a step — one carrying a
/// placeholder, or a pointer at another verb — is written in backticks, which is what
/// keeps it out of the run and out of an agent's copy-paste.
///
/// What it teaches is what `ComponentAnalyzer` and `ReactEmitter` actually read, not what
/// the format could carry: `_bind` is documented here as unread because no version of the
/// analyzer has ever looked at it, and `_action` is documented as recorded-but-unemitted
/// because nothing downstream of `ComponentDefinition.actions` consumes it.
extension HelpTopic {
    static let codegenTopic = """
    WHAT BECOMES A COMPONENT, WHAT BECOMES A PAGE
      `woodcase generate react` reads one flag to decide: common.reusable. A node with
      common.reusable=true becomes components/<Name>.tsx — the name PascalCased, a leading
      "Component/" dropped, so "Component/Action Button" emits ActionButton — and it may
      sit anywhere in the tree. Every OTHER top-level frame (a direct child of the
      document, not reusable) becomes pages/<Name>.tsx, importing the components its
      instances point at. Nothing else emits a file: a frame inside a page is that page's
      markup, and a document of nothing but components emits no pages/ directory at all.

    THE FOUR METADATA KEYS THAT ARE READ
      Everything a component declares beyond its drawing lives in common.metadata. That is
      one object, so writing it whole DROPS every key already there; write one key at a
      time, a further dot goes into the map, and =null takes an entry away. The schema
      requires metadata.type, so an object one of these writes CREATES carries
      type="unknown" beside your key — the default, not a mistake, and read by nothing
      here. Choose it in the same write to get {"type":"component","_role":"button"}:
        `woodcase set design.pen Button common.metadata.type=component common.metadata._role=button`
        _role    what the component is — its element, its extra props, its state triggers
                 `woodcase set design.pen Button common.metadata._role=button`
        _props   the parameters it publishes: name -> a name path to one descendant
                 `woodcase set design.pen Button common.metadata._props.label=Label`
        _action  a name for what a role-carrying node does
                 `woodcase set design.pen Button common.metadata._action=submit`
        _states  a variant the naming convention below will not find, by node id
                 `woodcase set design.pen Button common.metadata._states.hover=<node id>`
      Two warnings, because the format is wider than the reader: _bind is NOT read — a
      component's bindings come from _role alone — and _action is recorded but nothing in
      the React output reflects it yet, so declare it for intent, not for an onSubmit prop.

    _role — SIX VALUES, ON THE COMPONENT'S OWN ROOT
      button   link   toggle   textInput   select   tabBar
      Only the root of a reusable node is read for the role, and it buys three things:
        the element  button and toggle emit <button>, link an <a href={href}>, tabBar a
                     <nav role="tablist">; textInput, select and no role emit a <div>.
        extra props  disabled? wherever the role has a disabled state, checked? on a
                     toggle, href? on a link, selected?: "home" | … on a tabBar.
        triggers     what the states below hang off — :hover, :active, :focus-visible,
                     :disabled, [data-open] — plus smart defaults for the states you did
                     not draw (hover dims, pressed scales, disabled fades).
      A role on a DESCENDANT is read only into the analysis — it is what makes a textInput,
      toggle or select node a binding — and no React output reflects a binding yet.

    _props — THE PARAMETERS A CONSUMER SETS
      One entry per parameter: the name a consumer writes, and a name path from the
      component's root down to the one descendant it stands for ("Label", "Body/Title").
      The property and the TypeScript type are inferred from what that descendant IS — a
      text node gives a string prop over its content, with its current content as the
      default; a rectangle, frame or ellipse gives a color prop over its fill, or an
      imageURL prop when that fill is an image. Read the answer back, never guess it:
      `woodcase get design.pen Button` prints a props block of name, resolved path and
      type, and says so in the row when a declared path resolves to no node. Give each
      parameter its own descendant: an override is keyed by node id, so two parameters
      naming one node cannot be told apart. `common.metadata._props.spare=null` drops one.

    INSTANCES: AN OVERRIDE BECOMES A PROP, OR INLINES THE COMPONENT
      `cp` of a reusable node makes an instance — a ref — and `override` writes one
      property on one descendant of it. A declared parameter name is accepted in place of
      the property name, so `woodcase override design.pen Home/Save label=Send` lands on
      whatever _props says label is. The emitter walks those overrides back through _props:
      one that lands on a declared parameter's node becomes an attribute on the tag. One
      that lands anywhere ELSE cannot be said as a prop, so the emitter gives up on the tag
      and INLINES the component — the whole patched tree is pasted into the page under a
      {/* Customized from: Button */} comment, and that instance stops sharing the
      component. Declare a parameter for everything you mean to override. The instance's
      own width, height, cornerRadius and fill are the exception: those are root overrides,
      they become a style={{…}} on the tag, and they never inline it.

    STATE VARIANTS
      Draw the variant as a top-level frame named {Component}:{state} — Button:hover beside
      Button — and leave it non-reusable; it is diffed against the component, the
      difference becomes CSS in states.css keyed to the role's trigger, and it is not
      mistaken for a page. Known names: button hover/pressed/disabled/focused; link
      hover/active/focused; toggle on/disabled/focused; textInput focused/filled/disabled;
      select focused/open/disabled. Any other name becomes [data-<name>="true"], and a
      variant that adds or removes children becomes a boolean prop and a second render
      function. A component with NO _role gets no states from the naming convention at all
      — the sibling is ignored in silence, so give it a role. tabBar is the other exception:
      its variants are siblings at its own level, may themselves be reusable, and merge
      into one component with selected?: "home" | "log" instead of booleans.

    WORKED EXAMPLE: A BUTTON, FROM NOTHING TO A TYPED PROP
      woodcase new design.pen
      woodcase add design.pen document -F - --as ana <<'JSON'
    {"type":"frame","name":"Home","layout":"vertical","width":390,"height":844,"padding":16,"gap":12}
    JSON
      woodcase add design.pen document -F - --as ana <<'JSON'
    {"type":"frame","name":"Button","layout":"horizontal","gap":8,"padding":12,"fill":"#2563EB",
     "children":[{"type":"text","name":"Label","content":"Save","fill":"#FFFFFF"},
     {"type":"rectangle","name":"Dot","width":8,"height":8,"fill":"#FFFFFF"}]}
    JSON
      woodcase add design.pen document -F - --as ana <<'JSON'
    {"type":"frame","name":"Button:hover","layout":"horizontal","gap":8,"padding":12,
     "fill":"#1D4ED8","children":[{"type":"text","name":"Label","content":"Save","fill":"#FFFFFF"},
     {"type":"rectangle","name":"Dot","width":8,"height":8,"fill":"#FFFFFF"}]}
    JSON
      woodcase set design.pen Button common.reusable=true --as ana
      woodcase set design.pen Button common.metadata._role=button --as ana
      woodcase set design.pen Button common.metadata._props.label=Label --as ana
      woodcase set design.pen Button common.metadata._props.tint=Dot --as ana
      woodcase get design.pen Button
      # props
      #   label  Label/kind.content  string
      #   tint   Dot/kind.fills      color
      woodcase cp design.pen Button Home common.name=Save --as ana
      woodcase override design.pen Home/Save label=Send tint=#FFD166 --as ana
      woodcase generate react design.pen --output ui
      # ui/components/Button.tsx  interface ButtonProps { label?: string; tint?: string;
      #                           disabled?: boolean; … }, root <button type="button">
      # ui/pages/Home.tsx         <Button label="Send" tint="#FFD166" />
      # ui/states.css             .wc-button:hover { --wc-button-bg: #1D4ED8; }

    THE SWIFTUI TARGET: A PACKAGE YOU BUILD AND RUN
      `woodcase generate swiftui design.pen --output ui --name Acme` reads the same components,
      roles, props and states and writes a SwiftPM package: a public View per component and
      page, the theme, a catalog, and under Sources/Acme/Resources every image, icon font and
      text font the views draw. A text family the OS does not ship is taken from the document's
      declared fonts, else from Google Fonts through the font cache; one with no file is a
      warning, and draws in whatever the system has. The views register the fonts themselves;
      an app calls PenFonts.register() only to set a bundled family in views of its own.
        `cd ui && swift build`                         iOS 26 / macOS 26, or --floor ios18
        `swift run <Name>Catalog`                      every component, state, page and token
        `swift run <Name>Catalog --snapshot kit.png`   the catalog under every theme, as a PNG
        `swift run <Name>Catalog --fonts`              each bundled font, and whether it registered
      Package.swift is rewritten on every run: depend on the package, do not edit it.

    SEE ALSO
      `woodcase help design` — addressing, naming, and the read-write-verify loop every
      command above assumes. `woodcase generate react --help` — the flags: --output,
      --package, --preview; `woodcase generate swiftui --help` — --output, --name, --floor.
      `woodcase lint` is where the traps in this topic become a report rather than a
      surprise: a _props path that resolves to nothing, or two entries reading one field of
      one descendant (codegen-prop-path), a _role outside the six (codegen-role), and an
      instance the emitter would inline (codegen-unmapped-override). Run `woodcase lint
      --list` to see which checks this build carries; if those three are not in it, it
      predates them.
    """
}
