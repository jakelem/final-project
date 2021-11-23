#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

float pi = 3.14159265359;
float degToRad = 3.14159265359 / 180.0;

uniform float[20] u_BirdParameters;

struct MapQuery
{
  float dist;
  int material;
};

struct RaycastQuery
{
    bool intersected;
    vec3 isect;
    int material;
};

struct Material
{
    vec3 color;
    float kd;
    float ks;
    float cosPow;
    float displacement;
};

struct PointLight
{
    vec3 position;
    vec3 color;
    bool castsShadow;
};

float hash3(vec3 v)
{
    return fract(sin(dot(v, vec3(24.51853, 4815.44774, 32555.33333))) * 3942185.3);
}

vec4 noise3(vec3 v)
{
    //Adapted from IQ: https://www.iquilezles.org/www/articles/morenoise/morenoise.htm
    vec3 intV = floor(v);
    vec3 fractV = fract(v);
    vec3 u = fractV*fractV*fractV*(fractV*(fractV*6.0-15.0)+10.0);
    vec3 du = 30.0*fractV*fractV*(fractV*(fractV-2.0)+1.0);
    
    float a = hash3( intV+vec3(0.f,0.f,0.f) );
    float b = hash3( intV+vec3(1.f,0.f,0.f) );
    float c = hash3( intV+vec3(0.f,1.f,0.f) );
    float d = hash3( intV+vec3(1.f,1.f,0.f) );
    float e = hash3( intV+vec3(0.f,0.f,1.f) );
    float f = hash3( intV+vec3(1.f,0.f,1.f) );
    float g = hash3( intV+vec3(0.f,1.f,1.f) );
    float h = hash3( intV+vec3(1.f,1.f,1.f) );
    
    float k0 =   a;
    float k1 =   b - a;
    float k2 =   c - a;
    float k3 =   e - a;
    float k4 =   a - b - c + d;
    float k5 =   a - c - e + g;
    float k6 =   a - b - e + f;
    float k7 = - a + b + c - d + e - f - g + h;
    
    
    vec3 dv = 2.0* du * vec3( k1 + k4*u.y + k6*u.z + k7*u.y*u.z,
                             k2 + k5*u.z + k4*u.x + k7*u.z*u.x,
                             k3 + k6*u.x + k5*u.y + k7*u.x*u.y);
    
    return vec4(-1.f+2.f*(k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z), dv);
}

vec4 fbm3(vec3 v, int octaves, float amp, float freq, float pers, float freq_power)
{
    float sum = 0.f;
    vec3 dv = vec3(0.f,0.f,0.f);
    float speed = 0.01f;
    for(int i = 0; i < octaves; ++i)
    {
        amp *= pers;
        freq *= freq_power;
        vec4 noise = noise3((v) * freq);
        sum += amp * noise.x;
        dv += amp * noise.yzw;
    }
    return vec4(sum, dv);
}

MapQuery smoothMin( MapQuery a, MapQuery b, float k)
{
    float h = clamp( 0.5+0.5*(b.dist-a.dist)/k, 0.0, 1.0 );
    MapQuery res;
    if(h < 0.5) {
        res.dist = mix( b.dist, a.dist, h ) - k*h*(1.0-h);
        res.material = b.material;
    } else {
        res.dist = mix( b.dist, a.dist, h ) - k*h*(1.0-h);
        res.material = a.material;
    }
    return res;
}

MapQuery smoothMax( MapQuery a, MapQuery b, float k)
{
    float h = max(k-abs(a.dist-b.dist),0.0);
    MapQuery res;
    if(a.dist > b.dist) {
        res.dist = (a.dist + h*h*0.25/k);
        res.material = b.material;
    } else {
        res.dist = (b.dist + h*h*0.25/k);
        res.material = a.material;
    }
    return res;
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    if(h < 0.5) {
        return mix( b, a, h ) - k*h*(1.0-h);
    } else {
        return mix( b, a, h ) - k*h*(1.0-h);
    }
}

float smax( float a, float b, float k )
{
    float h = max(k-abs(a-b),0.0);
    return a > b ? (a + h*h*0.25/k) : (b + h*h*0.25/k);
}


