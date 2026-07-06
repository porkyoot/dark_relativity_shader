Shader "DarkRelativity/BlackHole"
{
    Properties
    {
        [Header(Core Metrics)]
        _RealRadius("Schwarzschild Radius (Rs)", Range(0.01, 0.49)) = 0.15
        
        [Header(Fast Lensing Settings)]
        _DistortionStrength("Lensing Strength", Range(0.1, 15.0)) = 1.0
        _DistortionPower("Lensing Falloff (Fast)", Range(0.5, 3.0)) = 1.2
        _ChromaticAberration("Chromatic Aberration", Range(0.0, 0.3)) = 0.05
        
        [Header(Rotation and Redshift Settings)]
        _RotationSpeed("Rotation Speed & Dir (+-)", Float) = 0.5
        _RedshiftFactor("Redshift Factor", Range(0.0, 5.0)) = 1.5
        
        [Header(Gravitational Redshift Fringe)]
        _FringeWidth("Fringe Width", Range(0.0, 0.5)) = 0.08
        _FringeStrength("Fringe Strength", Range(0, 10)) = 3.0
        
        [Header(Depth Occlusion Settings)]
        [Toggle] _UseDepthOcclusion("Use Depth Occlusion", Float) = 0
        
        [Header(Advanced Calibration Settings)]
        _HorizonLensingLimit("Horizon Lensing Limit", Range(0.5, 0.99)) = 0.85
        _MaxDeflectionAngle("Max Deflection Angle (Rad)", Range(1.0, 10.0)) = 3.77
        _ScreenBorderBlendWidth("Screen Border Blend Width", Range(0.01, 0.5)) = 0.15
        _FringeBaseColor("Fringe Base Color", Color) = (1.0, 0.45, 0.12, 1.0)
    }
    
    SubShader
    {
        Tags 
        { 
            // On se place juste après les transparences standards du monde
            "Queue" = "Transparent+10" 
            "RenderType" = "Transparent" 
            "DisableBatching" = "True"
        }
        
        GrabPass
        {
            "_GrabTexture"
        }
        
        Pass
        {
            Tags { "LightMode" = "Always" }
            
            // LA MODIFICATION SUR TOUT LE MESH EST ICI
            ZWrite On 
            Cull Off
            Blend SrcAlpha OneMinusSrcAlpha
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "BlackHoleCommon.cginc"
            
            UNITY_DECLARE_SCREENSPACE_TEXTURE(_GrabTexture);
            float4 _GrabTexture_TexelSize;
            UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);
            
            v2f vert(appdata v)
            {
                return vert_common(v);
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
                
                float2 screenUv = i.grabPos.xy / i.grabPos.w;
                float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, screenUv);
                float sceneLinearDepth = LinearEyeDepth(rawDepth);
                
                // Occlusion des objets physiques de premier plan
                if (_UseDepthOcclusion > 0.5 && distToCenter > meshRadius)
                {
                    if (sceneLinearDepth < i.grabPos.z)
                    {
                        discard;
                    }
                }
                
                float worldRs = meshRadius * saturate(_RealRadius / 0.5);
                
                // --- Calculs originaux de distorsion ---
                float aspect = UNITY_MATRIX_P[1][1] / UNITY_MATRIX_P[0][0];
                float2 aspectCorrect = float2(aspect, 1.0);
                
                float2 uv = i.grabPos.xy / i.grabPos.w;
                float2 centerUv = i.screenCenter.xy / i.screenCenter.w;
                float2 V = (uv - centerUv) * aspectCorrect;
                float r = length(V);
                
                float F = UNITY_MATRIX_P[1][1] * 0.5;
                float r_H = (worldRs / max(distToCenter, 0.0001)) * F;
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
                
                bool occludedByScene = false;
                float3 rayOrigin = eyePos;
                float3 rayDirection = rayDir;
                float3 centerToCam = rayOrigin - center;
                
                float B = dot(rayDirection, centerToCam);
                float C = dot(centerToCam, centerToCam) - worldRs * worldRs;
                float discriminant = B * B - C;
                
                if (_UseDepthOcclusion > 0.5 && discriminant >= 0.0)
                {
                    float t_horizon = -B - sqrt(discriminant);
                    if (t_horizon > 0.0)
                    {
                        float3 intersectionPoint = rayOrigin + rayDirection * t_horizon;
                        float4 horizonClipPos = UnityWorldToClipPos(intersectionPoint);
                        float horizonDepth = horizonClipPos.z / horizonClipPos.w;
                        #if defined(UNITY_REVERSED_Z)
                        bool isFarPlane = (rawDepth <= 1e-5);
                        occludedByScene = (rawDepth > horizonDepth) && !isFarPlane;
                        #else
                        bool isFarPlane = (rawDepth >= 0.99999);
                        occludedByScene = (rawDepth < horizonDepth) && !isFarPlane;
                        #endif
                    }
                }
                
                if (cosTheta > cosTheta_H && !occludedByScene)
                {
                    finalColor = fixed4(0, 0, 0, edgeFade);
                }
                else
                {
                    // LENSING MATHEMATICS
                    float theta = acos(clamp(cosTheta, -1.0, 1.0));
                    float theta_H = acos(clamp(cosTheta_H, -1.0, 1.0));
                    
                    float3 perpVec = rayDir - singularityDir * cosTheta;
                    float perpLen = length(perpVec);
                    float3 perpendicular = (perpLen > 1e-5) ? (perpVec / perpLen) : float3(0.0, 0.0, 0.0);
                    
                    float doppler = GetUnifiedDoppler(rayDir, singularityDir, perpendicular, distToCenter, worldRs);
                    
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
                    
                    float theta_R = theta - theta_H * distFactor * (1.0 + _ChromaticAberration * 0.5);
                    float theta_G = theta - theta_H * distFactor;
                    float theta_B = theta - theta_H * distFactor * (1.0 - _ChromaticAberration * 0.5);
                    
                    float3 ray_R = singularityDir * cos(theta_R) + perpendicular * sin(theta_R);
                    float3 ray_G = singularityDir * cos(theta_G) + perpendicular * sin(theta_G);
                    float3 ray_B = singularityDir * cos(theta_B) + perpendicular * sin(theta_B);
                    
                    half3 col;
                    
                    if (distToCenter < worldRs)
                    {
                        half4 probeColor_R = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_R, 0.0);
                        half4 probeColor_G = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_G, 0.0);
                        half4 probeColor_B = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_B, 0.0);
                        
                        col.r = DecodeHDR(probeColor_R, unity_SpecCube0_HDR).r;
                        col.g = DecodeHDR(probeColor_G, unity_SpecCube0_HDR).g;
                        col.b = DecodeHDR(probeColor_B, unity_SpecCube0_HDR).b;
                        
                        col = ApplyBackgroundDoppler(col, doppler);
                    }
                    else
                    {
                        float3 proj_R = eyePos + (occludedByScene ? rayDir : ray_R) * distToCenter;
                        float3 proj_G = eyePos + (occludedByScene ? rayDir : ray_G) * distToCenter;
                        float3 proj_B = eyePos + (occludedByScene ? rayDir : ray_B) * distToCenter;
                        
                        float4 clip_R = UnityWorldToClipPos(proj_R);
                        float4 clip_G = UnityWorldToClipPos(proj_G);
                        float4 clip_B = UnityWorldToClipPos(proj_B);
                        
                        float2 uv_R = ComputeGrabScreenPos(clip_R).xy / max(clip_R.w, 0.0001);
                        float2 uv_G = ComputeGrabScreenPos(clip_G).xy / max(clip_G.w, 0.0001);
                        float2 uv_B = ComputeGrabScreenPos(clip_B).xy / max(clip_B.w, 0.0001);
                        
                        float blendW = max(_ScreenBorderBlendWidth, 0.02);
                        
                        bool inBounds_R = all(uv_R > 0.0) && all(uv_R < 1.0) && (clip_R.w > 0.0);
                        float2 distToEdge_R = min(uv_R, 1.0 - uv_R);
                        float edgeDist_R = min(distToEdge_R.x, distToEdge_R.y);
                        float blend_R = inBounds_R ? smoothstep(0.0, blendW, edgeDist_R) : 0.0;
                        half3 grabCol_R = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, uv_R).rgb;
                        half3 probeCol_R = DecodeHDR(UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_R, 0.0), unity_SpecCube0_HDR);
                        col.r = lerp(probeCol_R.r, grabCol_R.r, blend_R);
                        
                        bool inBounds_G = all(uv_G > 0.0) && all(uv_G < 1.0) && (clip_G.w > 0.0);
                        float2 distToEdge_G = min(uv_G, 1.0 - uv_G);
                        float edgeDist_G = min(distToEdge_G.x, distToEdge_G.y);
                        float blend_G = inBounds_G ? smoothstep(0.0, blendW, edgeDist_G) : 0.0;
                        half3 grabCol_G = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, uv_G).rgb;
                        half3 probeCol_G = DecodeHDR(UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_G, 0.0), unity_SpecCube0_HDR);
                        col.g = lerp(probeCol_G.g, grabCol_G.g, blend_G);
                        
                        bool inBounds_B = all(uv_B > 0.0) && all(uv_B < 1.0) && (clip_B.w > 0.0);
                        float2 distToEdge_B = min(uv_B, 1.0 - uv_B);
                        float edgeDist_B = min(distToEdge_B.x, distToEdge_B.y);
                        float blend_B = inBounds_B ? smoothstep(0.0, blendW, edgeDist_B) : 0.0;
                        half3 grabCol_B = UNITY_SAMPLE_SCREENSPACE_TEXTURE(_GrabTexture, uv_B).rgb;
                        half3 probeCol_B = DecodeHDR(UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_B, 0.0), unity_SpecCube0_HDR);
                        col.b = lerp(probeCol_B.b, grabCol_B.b, blend_B);
                        
                        col = ApplyBackgroundDoppler(col, doppler);
                    }
                    
                    finalColor.rgb = col;
                    
                    if (!occludedByScene)
                    {
                        float fringeIn = cosTheta_H;
                        float fringeOut = cosTheta_H * (1.0 - _FringeWidth);
                        
                        if (_FringeWidth > 0.0 && cosTheta > fringeOut)
                        {
                            float fringeFactor = smoothstep(fringeOut, fringeIn, cosTheta) * edgeFade;
                            float3 baseColor = float3(1.0, 0.45, 0.12);
                            float3 fringeColor = GetFringeColor(baseColor, doppler);
                            float beaming = pow(max(doppler, 0.0001), 3.0);
                            float3 fringeGlow = fringeColor * fringeFactor * _FringeStrength * beaming;
                            finalColor.rgb = lerp(finalColor.rgb, finalColor.rgb + fringeGlow, fringeFactor);
                        }
                    }
                    
                    finalColor.a = edgeFade;
                }
                
                return finalColor;
            }
            ENDCG
        }
    }
}