precision mediump float;
/** @resolution */
uniform vec2 u_resolution;
/**
 * @label Size
 * @default 20
 */
uniform float u_size;
/**
 * @label A
 * @color
 * @default #ff0000
 */
uniform vec3 u_a;
/**
 * @label B
 * @color
 * @default #0000ff
 */
uniform vec3 u_b;
void main() {
  vec2 cell = floor(gl_FragCoord.xy / u_size);
  float check = mod(cell.x + cell.y, 2.0);
  gl_FragColor = vec4(mix(u_a, u_b, check), 1.0);
}
