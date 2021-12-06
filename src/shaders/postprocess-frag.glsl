#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;
uniform sampler2D u_Texture;
uniform sampler2D u_DepthTexture;

in vec2 fs_Pos;
in vec2 fs_UV;

out vec4 out_Col;
vec3 clearColor = vec3(0.98,0.96,0.92);

// From https://gamedev.stackexchange.com/questions/59797/glsl-shader-change-hue-saturation-brightness
vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 calcGradient(vec2 uv, int idx, float scale)
{
    vec2 epsilon = vec2(1.0) / u_Dimensions;
    vec4 left = scale * texture(u_DepthTexture, vec2(uv.x - epsilon.x, uv.y));
    vec4 right = scale * texture(u_DepthTexture, vec2(uv.x + epsilon.x, uv.y));
    vec4 up = scale * texture(u_DepthTexture, vec2(uv.x, uv.y - epsilon.y));
    vec4 down = scale * texture(u_DepthTexture, vec2(uv.x, uv.y + epsilon.y));
    float dzdx = ((right[idx]) - (left[idx])) * 0.5;
    float dzdy = ((up[idx]) - (down[idx])) * 0.5;

    return normalize(vec3(-dzdx, -dzdy, 1.0f));

}


void main() {

    float paperDistortion = 1.0;

    float cosPow = 30.0;
    vec3 paperNormal = calcGradient(fs_UV, 2, 4.0);

    vec2 off_UV = fs_UV + paperNormal.xy * paperDistortion * 0.001;
    vec4 maps = texture(u_DepthTexture, off_UV);
    float kd = maps.x;
    float ks = maps.x;

    vec3 col = texture(u_Texture, off_UV).xyz;
    vec3 pencilNormal = calcGradient(off_UV, 0, 1.9);

   // normal = vec3(0.0, 0.0,1.0);
    vec3 lightPos = vec3(0.0, 0.0, -10.0);
    vec3 lightVec = normalize(vec3(fs_Pos, 0.0) - lightPos);
    vec3 viewVec = vec3(0.0,0.0,-1.0);
    
    float diffuse = clamp(dot(paperNormal, lightVec), 0.0, 1.0);
    vec3 h = normalize(lightVec - viewVec);
    float specularIntensity = max(pow(max(dot(h, paperNormal), 0.f), cosPow), 0.f);
    float lightIntensity =  diffuse;
    out_Col = vec4(col * lightIntensity, 1.0);
    //out_Col.xyz = paperNormal;
   // if(maps.z < 0.01) {
        //out_Col.xyz = col;
    //}
    
    vec3 kdNormal = calcGradient(off_UV, 1, 3.0);

    float edge = 1.0 - dot(-viewVec, kdNormal);
    
    //    edge = clamp(edge - 0.8, 0.0, 1.0);
//    edge *= 10.0;
    if (edge > 0.2) {
        vec3 outlineColor = col;
        outlineColor = rgb2hsv(outlineColor);
        outlineColor.g += 0.5;
        outlineColor.b -= 0.1;
        outlineColor = hsv2rgb(outlineColor);
        col = mix(col, outlineColor, edge);
        col = mix(col, clearColor, edge);
        //col = vec3(edge);
        //out_Col = vec4(col, 1.0);

    }
    //out_Col = vec4(vec3(maps.z), 1.0);
    //out_Col = vec4(paperNormal, 1.0);

    //out_Col = vec4(vec3(maps.y), 1.0);
    

    //out_Col = vec4(texture(u_Texture, fs_UV).xyz, 1.0);
}
