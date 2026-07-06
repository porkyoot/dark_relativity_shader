Shader "DarkRelativity/Wormhole_Quest"
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
        _InnerCurvePower("Inner Curve Power", Range(1.0, 8.0)) = 3.0
        _EdgeBlendWidth("Edge Blend Width", Range(0.001, 0.2)) = 0.05
        
        [Header(Advanced Calibration Settings)]
        _MaxRings("Max Light Repeats (Rings)", Range(0.0, 20.0)) = 3.0
        
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
        
        Pass
        {
            Tags { "LightMode" = "Always" }
            
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
                float3 worldPos : TEXCOORD0;
                float3 normalWorld : TEXCOORD1;
                float4 constants : TEXCOORD2;
                float3 singularityDir : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };
            
            samplerCUBE _WormholeSkybox;
            half4 _WormholeSkybox_HDR;
            samplerCUBE _ManualEnvironmentMap;
            
            float _ThroatRadius;
            float _DistortionStrength;
            float _DistortionPower;
            float _SkyboxBrightness;
            float _InnerRefraction;
            float _InnerCurvePower;
            float _EdgeBlendWidth;
            float _MaxRings;
            
            inline float3 GetEyePos()
            {
                return float3(unity_CameraToWorld._m03, unity_CameraToWorld._m13, unity_CameraToWorld._m23);
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
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.normalWorld = UnityObjectToWorldNormal(v.normal);
                
                float3 centerWorld = unity_ObjectToWorld._m03_m13_m23;
                float3 eyePos = GetEyePos();
                float distToCenter = distance(eyePos, centerWorld);
                float meshRadius = GetMeshRadius();
                float worldRs = meshRadius * saturate(_ThroatRadius / 0.5);
                
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
                float theta_H = acos(clamp(cosTheta_H, -1.0, 1.0));
                
                o.constants = float4(distToCenter, meshRadius, theta_H, worldRs);
                o.singularityDir = normalize(centerWorld - eyePos);
                
                return o;
            }
            
            fixed4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                float3 eyePos = GetEyePos();
                float3 normalWorld = normalize(i.normalWorld);
                float3 rayDir = normalize(i.worldPos - eyePos);
                
                float distToCenter = i.constants.x;
                float meshRadius = i.constants.y;
                float theta_H = i.constants.z;
                float worldRs = i.constants.w;
                float3 singularityDir = normalize(i.singularityDir);
                
                // Backface culling optimisation
                if (distToCenter > meshRadius && dot(normalWorld, rayDir) > 0.0)
                {
                    discard;
                }
                
                // Edge fading for boundaries of the wormhole sphere
                // Quest-friendly simplified edge fade calculation
                float edgeFade = 1.0;
                if (distToCenter > meshRadius)
                {
                    float sinTheta_mesh = meshRadius / distToCenter;
                    float cosTheta_mesh = sqrt(max(0.0, 1.0 - sinTheta_mesh * sinTheta_mesh));
                    float theta_mesh = acos(clamp(cosTheta_mesh, -1.0, 1.0));
                    float cosTheta = dot(rayDir, singularityDir);
                    float theta = acos(clamp(cosTheta, -1.0, 1.0));
                    edgeFade = saturate((theta_mesh - theta) / max(theta_mesh * 0.15, 0.0001));
                }
                
                fixed4 finalColor = fixed4(0, 0, 0, edgeFade);
                
                float cosTheta = dot(rayDir, singularityDir); 
                float theta = acos(clamp(cosTheta, -1.0, 1.0));
                
                float3 perpVec = rayDir - singularityDir * cosTheta;
                float perpLen = length(perpVec);
                float3 perpendicular = (perpLen > 1e-5) ? (perpVec / perpLen) : float3(0.0, 0.0, 0.0);
                
                // Calculate distance-based fade to eliminate distortion right at the threshold
                float distFromHorizon = abs(distToCenter - worldRs);
                half transitionFade = saturate((half)(distFromHorizon / max(worldRs * 0.5, 0.0001)));
                
                // Calculate INSIDE Wormhole color
                float normalizedTheta = saturate(theta / max(theta_H, 0.0001));
                float baseMapping = normalizedTheta * 3.1415926535 * _InnerRefraction;
                float ringMapping = pow(normalizedTheta, _InnerCurvePower) * (_MaxRings * 6.283185307) * (float)transitionFade;
                float theta_out = baseMapping + ringMapping;
                
                float sin_out, cos_out;
                sincos(theta_out, sin_out, cos_out);
                float3 ray_Wormhole = singularityDir * cos_out + perpendicular * sin_out;
                half4 skyColor = texCUBElod(_WormholeSkybox, float4(ray_Wormhole, 0.0));
                half3 col_Inside = DecodeHDR(skyColor, _WormholeSkybox_HDR) * _SkyboxBrightness;
                
                // Calculate OUTSIDE Lensing color
                half fade = 1.0h;
                if (distToCenter > meshRadius)
                {
                    float sinTheta_mesh = meshRadius / distToCenter;
                    float cosTheta_mesh = sqrt(max(0.0, 1.0 - sinTheta_mesh * sinTheta_mesh));
                    float theta_mesh = acos(clamp(cosTheta_mesh, -1.0, 1.0));
                    fade = saturate((half)((theta_mesh - theta) / max(theta_mesh * 0.15, 0.0001)));
                }
                
                half outerNorm = saturate((half)(theta_H / max(theta, 0.0001)));
                half distFactor = pow(outerNorm, (half)_DistortionPower) * ((half)_MaxRings * 6.283185307h) * fade * transitionFade;
                float theta_Lensed = theta - theta_H * (float)distFactor;
                
                float sin_lensed, cos_lensed;
                sincos(theta_Lensed, sin_lensed, cos_lensed);
                float3 ray_Lensed = singularityDir * cos_lensed + perpendicular * sin_lensed;
                
                half3 col_Outside;
#ifdef USE_MANUAL_PROBE
                col_Outside = texCUBElod(_ManualEnvironmentMap, float4(ray_Lensed, 0.0)).rgb;
#else
                half4 probeColRaw = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_Lensed, 0.0);
                col_Outside = DecodeHDR(probeColRaw, unity_SpecCube0_HDR);
#endif
                
                // Smooth threshold blend between Inside and Outside (done in float for transition accuracy, then cast)
                float insideFactor = 1.0 - smoothstep(theta_H - _EdgeBlendWidth, theta_H + _EdgeBlendWidth, theta);
                finalColor.rgb = lerp(col_Outside, col_Inside, (half)insideFactor);
                finalColor.a = (half)edgeFade;
                
                return finalColor;
            }
            ENDCG
        }
    }
    
    Fallback "Transparent/Diffuse"
}
