/**
 * @schema 2.11
 * @input rows: number = 3
 * @input color: color = #3B82F6
 */
const rows = Math.max(1, Math.floor(pencil.input.rows));
const h = pencil.height / rows;
const nodes = [];
for (let r = 0; r < rows; r++) {
  nodes.push({ type: "rectangle", name: "Bar " + r, x: 0, y: r * h, width: pencil.width * (0.3 + 0.7 * Math.random()), height: h - 4, fill: pencil.input.color });
}
nodes.push({ type: "text", name: "rand", x: 4, y: 0, content: String(Math.random()).slice(0, 8), fontFamily: "Inter", fontSize: 12, fill: "#000000" });
return nodes;
