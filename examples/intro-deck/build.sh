#!/bin/zsh
# Rebuilds the intro deck from scratch: ./build.sh [png-dir]
#
# Every quote on a slide is read from the tool here, never typed: the banking fixture is
# shot, treed and scripted against a scratch copy, and the deck's own activity log is read
# back for the reveal. The deck keeps its own log (WOODCASE_HOME=.woodcase) so that log is
# exactly this build's writes.
set -e
cd "${0:A:h}"
DIR=$PWD
# The checkout's own build when there is one, else whatever woodcase is on PATH.
W=${WOODCASE:-$DIR/../../.build/debug/woodcase}
[[ -x $W ]] || W=woodcase
FIX=$DIR/../../Tests/WoodcaseTests/Fixtures
PNG=${1:-$DIR/../../local/intro-deck/final}
AS=claude

export WOODCASE_HOME=$DIR/.woodcase
mkdir -p .woodcase
rm -f .woodcase/*.jsonl(N)
rm -rf build assets deck.pen intro-deck.pdf
mkdir -p build/raw build/scratch assets

# Renders every slide, in canvas order, to <dir>/slide-NN.png: shots <dir> [max]
shots() {
  mkdir -p $1
  local i=1
  for id in $($W tree deck.pen --depth 0 --json | python3 -c 'import json,sys
for r in sorted(json.load(sys.stdin)["rows"], key=lambda r: r["rect"]["x"]): print(r["id"])'); do
    $W shot deck.pen "#$id" --out "$1/slide-$(printf %02d $i).png" --max ${2:-1920} > /dev/null
    i=$((i+1))
  done
}

# 1. Warm the font cache, so the first measurement is the real one.
cat > build/warm.pen <<'JSON'
{"version":"2.17","children":[{"type":"frame","id":"Warm0","name":"Warm","layout":"vertical","children":[
 {"type":"text","id":"Wm001","name":"A","content":"Aa","fontFamily":"Schibsted Grotesk","fontWeight":"400"},
 {"type":"text","id":"Wm002","name":"B","content":"Aa","fontFamily":"Schibsted Grotesk","fontWeight":"500"},
 {"type":"text","id":"Wm003","name":"C","content":"Aa","fontFamily":"Schibsted Grotesk","fontWeight":"600"},
 {"type":"text","id":"Wm004","name":"D","content":"Aa","fontFamily":"Martian Mono","fontWeight":"400"},
 {"type":"text","id":"Wm005","name":"E","content":"Aa","fontFamily":"Martian Mono","fontWeight":"500"},
 {"type":"text","id":"Wm006","name":"F","content":"Aa","fontFamily":"Inter","fontWeight":"500"}]}]}
JSON
$W shot build/warm.pen Warm --out build/warm.png > /dev/null
$W shot $FIX/banking.pen banking-home --out build/warm2.png > /dev/null

# 2. Real material from the banking fixture. Writes go to a scratch copy only.
S=build/scratch
cp $FIX/banking.pen $FIX/kit.lib.pen quotes/measure.js $S/
R=$DIR/build/raw
$W shot $FIX/banking.pen banking-home --out assets/render.png --scale 2 > /dev/null
$W tree $FIX/banking.pen banking-home --expand --json --props kind.ref > $R/tree.json
$W tree $FIX/kit.lib.pen --json > $R/kit-tree.json
$W vars $FIX/banking.pen --json > $R/vars.json
cp $FIX/banking.pen $R/banking.pen.txt
(
  cd $S
  { echo '$ woodcase tree banking.pen banking-home/header --props kind.content'
    $W tree banking.pen banking-home/header --props kind.content; } > $R/tree-header.txt
  rev=$($W get banking.pen hdrN --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])')
  { echo "\$ woodcase set banking.pen hdrN kind.content=Sam --rev $rev"
    $W set banking.pen hdrN kind.content=Sam --rev $rev --as $AS; } > $R/set.txt
  { echo '$ woodcase shot banking.pen banking-home --out home.png'
    $W shot banking.pen banking-home --out home.png; } > $R/shot.txt
  { echo '$ woodcase set banking.pen qa4/label kind.content=Top-up'
    $W set banking.pen qa4/label kind.content=Top-up --as $AS 2>&1 && echo '[exit 0]' || echo "[exit $?]"; } > $R/refused.txt
  { echo '$ woodcase override banking.pen qa4/label content=Top-up'
    $W override banking.pen qa4/label content=Top-up --as $AS 2>&1; } > $R/fixed.txt
  $W shot banking.pen banking-home/quick-actions --out $DIR/assets/quick-actions-after.png --scale 2 > /dev/null
  { echo '$ woodcase js banking.pen -F measure.js'
    $W js banking.pen -F measure.js --as $AS 2>&1 && echo '[exit 0]' || echo "[exit $?]"; } > $R/js.txt
  $W generate react banking.pen --output react > $R/react-gen.txt 2>&1
  $W generate swiftui banking.pen --output swiftui --name Banking > $R/swiftui-gen.txt 2>&1
)
python3 lib/data.py $DIR > build/data.js

# 3. The planes: each stage of the pipeline drawn flat, turned 45°, and shot, so the stack
#    can stretch it into its dimetric view.
$W new build/planes.pen --as $AS > /dev/null
$W js build/planes.pen -F build/data.js -F lib/helpers.js -F lib/planes.js -F lib/iso-sources.js --as $AS > /dev/null
for p in parse resolve expand layout render "layout lit"; do
  $W shot build/planes.pen "Iso $p" --out "assets/iso-${p// /-}.png" --scale 1.6 > /dev/null
done

# 4. The deck, written the way it is put together: each page as an empty frame, then one
#    write per part of it (the picture, the evidence, the caption), so the log reads as the
#    deck's real history. The reveal is written last, so the log it shows is every write
#    before its own.
$W new deck.pen --as $AS > /dev/null
LIBS=(-F build/data.js -F lib/helpers.js -F lib/planes.js -F lib/stack.js)
page() {
  local k=0
  while true; do
    echo "const STEP = $k;" > build/step.js
    out=$($W js deck.pen $LIBS "$@" -F build/step.js -F lib/step.js --as $AS)
    [[ $out == *'"done"'* ]] && break
    k=$((k+1))
  done
}
for n in 01 02 03 04 05 06 07 10; do
  page -F slides/$n.js
done

# 5. In the open: the viewer serves the banking scratch copy, following the agent, and the
#    agent writes to it; the shot is taken inside the seven seconds its edit markers stay
#    up, in dark mode. The boxes slide 8 marks come from the page itself.
SLEEPY=${SLEEPY:-sleepy}
$W serve $S/banking.pen --port 0 > build/raw/url.txt 2> build/raw/serve.err &
SERVE=$!
trap 'kill $SERVE 2> /dev/null' EXIT
for i in {1..300}; do [[ -s build/raw/url.txt ]] && break; sleep 0.1; done
URL=$(head -1 build/raw/url.txt)
[[ -n $URL ]] || { cat build/raw/serve.err; exit 1; }
VIEW=$(curl -sf ${URL}files | python3 -c 'import json,sys
f=json.load(sys.stdin)["files"][0]
print(f["id"] + "/artboards/" + next(a["id"] for a in f["artboards"] if a["name"] == "banking-home"))')
PAGE="${URL}files/$VIEW?follow=$AS&tab=activity"
(
  cd $S
  $W set banking.pen hdrN kind.content=Ada --as $AS
  $W override banking.pen Qh9Dq/ydTfa 'content=\$31,204.15' --as $AS
  $W override banking.pen aqCub/vpvCO 'content=Blue Bottle' --as $AS
) > /dev/null
# Connected, and the render drawn; the edit markers are still up (they last seven seconds).
READY='js:[...document.querySelectorAll(".v-live-label")].some(e => e.dataset.state == "live" && e.offsetParent) && [...document.images].every(i => i.complete && i.naturalWidth > 0)'
$SLEEPY shot "$PAGE" --size 1600x1000 --scale 2 --theme dark --wait-for $READY --out assets/dashboard.png > /dev/null
for m in presence:'#v-presence' live:'.v-live-label' activity:'#v-activity' outline:'#v-outline'; do
  $SLEEPY query "$PAGE" --size 1600x1000 --theme dark --wait-for $READY --selector ${m#*:} > build/raw/dash-${m%%:*}.json
done
kill $SERVE; trap - EXIT
python3 lib/dash.py $DIR > build/dash.js
page -F build/dash.js -F slides/08.js

# 6. The reveal: this deck's own pages become the planes, beside its own log.
shots build/thumbs 960
$W js build/planes.pen -F build/data.js -F lib/helpers.js -F lib/planes.js -F lib/iso-thumbs.js --as $AS > /dev/null
for n in 1 2 3 4 5 6 7 8; do
  $W shot build/planes.pen "Iso thumb $n" --out assets/iso-thumb-$n.png --scale 1 > /dev/null
done
# In UTC, so its times agree with the undo dry-run's timestamps beside it.
TZ=UTC $W activity deck.pen -n 1000 > build/raw/log.txt
{ echo '$ woodcase undo deck.pen --dry-run'
  $W undo deck.pen --dry-run --as $AS; } > build/raw/undo.txt
python3 lib/log.py $DIR > build/log.js
page -F build/log.js -F slides/09.js

# Crops are deliberate: a plane running off the page reads as clipped, and that is the point.
$W lint deck.pen || true

# 7. The PDF, one vector page per top-level frame, and the page renders.
rm -f intro-deck.pdf
$W render deck.pen --format pdf > /dev/null
mv deck.pdf intro-deck.pdf
shots $PNG
echo "built deck.pen, intro-deck.pdf → $PNG"
