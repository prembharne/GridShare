#version 300 es
precision mediump float;

uniform vec2 uResolution;
uniform float uTime;
uniform vec3 uColor;
uniform float uDensity;

out vec4 fragColor;

// Cheap hash for pseudo-random particle positions.
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void main() {
  vec2 uv = gl_FragCoord.xy / uResolution.xy;
  float aspect = uResolution.x / uResolution.y;
  vec3 col = vec3(0.0);

  // ~28 drifting motes rising slowly — "magical dust".
  const int N = 28;
  for (int i = 0; i < N; i++) {
    float fi = float(i);
    vec2 seed = vec2(fi * 1.37, fi * 2.11);
    float rx = hash(seed);
    float ry = hash(seed + 7.3);
    float speed = 0.05 + 0.12 * hash(seed + 19.1);
    float x = rx;
    float y = fract(ry + uTime * speed);            // rise upward, wrap
    float size = 0.0016 + 0.004 * hash(seed + 3.7);  // varied mote size
    float dx = (uv.x - x) * aspect;
    float dy = uv.y - y;
    float d = length(vec2(dx, dy));
    float twinkle = 0.5 + 0.5 * sin(uTime * 2.0 + fi * 6.28);
    float mote = smoothstep(size, 0.0, d) * twinkle;
    col += uColor * mote * uDensity;
  }

  fragColor = vec4(col, 1.0);
}
