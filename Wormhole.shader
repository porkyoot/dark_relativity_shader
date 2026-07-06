Shader "DarkRelativity/Wormhole"
{
    Properties
    {
        [Header(Core Metrics)]
        _ThroatRadius("Throat Radius (Rs)", Range(0.01, 0.49)) = 0.15
        
        [Header(Lensing Settings)]
        _DistortionStrength("Lensing Strength", Range(0.1, 15.0)) = 1.0
        _DistortionPower("Lensing Falloff", Range(0.5, 3.0)) = 1.2
        
        [Header(Wormhole Interior)]
        [NoScaleOffset] _WormholeSkybox("Wormhole Skybox", Cube) = "_Skybox" {}
        _SkyboxBrightness("Skybox Brightness", Range(0, 10)) = 1.0
        _InnerRefraction("Inner Refraction", Range(0.1, 5.0)) = 1.0
        
        [Header(Advanced Calibration Settings)]
        _HorizonLensingLimit("Horizon Lensing Limit", Range(0.5, 0.99)) = 0.85
        _MaxDeflectionAngle("Max Deflection Angle (Rad)", Range(1.0, 10.0)) = 3.77
        _ScreenBorderBlendWidth("Screen Border Blend Width", Range(0.01, 0.5)) = 0.15
        
        [Header(Fallback Environment)]
        [Toggle(USE_MANUAL_PROBE)] _UseManualProbe("Use Manual Environment Map", Float) = 0
        [NoScaleOffset] _ManualEnvironmentMap("Manual Environment Map", Cube) = "black" {}
    }
    
    SubShader
    {
        Tags 
        { 
            "Queue" = "Transparent+10" 
            "RenderType" = "Transparent" 
            "DisableBatching" = "True"
        }
        
        GrabPass
        {
            "_DarkRelativityGrab"
        }
        
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            
            ZWrite On 
            Cull Off
            Blend SrcAlpha OneMinusSrcAlpha
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase
            #pragma shader_feature USE_MANUAL_PROBE
            
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
                float3 normalWorld : TEXCOORD2;
                float4 screenCenter : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            UNITY_DECLARE_SCREENSPACE_TEXTURE(_DarkRelativityGrab);
            float4 _DarkRelativityGrab_TexelSize;

            samplerCUBE _WormholeSkybox;
            half4 _WormholeSkybox_HDR;
            samplerCUBE _ManualEnvironmentMap;
            
            float _ThroatRadius;
            float _DistortionStrength;
            float _DistortionPower;
            float _SkyboxBrightness;
            float _InnerRefraction;
            
            float _HorizonLensingLimit;
            float _MaxDeflectionAngle;
            float _ScreenBorderBlendWidth;
            
            inline float3 GetEyePos()
            {
                return mul(unity_CameraToWorld, float4(0.0, 0.0, 0.0, 1.0)).xyz;
            }

            inline float GetMeshRadius()
            {
                return length(float3(unity_ObjectToWorld._m00, unity_ObjectToWorld._m10, unity_ObjectToWorld._m20)) * 0.5;
            }
            
            v2f vert(appdata v)
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
                
                return o;
            }
            
            fixed4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                float3 eyePos = GetEyePos();
                float3 center = unity_ObjectToWorld._m03_m13_m23;
                float3 normalWorld = normalize(i.normalWorld);
                float3 rayDir = normalize(i.worldPos - eyePos);
                float distToCenter = distance(eyePos, center);
                float meshRadius = GetMeshRadius();
                
                // Backface culling optimisation
                if (distToCenter > meshRadius && dot(normalWorld, rayDir) > 0.0)
                {
                    discard;
                }
                
                float worldRs = meshRadius * saturate(_ThroatRadius / 0.5);
                
                // Screen parameters
                float aspect = UNITY_MATRIX_P[1][1] / UNITY_MATRIX_P[0][0];
                float2 aspectCorrect = float2(aspect, 1.0);
                
                float2 uv = i.grabPos.xy / i.grabPos.w;
                float2 centerUv = i.screenCenter.xy / i.screenCenter.w;
                float2 V = (uv - centerUv) * aspectCorrect;
                float r = length(V);
                
                float F = UNITY_MATRIX_P[1][1] * 0.5;
                float r_mesh_screen = (meshRadius / max(distToCenter, 0.0001)) * F;
                float edgeFade = (distToCenter > meshRadius) ? saturate((r_mesh_screen - r) / (r_mesh_screen * 0.15 + 1e-5)) : 1.0;
                
                fixed4 finalColor = fixed4(0, 0, 0, edgeFade);
                
                float3 singularityDir = normalize(center - eyePos);
                float cosTheta = dot(rayDir, singularityDir); 
                
                float cosTheta_H;
                if (distToCenter >= worldRs)
                {
                    float sinTheta_H = worldRs / max(distToCenter, 0.0001);
                    cosTheta_H = sqrt(max(0.0, 1.0 - sinTheta_H * sinTheta_H));
                }
                else
                {
                    cosTheta_H = - (1.0 - distToCenter / max(worldRs, 0.0001));
                }
                
                float theta = acos(clamp(cosTheta, -1.0, 1.0));
                float theta_H = acos(clamp(cosTheta_H, -1.0, 1.0));
                
                float3 perpVec = rayDir - singularityDir * cosTheta;
                float perpLen = length(perpVec);
                float3 perpendicular = (perpLen > 1e-5) ? (perpVec / perpLen) : float3(0.0, 0.0, 0.0);
                
                if (cosTheta > cosTheta_H)
                {
                    // INSIDE WORMHOLE THROAT (theta <= theta_H)
                    // Map the inward ray to an outward view in the other universe
                    float normalizedTheta = theta / max(theta_H, 0.0001);
                    float theta_out = normalizedTheta * 3.1415926535 * _InnerRefraction;
                    
                    float3 ray_Wormhole = singularityDir * cos(theta_out) + perpendicular * sin(theta_out);
                    
                    half4 skyColor = texCUBElod(_WormholeSkybox, float4(ray_Wormhole, 0.0));
                    half3 decodedSkyColor = DecodeHDR(skyColor, _WormholeSkybox_HDR);
                    
                    finalColor.rgb = decodedSkyColor * _SkyboxBrightness;
                    finalColor.a = edgeFade;
                }
                else
                {
                    // OUTSIDE THROAT (LENSING)
                    float fade = 1.0;
                    if (distToCenter > meshRadius)
                    {
                        float sinTheta_mesh = meshRadius / distToCenter;
                        float cosTheta_mesh = sqrt(max(0.0, 1.0 - sinTheta_mesh * sinTheta_mesh));
                        float theta_mesh = acos(clamp(cosTheta_mesh, -1.0, 1.0));
                        fade = saturate((theta_mesh - theta) / max(theta_mesh * 0.15, 0.0001));
                    }
                    
                    float distBase = theta_H / max(theta - theta_H * _HorizonLensingLimit, 0.0001);
                    float oppositeFade = cos(theta * 0.5);
                    float distFactor = _DistortionStrength * pow(distBase, _DistortionPower) * fade * oppositeFade;
                    
                    distFactor = min(distFactor, _MaxDeflectionAngle / max(theta_H, 0.0001));
                    
                    float theta_Lensed = theta - theta_H * distFactor;
                    float3 ray_Lensed = singularityDir * cos(theta_Lensed) + perpendicular * sin(theta_Lensed);
                    
                    half3 col;
                    
                    if (distToCenter < worldRs)
                    {
                        // If camera is inside the throat
                        half4 probeColor = texCUBElod(_WormholeSkybox, float4(ray_Lensed, 0.0));
                        col = DecodeHDR(probeColor, _WormholeSkybox_HDR) * _SkyboxBrightness;
                    }
                    else
                    {
                        float3 proj_Lensed = eyePos + ray_Lensed * distToCenter;
                        float4 clip_Lensed = UnityWorldToClipPos(proj_Lensed);
                        float2 uv_Lensed = ComputeGrabScreenPos(clip_Lensed).xy / max(clip_Lensed.w, 0.0001);
                        
                        float blendW = max(_ScreenBorderBlendWidth, 0.02);
                        
                        bool inBounds = all(uv_Lensed > 0.0) && all(uv_Lensed < 1.0) && (clip_Lensed.w > 0.0);
                        float2 distToEdge = min(uv_Lensed, 1.0 - uv_Lensed);
                        float edgeDist = min(distToEdge.x, distToEdge.y);
                        float blend = inBounds ? smoothstep(0.0, blendW, edgeDist) : 0.0;
                        
                        half3 grabCol = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_DarkRelativityGrab, uv_Lensed).rgb;
                        
                        half3 probeCol;
#ifdef USE_MANUAL_PROBE
                        probeCol = texCUBElod(_ManualEnvironmentMap, float4(ray_Lensed, 0.0)).rgb;
#else
                        half4 probeColRaw = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_Lensed, 0.0);
                        probeCol = DecodeHDR(probeColRaw, unity_SpecCube0_HDR);
#endif
                        
                        col = lerp(probeCol, grabCol, blend);
                    }
                    
                    finalColor.rgb = col;
                    finalColor.a = edgeFade;
                }
                
                return finalColor;
            }
            ENDCG
        }
    }
    
    Fallback "Transparent/Diffuse"
}
