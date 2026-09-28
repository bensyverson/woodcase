precision mediump float;
/** @resolution */
uniform vec2 u_resolution;
/** @backdrop */
uniform sampler2D u_back;
void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec4 c = texture2D(u_back, uv);
  gl_FragColor = vec4(1.0 - c.rgb, 1.0);
}
