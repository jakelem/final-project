#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

float pi = 3.14159265359;
float degToRad = 3.14159265359 / 180.0;
int bodyMaterial = 0;
int headMaterial = 1;
int wingMaterial = 2;
int legMaterial = 3;
int tailMaterial = 4;
int beakMaterial = 5;
int eyeMaterial = 6;

vec3 clearColor = vec3(0.96,0.95,0.89);

vec3 headPos = vec3(0.0);
vec3 wingPos = vec3(0.0);
vec3 eyePos = vec3(0.0);
vec3 bodyPos = vec3(0.0);

vec3 breastPos = vec3(0.0);
vec3 tailBonePos = vec3(0.0);
float lowerBodyWidth = 0.0;
vec3 footPos = vec3(0.0, -1.0, 0.0);
float legHeight = 0.0;

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

struct MixedMaterial
{
    int materialIdA;
    int materialIdB;
    float lerpVal;
};

struct PointLight
{
    vec3 position;
    vec3 color;
    bool castsShadow;
};

float hash3(vec3 v)
{
    return fract(sin(dot(v, vec3(123.5, 258.35, 532.5))) * 3985.3);
}

vec2 hash2vec2(vec2 v) {
    return fract(vec2(
                 sin(dot(v, vec2(123.5, 258.35))) * 3985.3,
                 sin(dot(v, vec2(825.3, 482.31))) * 8493.4
                 )
                 );
}


float hash1(float v)
{
    return fract(sin(v * 323359.34829489 + v * 9852.555));
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


float egg2d(  vec2 p, float ra, float rb )
{
    const float k = sqrt(3.0);
    p.x = abs(p.x);
    float r = ra - rb;
    return ((p.y<0.0)       ? length(vec2(p.x,  p.y    )) - r :
            (k*(p.x+r)<p.y) ? length(vec2(p.x,  p.y-k*r)) :
                              length(vec2(p.x+r,p.y    )) - 2.0*r) - rb;
}

float sdfFeatherTexture(vec2 uv, float freq, float amp, float radius) {
    float res = 0.0;
    vec2 period = vec2(1.f / freq);
    float sdf = 100.0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            // Get the coordinate of bottom left corner of cell
            vec2 cellNum = floor((uv + period * vec2(i, j)) / period);
            
            // Determine what (u,v) is in the local space of the neighboring cell.
            vec2 repUv = mod(uv + period * vec2(i, j), period) - period * vec2(i, j);
            
            // Egg can at most extend up to the bounds of the 3x3 grid around floor(uv)
            float egg = egg2d(repUv + hash2vec2(cellNum) * 0.03, amp + hash2vec2(cellNum).x * 0.04, 0.0);
            if(egg < 0.001) {
                sdf = egg;
            }
        }
    }

    
    // We displace by period so that our repeated coordinate domain goes from -period -> period rather than 0 -> 2*period
  //  vec2 repUv =  mod(uv + period, period) - period * 0.5;
  // sdf = egg2d(repUv, 0.06, 0.0);
    //uv = mod(uv * 3.0, 3.0);
    vec2 cellNum = floor((uv) / period);
    float r= length(cellNum);
   // if(length(cellNum) < 7.0) {
        if(sdf < 0.0) {
            res = clamp(1.0 + sdf * 9.0, 0.0, 1.0);
        } else {
            res = -1.0;
        }
        // clamp(1.0 - abs(sdf * sdf * 200.0), 0.0, 1.0);
    //} else {
        //res = -1.0;
    //}
    return res;
}

float sinFeatherTexture(vec2 uv, float freq, float amp) {
    float res = 1.0;
    float waveInput = freq * uv.x;
    float waveNum = float( floor(waveInput / (2.0 * pi)));
    waveInput = freq * uv.x;
    //float featherSpacingV = 4.0;
    float waveoffset = abs(1.0 * sin(waveInput));
    
    float featherwave = hash1(waveNum * 2030.042) * 20.0
    + uv.y * amp - waveoffset;
    
  //  featherwave *= reverseFeather[i];
    float cell = floor(featherwave); //+ floor(waveoffset);
    float rand = 0.1 + hash3(vec3(cell, cell, cell));
    //rand *= floor(3.0 * sin(freqAmp * isectHatch.x));
    
    float f = fract(featherwave); //abs(sin(hatchDir * 20.0 - waveoffset));
    f = smoothstep(0.0, 0.3, f);
    
    // Featherwave is the cutoff for the sin function
    //if(featherwave < 0.0) {
        f = clamp(f + 0.2, 0.0, 1.0);
        res = f * waveoffset;
        
        
    //} else {
       // res = -1.0;
    //}
    
    return res;
}

