#version 300 es
precision mediump float;

uniform vec2 uResolution;
uniform float uTime;
uniform vec3 uColor;
uniform float uProgress;

out vec4 fragColor;

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / uResolution.y;
  float d = length(uv);
  float ring = smoothstep(0.03, 0.0, abs(d - 0.35 - 0.015 * sin(uTime * 2.0)));
  float glow = exp(-abs(d - 0.35) * 6.0) * (0.45 + 0.55 * uProgress);
  fragColor = vec4(uColor * (ring * 0.6 + glow * 0.5), 1.0);
}
