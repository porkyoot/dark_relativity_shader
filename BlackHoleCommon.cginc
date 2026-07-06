#ifndef BLACK_HOLE_COMMON_INCLUDED
#define BLACK_HOLE_COMMON_INCLUDED

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
    
    return o;
}

// Unified Doppler Factor based on precomputed LUT values
inline float GetUnifiedDoppler(float3 rayDir, float3 singularityDir, float3 perpendicular, float distToCenter, float worldRs)
{
    float gravPotential = worldRs / max(distToCenter, 0.0001);
    float cosTheta = dot(rayDir, singularityDir);
    
    // Gravitational redshift
    float c = max(_SpeedOfLight, 0.001);
    float z_g = gravPotential * (100.0 / c);
    float D_grav = exp(-cosTheta * z_g);
    
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
    
    // We multiply by an extra factor of 2.0 to make the color shift very visible in the deformation
    float beta = clamp(v_proj * 2.0, -0.99, 0.99);
    
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
    
    // Relativistic Beaming: power-of-three intensity scaling
    float beaming = pow(max(doppler, 0.0001), 3.0);
    return col * (half)beaming;
}

#endif // BLACK_HOLE_COMMON_INCLUDED