Material eyePattern(vec3 p, vec3 normal) {
    Material res;
    res.color = vec3(1.0);
    return res;
}

Material featherPattern(vec3 p, vec3 normal, int i) {
    Material res;
    float fbm = fbm3(p, 5, 2.0, 6.0, 0.5, 2.0).x;
    // Divide bird into sections based on normal direction
    // Prevent hairy ball effect
    
//        if(abs(normal.x) > 0.7 - 0.01 * fbm) {
//            hatchDir = isectHatch.z;
//        }
    if(abs(normal.y) > 0.7 - 0.01 * fbm) {
        //hatchDir = isectHatch.z;
    }
    vec3 isectHatch = p;

    float[5] featherLayerFreqs = float[5](10.0, 6.8, 13.5, 13.4, 13.4);
    float[5] featherLayerAmps = float[5](10.0, 6.8, 13.5, 4.4, 4.4);

    float[5] featherLayerRotations = float[5](-20.0, -50.0, -150.0, -50.0, -200.0);
    
    // TODO: change to vec3s
    vec3[5] featherLayerOffsets = vec3[5](wingPos - vec3(5.4,6.0,0.0),
                                          wingPos - vec3(5.4,5.5,0.0),
                                          wingPos - vec3(0.6,-0.6,0.0),
                                          wingPos - vec3(7.9,6.4,0.0),
                                          headPos  - vec3(0.2,-1.3,0.0));
    int[5] axis = int[5] (1, 1, 1, 1, 2);
    float albedoFactor = 1.0;
    int[5] featherType = int[5] (0, 0, 1, 1, 0);
    
    vec3[5] colors = vec3[5](vec3(0.4, 0.2, 0.1),
                             vec3(0.1, 0.1, 0.1),
                             vec3(0.12, 0.1, 0.1),
                             vec3(0.12, 0.1, 0.11),
                             vec3(0.6, 0.6, 0.57));
    

    
   // for(int i = 0; i < 5; ++i) {
        isectHatch = p;
        isectHatch -= featherLayerOffsets[i];
        isectHatch.z = abs(isectHatch.z);
        mat3 rot = rotationAxisAngle(normalize(vec3(0.0, 0.0, 1.0)), featherLayerRotations[i] * degToRad);
        isectHatch = rot * isectHatch;
        float hatchDir = isectHatch[axis[i]];
        vec2 uv = vec2(hatchDir + fbm * 0.03, isectHatch.x);
        //uv = query.isect.xy;

        float f = 1.0;
        if(featherType[i] == 0) {
            f = sinFeatherTexture(uv, featherLayerFreqs[i], featherLayerAmps[i]);
        } else {
            f = sdfFeatherTexture(uv, 5.0, 0.2, 3.0);
        }
        
        if(f >= 0.0) {
            f = clamp(f + 0.2, 0.0, 1.0);
            res.kd = f;
            res.color = colors[i];
        }

        /*
        float freqAmp = 3.0 * float(i + 1);
        
        float waveInput = freqAmp * isectHatch.x;
        float waveNum = float( floor(waveInput / (2.0 * pi)));
        waveInput = freqAmp * isectHatch.x;
        
        float waveoffset = abs(1.0 * sin(waveInput));
        
        float featherwave = hash1(waveNum * 2030.042) * 2.0
        + fbm * 0.1 + hatchDir * featherSpacingV - waveoffset;
        featherwave *= reverseFeather[i];
        float cell = floor(featherwave); //+ floor(waveoffset);
        float rand = 0.1 + hash3(vec3(cell, cell, cell));
        //rand *= floor(3.0 * sin(freqAmp * isectHatch.x));
        
        float f = fract(featherwave); //abs(sin(hatchDir * 20.0 - waveoffset));
        f = smoothstep(0.0, 0.3 + float(i) * 0.3, f);
        
        // Featherwave is the cutoff for the sin function
        if(featherwave > 20.0) {
            f = clamp(f + 0.2, 0.0, 1.0);
            albedoFactor = f;
        }*/
        
    //}
    
//    float f = sdfFeatherTexture(query.isect.xy, 4.0, 0.1);
//    if(f >= 0.0) {
//        f = clamp(f + 0.2, 0.0, 1.0);
//        albedoFactor = f;
//    }

    
    //albedoFactor = mix(1.0, albedoFactor, abs(normal.z));
    
    return res;
}

