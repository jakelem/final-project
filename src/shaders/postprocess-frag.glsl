#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;
uniform sampler2D u_Texture;

in vec2 fs_Pos;
in vec2 fs_UV;

out vec4 out_Col;

void main() {
    vec4 col = texture(u_Texture, fs_UV);
    out_Col = col;
    //out_Col = vec4(fs_UV, 0.0, 1.0)
}
