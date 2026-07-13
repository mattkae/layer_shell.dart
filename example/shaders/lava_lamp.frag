#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

layout(location = 0) uniform vec2 uSize;
layout(location = 1) uniform float uTime;

out vec4 fragColor;

// Inverse-square falloff: the classic metaball field contribution.
float blob(vec2 p, vec2 center, float radius) {
  vec2 d = p - center;
  return (radius * radius) / max(dot(d, d), 1e-4);
}

void main() {
  vec2 uv = FlutterFragCoord() / uSize; // (0,0) = top-left, y grows downward
  float aspect = uSize.x / uSize.y;
  vec2 p = vec2(uv.x * aspect, uv.y); // aspect-corrected, so blobs stay round
  float t = uTime;

  // Seven blobs on independent sine paths. The slow y term makes them rise and
  // sink past each other like wax in a lamp; the radius breathes as they move.
  float field = 0.0;
  for (int i = 0; i < 7; i++) {
    float fi = float(i);
    float x = aspect * (0.5 + 0.34 * sin(t * (0.23 + 0.07 * fi) + fi * 2.1));
    float y = 0.5 + 0.42 * sin(t * (0.10 + 0.035 * fi) + fi * 1.7) * cos(t * 0.13 + fi);
    float r = 0.11 + 0.05 * sin(t * 0.31 + fi * 3.0);
    field += blob(p, vec2(x, y), r);
  }

  vec3 bg = mix(vec3(0.16, 0.06, 0.22), vec3(0.07, 0.05, 0.16), uv.y);
  vec3 lava = mix(vec3(1.00, 0.35, 0.15), vec3(0.98, 0.15, 0.55),
                  clamp(uv.y + 0.25 * sin(t * 0.2), 0.0, 1.0));

  float core = smoothstep(0.90, 1.60, field); // solid body
  float halo = smoothstep(0.25, 1.00, field); // surrounding bloom

  vec3 color = bg + lava * halo * 0.35;
  color = mix(color, lava, core);
  color *= 1.0 - 0.25 * pow(abs(uv.y - 0.5) * 2.0, 2.0); // gentle vignette

  fragColor = vec4(color, 1.0); // opaque; the FlView behind it is transparent
}