Material getMaterialForId(int id, vec3 p, vec3 normal) {
    Material res;
    return featherPattern(p, normal, id);

    if (id == 0) {
        res.color = vec3(0.9, 0.1, 0.1);

        //return featherPattern(p, normal, id);
    } else if (id == 1) {
        res.color = vec3(0.1, 0.9, 0.1);

        //return featherPattern(p, normal, id);
    } else if (id == 2) {
        res.color = vec3(0.1, 0.1, 0.9);
    } else if (id == 3) {
        res.color = vec3(0.2, 0.2, 0.2);
    } else if (id == 4) {
        res.color = vec3(0.8, 0.8, 0.2);
    }
    
    return res;
}

Material calcMixedMaterial(MixedMaterial mat, vec3 p, vec3 normal) {
    if(mat.materialIdA == mat.materialIdB) {
        return getMaterialForId(mat.materialIdA, p, normal);
    }
    Material res;
    Material a = getMaterialForId(mat.materialIdA, p, normal);
    Material b = getMaterialForId(mat.materialIdB, p, normal);

    res.color = mix(a.color, b.color, mat.lerpVal);
    res.ks = mix(a.ks, b.ks, mat.lerpVal);
    res.kd = mix(a.kd, b.kd, mat.lerpVal);
    res.cosPow = mix(a.cosPow, b.cosPow, mat.lerpVal);
    res.displacement = mix(a.displacement, b.displacement, mat.lerpVal);

    return res;
}

MixedMaterial matchMaterial(MixedMaterial mat) {
    MixedMaterial res = mat;
    if (mat.lerpVal < 0.001) {
        res.materialIdB = mat.materialIdA;
    }
    if (mat.lerpVal > 0.999) {
        res.materialIdA = mat.materialIdB;
    }
    
    return res;
}

MixedMaterial mixMaterials(MixedMaterial mixedMaterial,
                               int materialIdC,
                               float lerpVal) {
    MixedMaterial res;
    if(mixedMaterial.lerpVal >= 0.5) {
        res.materialIdA = mixedMaterial.materialIdB;
        res.materialIdB = materialIdC;
        res.lerpVal = lerpVal;
    }
    
    if(mixedMaterial.lerpVal < 0.5) {
        res.materialIdA = mixedMaterial.materialIdA;
        res.materialIdB = materialIdC;
        res.lerpVal = lerpVal;

    }
    
    if(mixedMaterial.lerpVal > 0.0 && mixedMaterial.lerpVal < 1.0) {
        if (lerpVal <= 0.4) {
            return mixedMaterial;
        }
        
    }

    return res;

}

