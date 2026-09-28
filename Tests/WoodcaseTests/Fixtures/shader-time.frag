precision mediump float;
/** @resolution */
uniform vec2 u_resolution;
/** @time */
uniform float u_time;
void main() {
  float t = clamp(u_time / 10.0, 0.0, 1.0);
  gl_FragColor = vec4(t, 0.5, 0.0, 1.0);
}