vec3 elongate( vec3 p, vec3 h )
{
    vec3 q = p - clamp( p, -h, h );
    return q;
}
float cappedCone(vec3 p, vec3 a, vec3 b, float ra, float rb)
{
    float rba  = rb-ra;
    float baba = dot(b-a,b-a);
    float papa = dot(p-a,p-a);
    float paba = dot(p-a,b-a)/baba;
    float x = sqrt( papa - paba*paba*baba );
    float cax = max(0.0,x-((paba<0.5)?ra:rb));
    float cay = abs(paba-0.5)-0.5;
    float k = rba*rba + baba;
    float f = clamp( (rba*(x-ra)+paba*baba)/k, 0.0, 1.0 );
    float cbx = x-ra - f*rba;
    float cby = paba - f;
    float s = (cbx < 0.0 && cay < 0.0) ? -1.0 : 1.0;
    return s*sqrt( min(cax*cax + cay*cay*baba,
                       cbx*cbx + cby*cby*baba) );
}

float roundCone(vec3 p, vec3 a, vec3 b, float r1, float r2)
{
    // sampling independent computations (only depend on shape)
    vec3  ba = b - a;
    float l2 = dot(ba,ba);
    float rr = r1 - r2;
    float a2 = l2 - rr*rr;
    float il2 = 1.0/l2;
    
    // sampling dependant computations
    vec3 pa = p - a;
    float y = dot(pa,ba);
    float z = y - l2;
    float x2 = dot( pa*l2 - ba*y, pa*l2 - ba*y );
    float y2 = y*y*l2;
    float z2 = z*z*l2;

    // single square root!
    float k = sign(rr)*rr*rr*x2;
    if( sign(z)*a2*z2 > k ) return  sqrt(x2 + z2)        *il2 - r2;
    if( sign(y)*a2*y2 < k ) return  sqrt(x2 + y2)        *il2 - r1;
                            return (sqrt(x2*a2*il2)+y*rr)*il2 - r1;
}

// Ra: radius rb: roundedness h: height
float roundedCylinder( vec3 p, float ra, float rb, float h )
{
  vec2 d = vec2( length(p.xz)-2.0*ra+rb, abs(p.y) - h );
  return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
}

float cappedTorus(vec3 p, vec2 sc, float ra, float rb)
{
  p.x = abs(p.x);
  float k = (sc.y*p.x>sc.x*p.y) ? dot(p.xy,sc) : length(p.xy);
  return sqrt( dot(p,p) + ra*ra - 2.0*ra*k ) - rb;
}

float box( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}


float sphere(vec3 p, float s)
{
    return length(p) - s;
}

float ellipsoid( vec3 p, vec3 r )
{
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0*(k0-1.0)/k1;
}

float stick(vec3 p, vec3 a, vec3 b, float r1, float r2)
{
    vec3 pa = p-a, ba = b-a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return  length( pa - ba*h ) - mix(r1,r2,h*h*(3.0-2.0*h));
}


vec3 bend( vec3 p, float k )
{
    float c = cos(k*p.x);
    float s = sin(k*p.x);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
}


vec3 twist( vec3 p, float k)
{
    float c = cos(k*p.y);
    float s = sin(k*p.y);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xz,p.y);
    return q;
}

float onion(float sdf, float thickness)
{
    return abs(sdf) - thickness;
}

float roundBox( vec3 p, vec3 b, float r )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

// https://iquilezles.org/www/articles/noacos/noacos.htm
mat3 rotationAxisAngle( vec3 v, float a )
{
    float si = sin( a );
    float co = cos( a );
    float ic = 1.0f - co;

    return mat3( v.x*v.x*ic + co,       v.y*v.x*ic - si*v.z,    v.z*v.x*ic + si*v.y,
                   v.x*v.y*ic + si*v.z,   v.y*v.y*ic + co,        v.z*v.y*ic - si*v.x,
                   v.x*v.z*ic - si*v.y,   v.y*v.z*ic + si*v.x,    v.z*v.z*ic + co );
}

float plane( vec3 p, vec3 n, float h )
{
  // n must be normalized
  return dot(p,n) + h;
}

float getBias(float time, float bias)
{
    return (time / ((((1.0/bias) - 2.0)*(1.0 - time))+1.0));
}

float getGain(float time,float gain)
{
  if(time < 0.5)
    return getBias(time * 2.0,gain)/2.0;
  else
    return getBias(time * 2.0 - 1.0,1.0 - gain)/2.0 + 0.5;
}



float feather(vec3 p, vec3 a, vec3 b, float r1, float r2, vec3 cutOffset, float thickness)
{
    float cone1 = roundCone(p, a, b, r1, r2);
    cone1 = onion(cone1, thickness);
    
    vec3 dir = 3.0 * normalize(a - b);
    float cutCone = roundCone(p + cutOffset, a + dir, b - dir, r1 * 1.1, r2 * 1.1);
    return smax(cone1, -cutCone, 0.01);
    //return smin(cone1, cutCone, 0.01);

}