Material getMaterialAtPoint(RaycastQuery query, vec3 normal) {
    vec3 p = query.isect;
    float fbm = 0.02 * fbm3(p, 3, 1.0, 1.0, 0.5, 2.0).x;
    MixedMaterial res;
    vec3 mirrorPZ = p;
    mirrorPZ.z = abs(mirrorPZ.z);

    res.materialIdA = 0;
    res.materialIdB = 1;
    res.lerpVal = 1.0;

    if(query.material == wingMaterial) {
        float distToWing = smoothstep(0.3, 0.4, distance(wingPos, mirrorPZ) * 0.3 + fbm);
        res = mixMaterials(res, 3, 1.0 - distToWing);
        distToWing = smoothstep(0.3, 0.33, distance(wingPos + vec3(0.5, 0.3, 0.0), mirrorPZ) * 0.3 + fbm);
        res = mixMaterials(res, 4, 1.0 - distToWing);
    }
    
    float distToHead = smoothstep(0.2, 0.5, distance(headPos, p) * 0.2 + fbm);
    res = mixMaterials(res, 0, 1.0 - distToHead);

    float breastDist = distance(breastPos, p) * 0.2;
    float distToBreast = smoothstep(0.2, 0.21, distance(breastPos, p) * 0.2 + 4.0 * fbm);
    res = mixMaterials(res, 3, 1.0 - distToBreast);
        
    // Crown
    distToHead = smoothstep(0.2, 0.3, distance(headPos + vec3(0.0, 0.9, 0.0), p) * 0.4 + fbm);
    res = mixMaterials(res, 4, 1.0 - distToHead);

    // Nape
    distToHead = smoothstep(0.2, 0.3, distance(headPos + vec3(0.6, 0.0, 0.0), p) * 0.45 + fbm);
    res = mixMaterials(res, 4, 1.0 - distToHead);

    // Rump
    float distToTailbone = smoothstep(0.4, 0.5, distance(tailBonePos + vec3(0.6, 0.0, 0.0), p) * 0.4 + fbm);
    res = mixMaterials(res, 4, 1.0 - distToTailbone);

    float distToEye = smoothstep(0.3, 0.4 , distance(eyePos, mirrorPZ) * 0.98 + fbm * 9.0);
    res = mixMaterials(res, 4, 1.0 - distToEye);
    
    if(query.material == bodyMaterial) {
        float distToWing = smoothstep(0.3, 0.4, distance(wingPos, mirrorPZ) * 0.7 + fbm);
        res = mixMaterials(res, 2, 1.0 - distToWing);
    }
    
    float footDist = smoothstep(0.6, 0.8, distance(footPos, mirrorPZ) / legHeight + fbm * 3.0);
    res = mixMaterials(res, 2, 1.0 - footDist);


    if(query.material == eyeMaterial) {
        float distToWing = smoothstep(0.3, 0.4, distance(eyePos, mirrorPZ) * 0.7 + fbm);
        res = mixMaterials(res, 2, 1.0 - distToWing);
    }
    return calcMixedMaterial(res, p, normal);
}



