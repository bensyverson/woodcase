precision mediump float;
/** @resolution */
uniform vec2 u_resolution;
/** @sdf */
uniform sampler2D u_sdf;
void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float d = texture2D(u_sdf, uv).r;
  float band = step(0.5, fract(d / 8.0));
  gl_FragColor = vec4(band, 0.0, 1.0 - band, 1.0);
}