MapQuery map(vec3 p)
{

    float weight = u_BirdParameters[0];
    float neckLength = u_BirdParameters[1];
    float neckWidth = u_BirdParameters[2];
    float headSize = u_BirdParameters[3];
    float tailAngle = u_BirdParameters[4];
    float tailSpread = u_BirdParameters[5];
    float tailLength = u_BirdParameters[6];
    float height = u_BirdParameters[7];
    float skullLength = u_BirdParameters[8];
    float beakHeight = u_BirdParameters[9];
    float beakLength = u_BirdParameters[10];

    vec3 groundPos = vec3(0.0, -1.0, 0.0);
    vec3 footPos = groundPos + vec3(0.0, 0.0, 0.4);
    vec3 bodyPos = groundPos + vec3(0.0, height, 0.0);

    float lowerBodyWidth = weight * 0.9 + 0.1;
    float breastWidth = weight * 1.2;
    float upperNeckWidth = neckWidth * weight * 0.9;
    float lowerNeckWidth = mix(upperNeckWidth, breastWidth, 0.4);
    float headWidth = mix(upperNeckWidth, headSize * 0.5 + weight * 0.5, 0.6);

    vec3 neckVector = vec3(-0.5, 0.86, 0.0);

    
    //TODO: replace offset with parameters
    // Puff out more with weight
    vec3 neckStartPos = bodyPos + vec3(-1.0 - weight * 0.1, 0.7, -0.0);

    // Body
    MapQuery res = MapQuery(roundCone(p, bodyPos, neckStartPos, lowerBodyWidth, breastWidth), 0);
    
    // Body details
    //vec3 sidesPos = bodyPos + vec3(-1.0, 1.0,-0.4);
   // res = smoothMin(res, MapQuery(sphere(p - sidesPos, 0.5), 1), 0.6);
    
    // Neck to head
    //TODO: replace offset with parameters
    vec3 neckEndPos = neckStartPos + neckLength * neckVector;
    res = smoothMin(res, MapQuery(roundCone(p, neckStartPos, neckEndPos, lowerNeckWidth, upperNeckWidth), 1), 0.3);

    vec3 headStartPos = neckEndPos + vec3(-0.3,0.4, 0.0);
    vec3 headEndPos = headStartPos + vec3(-0.45 - skullLength, 0.0, 0.0);
    float frontalSkull = mix(headWidth, beakHeight, 0.6);
    vec3 beakPos = headEndPos + vec3(-frontalSkull, 0.1, 0.0);

    vec3 beakTipPos = beakPos + vec3(-beakLength, 0.0, 0.0);

    res = smoothMin(res, MapQuery(roundCone(p, headStartPos, headEndPos, headWidth, frontalSkull), 2), 0.2);

   // vec3 breastPos = bodyPos + vec3(-1.0, 1.0,0.0);
   // res = smoothMin(res, MapQuery(sphere(p - breastPos, 1.0), 0), 0.1);

    float beak = roundCone(p, beakPos, beakTipPos, beakHeight, 0.01);
    beak = onion(beak, 0.03);
    
    vec3 midBeak = 0.5 * (beakPos + beakTipPos) - vec3(0.0, beakLength, 0.0);
    
    //float cutBeak = sphere(p - midBeak, max(beakLength, beakHeight));
    float cutBeak = roundCone(p + vec3(0.0, beakHeight, 0.0), beakPos, beakTipPos, beakHeight, beakHeight);

    MapQuery topBeak = smoothMax(MapQuery(-cutBeak, 3), MapQuery(beak, 3), 0.05);
    MapQuery bottomBeak = smoothMax(MapQuery(cutBeak, 3), MapQuery(beak, 3), 0.07);
    
   // res = smoothMin(res, MapQuery(cutBeak, 4), 0.01);
    res = smoothMin(res, topBeak, 0.01);
    res = smoothMin(res, bottomBeak, 0.01);

    vec3 mirrorPZ = p;
    mirrorPZ.z = abs(mirrorPZ.z);
    
    vec3 legPos = bodyPos + vec3(-0.7, -0.2, 0.34);

    vec3 kneePos = mix(legPos, footPos, 0.5) + vec3(0.6,-0.1,0.0);
    
    vec3 toeOffsets[4] = vec3[4](vec3(0.35, -0.1, 0.0),
                           vec3(-0.2, -0.1, 0.2),
                           vec3(-0.5, -0.1, 0.0),
                           vec3(-0.2, -0.1, -0.2));
    
    res = smoothMin(res,
                    MapQuery(roundCone(mirrorPZ, legPos, kneePos, 0.2 + weight * 0.2, 0.1 + weight * 0.1),
                    2), 0.01);
    
    res = smoothMin(res,
                    MapQuery(roundCone(mirrorPZ, kneePos, footPos, 0.13, 0.1),
                    2), 0.1);

    for (int i = 0 ; i < 4; ++i) {
        res = smoothMin(res,
                        MapQuery(roundCone(mirrorPZ, footPos, footPos + toeOffsets[i], 0.06, 0.04),
                        2), 0.04);
    }
    
    // tail
    vec3 tailBonePos = bodyPos + vec3(lowerBodyWidth, 0.0, 0.0);
    res = smoothMin(res, MapQuery(roundCone(p, bodyPos, tailBonePos, 1.0, 0.3), 2), 0.2);

    vec3 tailPos = tailBonePos + vec3(1.3,0.0, 0.0);

    float cutTailFeather = feather(p, tailBonePos, tailPos, 0.4, 0.2, vec3(0.0, 0.2, 0.0), 0.02);
    res = smoothMin(res, MapQuery(cutTailFeather, 2), 0.01);
    
    vec3 tailVec = vec3(cos(tailAngle), sin(tailAngle), 0.0);
    
    vec3 tailCovertStartPos = tailBonePos;
    vec3 tailCovertEndPos = tailCovertStartPos + tailLength * tailVec;

    cutTailFeather = feather(p, tailCovertStartPos, tailCovertEndPos, 0.5 + 0.1 * tailSpread, tailSpread, vec3(0.0, 0.6, 0.0), 0.02);
    res = smoothMin(res, MapQuery(cutTailFeather, 2), 0.01);

    
    // Wings
    vec3 shoulderPos = mix(bodyPos, neckStartPos, 0.9);
    shoulderPos.y += 0.2;
    shoulderPos.z += mix(lowerBodyWidth, breastWidth, 0.9) * 0.6;
    vec3 wingEndPos = mix(bodyPos, neckStartPos, 0.01);
    wingEndPos.z += lowerBodyWidth;
    
    float wing = feather(mirrorPZ, shoulderPos,
                         wingEndPos, 0.9, 0.7,
                         vec3(0.0, 0.2, 0.4), 0.01);

    res = smoothMin(res, MapQuery(wing, 2), 0.01);

    vec3 wing2Dir = 2.1 * normalize(vec3(2.4, -1.0, lowerBodyWidth * 0.8));
    vec3 wing2EndPos = wingEndPos + wing2Dir;

    float wing2 = feather(mirrorPZ, shoulderPos,
                          wing2EndPos, 0.6, 0.2,
                         vec3(0.0, 0.1, 0.1), 0.01);

    res = smoothMin(res, MapQuery(wing2, 4), 0.01);

    return res;
    
}