MapQuery map(vec3 p)
{
    headPos = vec3(1.0);

    float weight = u_BirdParameters[0];
    float neckLength = u_BirdParameters[1];
    float neckWidth = u_BirdParameters[2];
    float headSize = u_BirdParameters[3];
    float tailAngle = u_BirdParameters[4];
    float tailSpread = u_BirdParameters[5];
    float tailLength = u_BirdParameters[6];
    float height = u_BirdParameters[7];
    legHeight = height;
    float skullLength = u_BirdParameters[8];
    float beakHeight = u_BirdParameters[9];
    float beakLength = u_BirdParameters[10];

    vec3 groundPos = vec3(0.0, -1.0, 0.0);
    vec3 footPos = groundPos + vec3(0.0, 0.0, 0.4);
    bodyPos = groundPos + vec3(0.0, height, 0.0);

    lowerBodyWidth = weight * 0.9 + 0.1;
    float breastWidth = weight * 1.2;
    float upperNeckWidth = neckWidth * weight * 0.9;
    float lowerNeckWidth = mix(upperNeckWidth, breastWidth, 0.4);
    float headWidth = mix(upperNeckWidth, headSize * 0.5 + weight * 0.5, 0.6);

    vec3 neckVector = vec3(-0.5, 0.86, 0.0);

    
    //TODO: replace offset with parameters
    // Puff out more with weight
    vec3 neckStartPos = bodyPos + vec3(-1.0 - weight * 0.1, 0.7, -0.0);
    // Body
    MapQuery res = MapQuery(roundCone(p, bodyPos, neckStartPos, lowerBodyWidth, breastWidth), bodyMaterial);
    breastPos = neckStartPos;
    breastPos.x -= breastWidth;
    // Body details
    //vec3 sidesPos = bodyPos + vec3(-1.0, 1.0,-0.4);
   // res = smoothMin(res, MapQuery(sphere(p - sidesPos, 0.5), 1), 0.6);
    
    // Neck to head
    //TODO: replace offset with parameters
    vec3 neckEndPos = neckStartPos + neckLength * neckVector;
    res = smoothMin(res, MapQuery(roundCone(p, neckStartPos, neckEndPos, lowerNeckWidth, upperNeckWidth), headMaterial), 0.3);

    vec3 headStartPos = neckEndPos + vec3(-0.3,0.4, 0.0);
    vec3 headEndPos = headStartPos + vec3(-0.45 - skullLength, 0.0, 0.0);
    
    headPos = mix(headStartPos, headEndPos, 0.5);
    float frontalSkull = mix(headWidth, beakHeight, 0.6);
    vec3 beakPos = headEndPos + vec3(-frontalSkull, 0.1, 0.0);

    vec3 beakTipPos = beakPos + vec3(-beakLength, 0.0, 0.0);

    res = smoothMin(res, MapQuery(roundCone(p, headStartPos, headEndPos, headWidth, frontalSkull), headMaterial), 0.2);

   // vec3 breastPos = bodyPos + vec3(-1.0, 1.0,0.0);
   // res = smoothMin(res, MapQuery(sphere(p - breastPos, 1.0), 0), 0.1);

    float beak = roundCone(p, beakPos, beakTipPos, beakHeight, 0.01);
    beak = onion(beak, 0.03);
    
    vec3 midBeak = 0.5 * (beakPos + beakTipPos) - vec3(0.0, beakLength, 0.0);
    
    //float cutBeak = sphere(p - midBeak, max(beakLength, beakHeight));
    float cutBeak = roundCone(p + vec3(0.0, beakHeight, 0.0), beakPos, beakTipPos, beakHeight, beakHeight);

    MapQuery topBeak = smoothMax(MapQuery(-cutBeak, beakMaterial), MapQuery(beak, beakMaterial), 0.05);
    MapQuery bottomBeak = smoothMax(MapQuery(cutBeak, beakMaterial), MapQuery(beak, beakMaterial), 0.07);
    
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
                    legMaterial), 0.01);
    
    res = smoothMin(res,
                    MapQuery(roundCone(mirrorPZ, kneePos, footPos, 0.13, 0.1),
                    legMaterial), 0.1);

    for (int i = 0 ; i < 4; ++i) {
        res = smoothMin(res,
                        MapQuery(roundCone(mirrorPZ, footPos, footPos + toeOffsets[i], 0.06, 0.04),
                        legMaterial), 0.04);
    }
    
    // tail
    tailBonePos = bodyPos + vec3(lowerBodyWidth, 0.0, 0.0);
    res = smoothMin(res, MapQuery(roundCone(p, bodyPos, tailBonePos, 1.0, 0.3), tailMaterial), 0.2);

    vec3 tailPos = tailBonePos + vec3(1.3,0.0, 0.0);

    float cutTailFeather = feather(p, tailBonePos, tailPos, 0.4, 0.2, vec3(0.0, 0.2, 0.0), 0.02);
    res = smoothMin(res, MapQuery(cutTailFeather, tailMaterial), 0.01);
    
    vec3 tailVec = vec3(cos(tailAngle), sin(tailAngle), 0.0);
    
    vec3 tailCovertStartPos = tailBonePos;
    vec3 tailCovertEndPos = tailCovertStartPos + tailLength * tailVec;

    cutTailFeather = feather(p, tailCovertStartPos, tailCovertEndPos, 0.5 + 0.1 * tailSpread, tailSpread, vec3(0.0, 0.6, 0.0), 0.02);
    res = smoothMin(res, MapQuery(cutTailFeather, tailMaterial), 0.01);

    
    // Wings
    vec3 shoulderPos = mix(bodyPos, neckStartPos, 0.9);
    shoulderPos.y += 0.2;
    shoulderPos.z += mix(lowerBodyWidth, breastWidth, 0.98) * 0.6;
    vec3 wingEndPos = mix(bodyPos, neckStartPos, 0.01);
    wingEndPos.z += lowerBodyWidth;
    wingPos = shoulderPos;

    float wing = feather(mirrorPZ, shoulderPos,
                         wingEndPos, 0.9, 0.7,
                         vec3(0.0, 0.2, 0.4), 0.01);

    res = smoothMin(res, MapQuery(wing, wingMaterial), 0.01);

    vec3 wing2Dir = 2.1 * normalize(vec3(2.4, -1.0, lowerBodyWidth * 0.8));
    vec3 wing2EndPos = wingEndPos + wing2Dir;

    float wing2 = feather(mirrorPZ, shoulderPos,
                          wing2EndPos, 0.6, 0.2,
                         vec3(0.0, 0.1, 0.1), 0.01);

    res = smoothMin(res, MapQuery(wing2, wingMaterial), 0.01);

    // Eye
    eyePos = mix(headStartPos, headEndPos, 0.9);
    eyePos.z = -0.36 + headWidth * 1.0;
    eyePos.y += headWidth * 0.2;

    MapQuery eyeQ = MapQuery(sphere(mirrorPZ - eyePos, 0.1), eyeMaterial);
    res = smoothMin(res, eyeQ, 0.05);
    
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

