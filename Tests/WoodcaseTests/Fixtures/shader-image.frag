precision mediump float;
/** @resolution */
uniform vec2 u_resolution;
uniform sampler2D u_image;
void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  gl_FragColor = texture2D(u_image, vec2(uv.x, 1.0 - uv.y));
}