MapQuery boundedMap(vec3 p)
{
    MapQuery boundingBox = MapQuery(sphere(p, 8.04), 0);
    if(boundingBox.dist < 0.001) {
        return map(p);
    }
    return boundingBox;

}

vec3 calcNormals(vec3 p)
{
    float epsilon = 0.00001;
    return normalize(vec3(boundedMap(p + vec3(epsilon, 0.0, 0.0)).dist - boundedMap(p - vec3(epsilon, 0.0, 0.0)).dist,
                          boundedMap(p + vec3(0.0, epsilon, 0.0)).dist - boundedMap(p - vec3(0.0, epsilon, 0.0)).dist,
                          boundedMap(p + vec3(0.0, 0.0, epsilon)).dist - boundedMap(p - vec3(0.0, 0.0, epsilon)).dist));
    
}

RaycastQuery raycast(vec3 origin, vec3 dir, int maxSteps)
{
    float t = 0.0;

    for(int i = 0; i < maxSteps; ++i)
    {
        vec3 p = origin + t * dir;
        MapQuery query = boundedMap(p);

        if (abs(query.dist) < 0.001) {
            return RaycastQuery(true, p, query.material);
        }
        
        t += query.dist;
        if(t > 60.0) {
            return RaycastQuery(false, vec3(0.0), 0);

        }
    }
    
    return RaycastQuery(false, vec3(0.0), 0);
}

float softShadow(vec3 origin, vec3 dir, float minT, float maxT, float k)
{
    float res = 1.0;
    float ph = 1e20;

    for(float t = minT; t < maxT; )
    {
        vec3 p = origin + t * dir;
        MapQuery query = map(p);
        if (abs(query.dist) < 0.0001) {
            return 0.0;
        }
        
        res = min( res, k * query.dist / t );
        t += query.dist;

    }
    
    return res;

}

float flower(vec2 p, float r, float numPetals, float petalSize, float rotation)
{
    float angle = atan(p.y, p.x) + rotation;
    float rPetals = petalSize * (r + abs(cos(numPetals * angle)));
    return length(p) - rPetals;
}

