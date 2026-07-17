#version 300 es
precision mediump float;

uniform vec2 uResolution;
uniform float uTime;
uniform vec3 uColorA;
uniform vec3 uColorB;

out vec4 fragColor;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p){
  vec2 i = floor(p);
  vec2 f = fract(p);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void main(){
  vec2 uv = gl_FragCoord.xy / uResolution.xy;
  float t = uTime * 0.05;
  float n = noise(uv * 3.0 + vec2(t, -t));
  float band = smoothstep(0.15, 0.85, n + uv.y * 0.4);
  vec3 col = mix(uColorA, uColorB, band);
  float vignette = smoothstep(1.25, 0.15, length(uv - 0.5));
  fragColor = vec4(col * band * vignette, 1.0);
}
