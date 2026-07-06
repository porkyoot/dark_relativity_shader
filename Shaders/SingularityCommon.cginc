#ifndef SINGULARITY_COMMON_INCLUDED
#define SINGULARITY_COMMON_INCLUDED

#include "UnityCG.cginc"

struct appdata
{
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct v2f
{
    float4 pos : SV_POSITION;
    float4 grabPos : TEXCOORD0;
    float3 worldPos : TEXCOORD1;
    float3 normalWorld : TEXCOORD3;
    float4 screenCenter : TEXCOORD4;
    float3 localPos : TEXCOORD6;
    float distToCenter : TEXCOORD7;
    float worldRs : TEXCOORD8;
    float cosTheta_H : TEXCOORD9;
    float theta_H : COLOR0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

// Uniforms
float _RealRadius;
float _DistortionStrength;
float _DistortionPower;
float _SpeedOfLight;
float _RotationVelocity;
float _FringeWidth;
float _FringeStrength;

// Exposed Advanced Parameters
float _HorizonLensingLimit;
float _MaxDeflectionAngle;
float _ScreenBorderBlendWidth;

inline float3 GetEyePos()
{
    return mul(unity_CameraToWorld, float4(0.0, 0.0, 0.0, 1.0)).xyz;
}

inline float GetMeshRadius()
{
    // Compute scale-independent world-space radius of the sphere mesh
    return length(float3(unity_ObjectToWorld._m00, unity_ObjectToWorld._m10, unity_ObjectToWorld._m20)) * 0.5;
}

inline v2f vert_common(appdata v)
{
    v2f o;
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_OUTPUT(v2f, o);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    
    o.pos = UnityObjectToClipPos(v.vertex);
    o.grabPos = ComputeGrabScreenPos(o.pos);
    o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
    o.normalWorld = UnityObjectToWorldNormal(v.normal);
    
    float3 centerWorld = unity_ObjectToWorld._m03_m13_m23;
    o.screenCenter = ComputeGrabScreenPos(UnityWorldToClipPos(centerWorld));
    o.localPos = v.vertex.xyz;
    
    float3 eyePos = GetEyePos();
    float distToCenter = distance(eyePos, centerWorld);
    float meshRadius = GetMeshRadius();
    float worldRs = meshRadius * saturate(_RealRadius / 0.5);
    
    float cosTheta_H = 0.0;
    
    #if defined(_ANALYTICMETRIC_BLACKHOLE)
        if (distToCenter >= worldRs * 1.5)
        {
            float sinTheta_H = (2.598076 * worldRs) / (distToCenter * sqrt(max(0.0001, 1.0 - worldRs / distToCenter)));
            cosTheta_H = sqrt(max(0.0, 1.0 - saturate(sinTheta_H * sinTheta_H)));
        }
        else
        {
            // Smoothly expand the shadow to cover the entire sky (cosTheta_H -> -1.0) as we fall to the center
            cosTheta_H = (distToCenter / max(worldRs * 1.5, 0.0001)) - 1.0;
        }
    #else
        // Ellis Wormhole throat size (no spatial curvature magnification)
        if (distToCenter >= worldRs)
        {
            float sinTheta_H = worldRs / max(distToCenter, 0.0001);
            cosTheta_H = sqrt(max(0.0, 1.0 - sinTheta_H * sinTheta_H));
        }
        else
        {
            cosTheta_H = 0.0; // Throat covers entire forward view when inside
        }
    #endif
    
    float theta_H = acos(clamp(cosTheta_H, -1.0, 1.0));
    
    o.distToCenter = distToCenter;
    o.worldRs = worldRs;
    o.cosTheta_H = cosTheta_H;
    o.theta_H = theta_H;
    
    return o;
}

// Unified Doppler Factor based on precomputed LUT values
inline float GetUnifiedDoppler(float3 rayDir, float3 singularityDir, float3 perpendicular, float distToCenter, float worldRs)
{
    float gravPotential = worldRs / max(distToCenter, 0.0001);
    float cosTheta = dot(rayDir, singularityDir);
    
    // Gravitational redshift (relaxed scaling)
    float c = max(_SpeedOfLight, 0.001);
    float z_g = gravPotential * (30.0 / c); // Relaxed multiplier
    // Clamp D_grav to a much wider range to allow intense color shifts (blueshift/redshift)
    // without causing glare, since beaming brightness is separately clamped in ApplyBackgroundDoppler.
    float D_grav = clamp(exp(-cosTheta * z_g), 0.05, 15.0);
    
    // Rotational frame-dragging shift: Local Y axis of the mesh is the spin axis
    float3 localY = normalize(float3(unity_ObjectToWorld._m01, unity_ObjectToWorld._m11, unity_ObjectToWorld._m21));
    float3 spinDir = normalize(cross(singularityDir, localY + float3(1e-6, 0.0, 0.0)));
    
    float theta = acos(clamp(cosTheta, -1.0, 1.0));
    
    float cosTheta_H;
    if (distToCenter >= worldRs)
    {
        float sinTheta_H_d = worldRs / max(distToCenter, 0.0001);
        cosTheta_H = sqrt(max(0.0, 1.0 - sinTheta_H_d * sinTheta_H_d));
    }
    else
    {
        cosTheta_H = - (1.0 - distToCenter / max(worldRs, 0.0001));
    }
    float theta_H = acos(clamp(cosTheta_H, -1.0, 1.0));
    
    // Calculate rotation natively. _RotationVelocity is a fraction of c (-0.99 to 0.99)
    // We decay it as a power of 1.5 so the visible accretion area retains some velocity
    float angleDecay = pow(max(theta_H, 0.0001) / max(theta, 0.0001), 1.5);
    float distanceDecay = sqrt(worldRs / max(distToCenter, 0.0001));
    float v_frac = _RotationVelocity * angleDecay * distanceDecay;
    
    // Relativistic Doppler from rotation
    float v_proj = dot(perpendicular, spinDir) * v_frac;
    
    // Relaxed rotational Doppler to keep colors highly saturated instead of flaring to white
    float beta = clamp(v_proj * 0.8, -0.75, 0.75);
    
    // Doppler shift formula: D = sqrt((1 + beta) / (1 - beta))
    float spinDopplerFactor = sqrt((1.0 + beta) / (1.0 - beta));
    
    return D_grav * spinDopplerFactor;
}

inline half3 RGBtoHSV(half3 c)
{
    half4 K = half4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    half4 p = lerp(half4(c.bg, K.wz), half4(c.gb, K.xy), step(c.b, c.g));
    half4 q = lerp(half4(p.xyw, c.r), half4(c.r, p.yzx), step(p.x, c.r));

    half d = q.x - min(q.w, q.y);
    half e = 1.0e-10;
    return half3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

inline half3 HSVtoRGB(half3 c)
{
    half4 K = half4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    half3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}


float _BeamingIntensity;

inline half3 ApplyBackgroundDoppler(half3 rgb, float doppler)
{
    half3 col = rgb;
    
    if (doppler > 1.0)
    {
        // Blueshift: Maps energy towards blue
        half s = saturate(1.0 - 1.0 / doppler);
        
        half3x3 M_blue = half3x3(
            1.0 - s, 0.0,     0.0,
            s,       1.0 - s, 0.0,
            s * 0.5, s,       1.0
        );
        col = mul(M_blue, rgb);
        
        // Desaturate at higher blueshifts to represent ultraviolet white glow
        col = lerp(col, dot(col, half3(0.299, 0.587, 0.114)), s * 0.5);
    }
    else
    {
        // Redshift: Maps energy towards red
        half s = saturate(1.0 - doppler);
        
        half3x3 M_red = half3x3(
            1.0,     s,       s * 0.5,
            0.0,     1.0 - s, s,
            0.0,     0.0,     1.0 - s
        );
        col = mul(M_red, rgb);
    }
    
    // Relativistic Beaming: power-of-three intensity scaling (clamped to prevent glare)
    float rawBeaming = pow(max(doppler, 0.0001), 3.0);
    float clampedBeaming = clamp(rawBeaming, 0.1, 4.0);
    float beaming = lerp(1.0, clampedBeaming, _BeamingIntensity);
    return col * (half)beaming;
}

inline half3 CheckOtherSingularity(half3 originalColor, float3 eyePos, float3 ray_Lensed, float4 otherPos, float otherRadius, float otherType, samplerCUBE wormholeSkybox, half4 wormholeSkybox_HDR, float skyboxBrightness)
{
    if (otherType > 0.5 && otherRadius > 0.001)
    {
        float3 O = eyePos - otherPos.xyz;
        float B = dot(O, ray_Lensed);
        float C = dot(O, O) - otherRadius * otherRadius;
        float D = B * B - C;
        if (D >= 0.0)
        {
            float t1 = -B - sqrt(D);
            float t2 = -B + sqrt(D);
            float t = (C < 0.0) ? 0.0 : ((t1 > 0.0) ? t1 : t2);
            
            if (t > 0.0)
            {
                if (otherType < 1.5)
                {
                    // Black Hole: render as a black sphere
                    return half3(0,0,0);
                }
                else
                {
                    // Wormhole: render as a sphere showing Universe B skybox
                    half4 otherSky = texCUBElod(wormholeSkybox, float4(ray_Lensed, 0.0));
                    return DecodeHDR(otherSky, wormholeSkybox_HDR) * skyboxBrightness;
                }
            }
        }
    }
    return originalColor;
}

#endif // BLACK_HOLE_COMMON_INCLUDED