vec3 pigment(vec3 col, float ctrl) {
    vec3 res = vec3(0.0);
    
    if(ctrl < 0.5) {
        float t = max(3.0 - ctrl * 4.0,  0.0);
        res.x = pow(col.x,t);
        res.y = pow(col.y,t);
        res.z = pow(col.z,t);
    } else {
        res = (ctrl - 0.5) * 2.0 * (clearColor - col) + col;
    }
    return res;
}

float cubeField(vec3 p) {
    return hash3(floor(p));
}

float greyscale(vec3 color) {
    return (0.2126*color.x + 0.7152*color.g + 0.0722*color.b);
}

vec2 rotate2D(vec2 v, float angle) {
    mat2 m = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
    return m * v;
}

float crossHatch2D(vec2 uv, float lightIntensity) {
    float res = 1.0;
    float angle = 0.0;
    float[4] thresholds = float[4](1.0, 0.3, 0.2, 0.1);
    
    for(int i = 0; i < 3; ++i) {
        if(lightIntensity <= thresholds[i]) {
            angle += 45.0;
            vec2 isectHatch = rotate2D(uv, degToRad * angle);
            float lines = abs(sin(70.0 * isectHatch.y));
            
            // Edit how thick/thin strokes are
            lines = smoothstep(0.4, 0.9, lines);
            float intervalSize = thresholds[i] - thresholds[i + 1];
            
            // Fade hatching between intervals
            if(lines < 0.5) {
                lines *= smoothstep(thresholds[i + 1] + intervalSize * 0.3,
                                    thresholds[i + 1] + intervalSize * 0.9,
                                    lightIntensity);

            }
            res = min(res, lines);
        }
    }
    
    return res;
}

float crossHatch(vec3 p, vec3 normal, float lightIntensity) {
    float res = 1.0;
    float fbm = fbm3(p, 4, 1.0, 4.0, 0.5, 2.0).x;

    vec3 isectHatch = p;
    isectHatch.y += fbm * 0.06;
    float yLines = crossHatch2D(isectHatch.xy, lightIntensity);//abs(sin(fbm * 3.0 + 70.0 * isectHatch.y));
    yLines += 0.2;
    yLines = mix(1.0, yLines, getBias(abs(normal.z), 0.2));
    
    isectHatch.z += fbm * 0.06;

//    float zLines = crossHatch2D(isectHatch.yz, lightIntensity);
//    zLines = mix(zLines, 1.0, getBias(abs(normal.z), 0.5));
//    zLines = mix(zLines, 1.0, getBias(abs(normal.y), 0.3));
    isectHatch = p;
    isectHatch.x += fbm * 0.06;

    float xLines = crossHatch2D(isectHatch.zx, lightIntensity);
    xLines = mix(xLines, 1.0, getBias(abs(normal.z), 0.3));
   // xLines = mix(1.0, xLines, getBias(abs(normal.y), 0.3));

        //res *= smoothstep(1.0 - lightIntensity, 0.6, lines * zLines);
    res *= smoothstep(0.2, 1.0, yLines * xLines);
    
    
    return res;


}

