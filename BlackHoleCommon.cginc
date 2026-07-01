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
float _ChromaticAberration;
float _RotationSpeed;
float _RedshiftFactor;
float _FringeWidth;
float _FringeStrength;
float _UseDepthOcclusion;

// Exposed Advanced Parameters
float _HorizonLensingLimit;
float _MaxDeflectionAngle;
float _ScreenBorderBlendWidth;
float4 _FringeBaseColor;

inline float3 GetEyePos()
{
    return mul(unity_CameraToWorld, float4(0.0, 0.0, 0.0, 1.0)).xyz;
}

inline float GetMeshRadius()
{
    // Compute scale-independent world-space radius of the sphere mesh
    return length(float3(unity_ObjectToWorld._m00, unity_ObjectToWorld._m10, unity_ObjectToWorld._m20)) * 0.5;
}

v2f vert_common(appdata v)
{
    v2f o;
    UNITY_SETUP_INSTANCE_ID(v);
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

// Unified Doppler Factor based on General Relativity: combinations of radial gravity shift and frame dragging spin
inline float GetUnifiedDoppler(float3 rayDir, float3 singularityDir, float3 perpendicular, float distToCenter, float worldRs)
{
    float cosTheta = dot(rayDir, singularityDir); // 1.0 when looking straight at center, -1.0 when looking away
    
    // Gravitational redshift scales with the gravitational potential Rs / D
    float gravityStrength = worldRs / max(distToCenter, 0.0001);
    
    // Gravitational shift: looking away (cosTheta < 0) yields blue shift; looking inward (cosTheta > 0) yields redshift
    float gravShift = - cosTheta * gravityStrength * _RedshiftFactor;
    
    // Rotational frame-dragging shift: Local Y axis of the mesh is the spin axis
    float3 localY = normalize(float3(unity_ObjectToWorld._m01, unity_ObjectToWorld._m11, unity_ObjectToWorld._m21));
    float3 spinDir = normalize(cross(singularityDir, localY + float3(1e-6, 0.0, 0.0)));
    
    // Scale rotation shift based on angle: decays exponentially as we move away from the horizon boundary on screen
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
    
    float angleDecay = pow(max(theta_H, 0.0001) / max(theta, 0.0001), 3.0);
    float spinShift = dot(perpendicular, spinDir) * _RotationSpeed * gravityStrength * angleDecay;
    
    // Exponential mapping of total shift (Doppler factor)
    return exp(gravShift + spinShift);
}

inline float3 RGBtoHSV(float3 c)
{
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

inline float3 HSVtoRGB(float3 c)
{
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

inline float3 GetFringeColor(float3 baseColor, float doppler)
{
    if (doppler > 1.0)
    {
        return lerp(baseColor, float3(0.35, 0.65, 1.0), saturate((doppler - 1.0) * _RedshiftFactor));
    }
    else
    {
        return lerp(baseColor, float3(1.0, 0.02, 0.0), saturate((1.0 - doppler) * _RedshiftFactor));
    }
}

inline float3 ApplyBackgroundDoppler(float3 rgb, float doppler)
{
    float3 col = rgb;
    
    if (doppler > 1.0)
    {
        // Exponential blueshift interpolation for vivid color progression
        float s = saturate(1.0 - exp(-(doppler - 1.0) * _RedshiftFactor));
        
        // Blueshift matrix: shifts wavelengths towards blue (Red -> Green -> Blue)
        float3x3 M_blue = float3x3(
            1.0 - s, 0.0,     0.0,
            s,       1.0 - s, 0.0,
            s * 0.5, s,       1.0
        );
        col = mul(M_blue, rgb);
        
        // Desaturate at higher blueshifts to represent ultraviolet white glow
        col = lerp(col, dot(col, float3(0.299, 0.587, 0.114)), s * 0.5);
    }
    else
    {
        // Exponential redshift interpolation for vivid color progression
        float s = saturate(1.0 - exp(-(1.0 - doppler) * _RedshiftFactor));
        
        // Redshift matrix: shifts wavelengths towards red (Blue -> Green -> Red)
        float3x3 M_red = float3x3(
            1.0,     s,       s * 0.5,
            0.0,     1.0 - s, s,
            0.0,     0.0,     1.0 - s
        );
        col = mul(M_red, rgb);
    }
    
    // Relativistic Beaming: power-of-three intensity scaling
    float beaming = pow(max(doppler, 0.0001), 3.0);
    return col * beaming;
}

#endif // BLACK_HOLE_COMMON_INCLUDED
