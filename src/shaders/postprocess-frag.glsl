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

vec3 calcGradient(vec2 uv)
{
    vec2 epsilon = vec2(1.0) / u_Dimensions;
    float scale = 0.6;
    vec4 left = scale * texture(u_DepthTexture, vec2(uv.x - epsilon.x, uv.y));
    vec4 right = scale * texture(u_DepthTexture, vec2(uv.x + epsilon.x, uv.y));
    vec4 up = scale * texture(u_DepthTexture, vec2(uv.x, uv.y - epsilon.y));
    vec4 down = scale * texture(u_DepthTexture, vec2(uv.x, uv.y + epsilon.y));
    
    float dzdx = (right.x - left.x) * 0.5;
    float dzdy = (up.x - down.x) * 0.5;
    
    return normalize(vec3(-dzdx, -dzdy, 1.0f));

}


void main() {
    vec4 maps = texture(u_DepthTexture, fs_UV);
    float ks = maps.x;
    float kd = maps.x;

    vec3 col = texture(u_Texture, fs_UV).xyz;
    float cosPow = 30.0;
    vec3 normal = calcGradient(fs_UV);
   // normal = vec3(0.0, 0.0,1.0);
    vec3 lightPos = vec3(0.0, 4.0, -9.0);
    vec3 lightVec = normalize(vec3(fs_Pos, 0.0) - lightPos);
    vec3 viewVec = vec3(0.0,0.0,-1.0);
    
    float diffuse = clamp(dot(normal, lightVec), 0.0, 1.0);
    vec3 h = normalize(lightVec - viewVec);
    float specularIntensity = max(pow(max(dot(h, normal), 0.f), cosPow), 0.f);
    float lightIntensity = kd * diffuse + ks * specularIntensity;
    out_Col = vec4(col * lightIntensity, 1.0);
    
    if(maps.z < 0.01) {
        out_Col.xyz = col;
    }
    
    //out_Col = vec4(normal, 1.0);
}
