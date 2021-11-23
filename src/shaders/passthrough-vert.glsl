#version 300 es
precision highp float;

// The vertex shader used to render the background of the scene
uniform mat4 u_ViewProj;

in vec4 vs_Pos;
out vec2 fs_Pos;

in vec2 vs_UV;
out vec2 fs_UV;

void main() {
  fs_Pos = vs_Pos.xy;
  fs_UV = vs_UV;

  gl_Position = vec4(vs_Pos.x, vs_Pos.y, 0, 1.0);
}