float circle2d( vec2 p, float r )
{
    return length(p) - r;
}

float box2d( in vec2 p, in vec2 b )
{
    vec2 d = abs(p)-b;
    return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}

float orientedBox2d( in vec2 p, in vec2 a, in vec2 b, float th )
{
    float l = length(b-a);
    vec2  d = (b-a)/l;
    vec2  q = (p-(a+b)*0.5);
          q = mat2(d.x,-d.y,d.y,d.x)*q;
          q = abs(q)-vec2(l,th)*0.5;
    return length(max(q,0.0)) + min(max(q.x,q.y),0.0);
}

void main() {
    float modTime = mod(u_Time, 100.0 * pi);

    float fov = 22.5f;
    float len = distance(u_Ref, u_Eye);
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 right = normalize(cross(look, u_Up));
    float aspect = u_Dimensions.x / u_Dimensions.y;
    vec3 v = u_Up * len * tan(fov);
    vec3 h = right * len * aspect * tan(fov);

    vec3 p = u_Ref + fs_Pos.x * h + fs_Pos.y * v;
    vec3 dir = normalize(p - u_Eye);
    
    vec3 lightPos = vec3(1.0, 0.6, -20.0);
    
    PointLight[3] pointLights;
    pointLights[0] = PointLight(vec3(1.0, 20.0, -50.0), 0.9 * vec3(1.08,1.05,1.06), true);
    pointLights[1] = PointLight(vec3(-100.0, 0.6, 6.0), 0.75 * vec3(0.2,0.3,0.38), false);
    pointLights[2] = PointLight(vec3(80.0, 0.6, 4.0), 0.77 * vec3(0.2,0.3,0.4), false);

    RaycastQuery query = raycast(u_Eye, dir, 70);
    float a = getBias((fs_Pos.y + 1.0) * 0.5, 0.68);
    
    // Clear color
    vec3 albedo = mix(vec3(0.58,0.6,0.72), vec3(0.92,0.95,0.96), a);
    
    /*vec2 pos_uv = fs_Pos;
    pos_uv.y *= aspect;
    Material m = backgroundPattern(pos_uv);
    if(flower(fs_Pos.xy, 0.5, 3.0, 0.3, 1.0) < 0.001) {
    }
    albedo = m.color;

    vec3 backgroundNormal = calcBackgroundNormals(fs_Pos);
    vec3 lightBackground = normalize(vec3(1.0, 0.0, 1.0));
    float diffuseBackground = clamp(dot(backgroundNormal, lightBackground), 0.0, 1.0);
    vec3 col = diffuseBackground* albedo  ;*/
    
    vec3 col = albedo;
    if(query.intersected)
    {
        col = vec3(0.0);
        vec3 normal = calcNormals(query.isect);
        vec3 tangent = normalize(cross(vec3(0,1,0),normal));
        vec3 bitangent = normalize(cross(normal, tangent));

        if(query.material == 0) {
            albedo = vec3(1.0,0.0,0.0);
        } else if(query.material == 1) {
            albedo = vec3(0.0,1.0,0.0);
        } else if(query.material == 2) {
            albedo = vec3(0.0,0.0,1.0);
        } else if(query.material == 3) {
            albedo = vec3(1.0,0.0,1.0);
        }
        
        mat3 tbn = mat3(tangent, bitangent, normal);
        vec3 viewVec = normalize(query.isect - u_Eye.xyz);
        float kd = 1.0;
        float ks = 1.0;
        float cosPow = 28.0;

        for (int i = 0; i < 1; ++i) {
            vec3 lightVec = normalize(pointLights[i].position - query.isect);
            vec3 h = normalize(lightVec - viewVec);
            float diffuse = clamp(dot(normal, lightVec), 0.0, 1.0);
            float specularIntensity = max(pow(max(dot(h, normal), 0.f), cosPow), 0.f);
            
            float shadow = 1.0;
            if (pointLights[i].castsShadow) {
                shadow = softShadow(query.isect + normal * 0.04, lightVec, 0.02, 4.5, 32.0);
            }
            
            vec3 lightIntensity = 0.3 + shadow * pointLights[i].color * clamp(kd * diffuse + ks * specularIntensity, 0.0, 2.7);
            col += lightIntensity * albedo;
        }
        
        // Diffuse Light
        col += vec3(0.20, 0.21, 0.23) * albedo;
    }
        
    out_Col = vec4(col, 1.0);
    //out_Col = vec4(fs_Pos + 1.0, 0.0, 1.0);
}
