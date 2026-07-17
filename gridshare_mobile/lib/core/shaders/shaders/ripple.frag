#version 300 es
precision mediump float;

uniform vec2 uResolution;
uniform float uTime;
uniform vec3 uColor;
uniform float uIntensity;

out vec4 fragColor;

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5 * uResolution.xy) / uResolution.y;
  float d = length(uv);
  float rings = sin(d * 22.0 - uTime * 3.0);
  float pulse = smoothstep(0.0, 0.5, rings) * exp(-d * 2.2);
  fragColor = vec4(uColor * pulse * uIntensity, 1.0);
}