float worley2d(vec2 uv, float xFreq, float yFreq)
{
    float minDist = 100.0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            //determine the lower left pixel of the current cell
            vec2 cellPos = vec2(floor(uv.x * xFreq) * (1.f/xFreq) + (1.f/xFreq) * float(i),
                                floor(uv.y * yFreq) * (1.f/yFreq) + (1.f/yFreq) * float(j));
            vec2 point = hash2vec2(cellPos);

            //convert random point to coordinate space of cell
            point.x = point.x * 1.f/xFreq + cellPos.x;
            point.y = point.y * 1.f/yFreq + cellPos.y;

            //continue if point is out of bounds
            if (point.x < 0.0 || point.x > 1.0 || point.y < 0.0 || point.y > 1.0) {
                continue;
            }
            minDist = min(minDist, distance(uv, point));
        }
    }
    return minDist;
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
    pointLights[0] = PointLight(vec3(-1.0, 9.0, -5.0), 0.9 * vec3(1.00,0.9,0.98), true);
    pointLights[1] = PointLight(vec3(-100.0, 0.6, 6.0), 0.75 * vec3(0.2,0.3,0.38), false);
    pointLights[2] = PointLight(vec3(80.0, 0.6, 4.0), 0.77 * vec3(0.2,0.3,0.4), false);

    RaycastQuery query = raycast(u_Eye, dir, 70);
    float a = getBias((fs_Pos.y + 1.0) * 0.5, 0.68);
    
    // Clear color

    vec3 albedo = clearColor;
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
    float dilutionFactor = 0.6;
    float cangianteFactor = 0.5;

    
    if(query.intersected)
    {
        col = vec3(0.0);
        vec3 normal = calcNormals(query.isect);
        //vec3 tangent = normalize(cross(vec3(0,1,0),normal));
        //vec3 bitangent = normalize(cross(normal, tangent));

        if(query.material == bodyMaterial || query.material == headMaterial) {
            float distToHead = clamp(distance(headPos, query.isect) * 0.2, 0.0, 1.0);
            albedo = mix(vec3(0.4,0.4,0.42), vec3(0.6,0.0,0.1) , distToHead);

        }
        

        float kd = 1.0;
        float ks = 0.1;

        //Material feather = featherPattern(query.isect, normal);
       // albedo = feather.color;
        //kd = feather.kd;

//        if(query.material == wingMaterial) {
//            //TODO: try offsetting isecthatch by wing position so it's centered during rotation
//            //albedo = mix(vec3(0.4, 0.1, 0.1), vec3(0.6, 0.4, 0.4), feather);
//
//
//        } else if(query.material == legMaterial) {
//            albedo = vec3(0.2,0.2,0.21);
//        } else if (query.material == tailMaterial){
//            albedo = vec3(0.2, 0.0, 0.0);
//        } else if (query.material == beakMaterial){
//            albedo = vec3(0.13, 0.1, 0.1);
//        } else if (query.material == eyeMaterial){
//            Material eye = eyePattern(query.isect, normal);
//            albedo = eye.color;
//            kd = 1.0;
//
//        }
        
        Material mat = getMaterialAtPoint(query, normal);
        albedo = mat.color;
        kd = mat.kd;

        vec3 symIsect = vec3(query.isect.xy, abs(query.isect.z));

        float hatch = crossHatch(symIsect, normal, greyscale(albedo * kd));
        
        // Hatching Pass
        kd *= clamp(0.5 + hatch, 0.0, 1.0);

        //TODO: Watercolor shading model
        // TODO: tie hatching to lighting
        // TODO: Add subtle fbm to substrate to make it look "old"
        //mat3 tbn = mat3(tangent, bitangent, normal);
        vec3 viewVec = normalize(query.isect - u_Eye.xyz);
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
            
            shadow = clamp(shadow + 0.4, 0.0,1.0);
            //vec3 lightIntensity = 0.6 + shadow * pointLights[i].color * clamp(kd * diffuse + ks * specularIntensity, 0.0, 2.7);
            vec3 lightIntensity = 0.3 + pointLights[i].color * kd * shadow + clamp(ks * specularIntensity, 0.0, 1.0);

            //col += lightIntensity * albedo;
            vec3 cc = albedo + pointLights[i].color * lightIntensity * cangianteFactor;
            col =  mix(cc, clearColor, clamp(lightIntensity * dilutionFactor, 0.0,1.0));
            float turb = fbm3(query.isect, 5, 0.6, 1.0, 0.5, 2.0).x;

            //float falloff = dot(-viewVec, normal);
           // col = mix(col, clearColor, falloff);
//            if(falloff > 0.8) {
//                col = vec3(0.1);
//            }
            col = pigment(col, turb);
            
            
        }
        
        //col = mix(albedo, col, feather);
        
        // Diffuse Light
        //col += vec3(0.20, 0.21, 0.23) * albedo;
        

    }
        
    
    //RaycastQuery test = RaycastQuery(true, 5.0 * vec3(fs_Pos, 0.0), 0);
   // col = vec3(0.5) * featherPattern(test, vec3(0.0, 0.0, 1.0));
    
    float fbm = fbm3(fs_Pos.xyy, 5, 2.0, 6.0, 0.5, 2.0).x;
    vec2 inFeather = fs_Pos;
    
    
    //inFeather.x += fbm * 0.01;
    //col = vec3(0.5) * featherTexture(inFeather, 20.0, 9.0);
    //col = vec3(0.1, 0.6, 0.65) *  sdfFeatherTexture(inFeather * 4.0, 8.0, 1.0);
    out_Col = vec4(col, 1.0);
    
    //out_Col = vec4(fs_Pos + 1.0, 0.0, 1.0);
}
