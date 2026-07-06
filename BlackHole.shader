Shader "DarkRelativity/BlackHole"
{
    Properties
    {
        [Header(Core Metrics)]
        _RealRadius("Schwarzschild Radius (Rs)", Range(0.01, 0.49)) = 0.15
        
        [Header(Fast Lensing Settings)]
        _DistortionStrength("Lensing Strength", Range(0.1, 15.0)) = 1.0
        _DistortionPower("Lensing Falloff (Fast)", Range(0.5, 3.0)) = 1.2
        
        [Header(Relativistic Physics Settings)]
        _SpeedOfLight("Speed of Light (c)", Float) = 100.0
        _RotationVelocity("Rotation Velocity (+-)", Float) = 50.0
        
        [Header(Thermodynamics and Fringe)]
        _FringeWidth("Fringe Width", Range(0.0, 0.5)) = 0.08
        _FringeStrength("Fringe Strength", Range(0, 10)) = 3.0
        

        [Header(Advanced Calibration Settings)]
        _HorizonLensingLimit("Horizon Lensing Limit", Range(0.5, 0.99)) = 0.85
        _MaxDeflectionAngle("Max Deflection Angle (Rad)", Range(1.0, 10.0)) = 3.77
        _ScreenBorderBlendWidth("Screen Border Blend Width", Range(0.01, 0.5)) = 0.15
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
            "_DarkRelativityGrab"
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
            
            UNITY_DECLARE_SCREENSPACE_TEXTURE(_DarkRelativityGrab);
            float4 _DarkRelativityGrab_TexelSize;
            
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
                


                
                float3 localY = normalize(float3(unity_ObjectToWorld._m01, unity_ObjectToWorld._m11, unity_ObjectToWorld._m21));
                float spinAlignment = dot(rayDir, localY);
                // Squeeze the poles (flattening) proportional to rotation velocity
                float squeeze = 1.0 - (spinAlignment * spinAlignment) * abs(_RotationVelocity) * 0.5;
                float worldRs = meshRadius * saturate(_RealRadius / 0.5) * squeeze;
                
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
                
                if (cosTheta > cosTheta_H)
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
                    
                    float doppler = GetUnifiedDoppler(rayDir, singularityDir, perpendicular, distToCenter, worldRs);
                    float theta_Lensed = theta - theta_H * distFactor;
                    float3 ray_Lensed = singularityDir * cos(theta_Lensed) + perpendicular * sin(theta_Lensed);
                    
                    half3 col;
                    
                    if (distToCenter < worldRs)
                    {
                        half4 probeColor = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_Lensed, 0.0);
                        col = DecodeHDR(probeColor, unity_SpecCube0_HDR);
                        col = ApplyBackgroundDoppler(col, doppler);
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
                        half3 probeCol = DecodeHDR(UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_Lensed, 0.0), unity_SpecCube0_HDR);
                        
                        col = lerp(probeCol, grabCol, blend);
                        col = ApplyBackgroundDoppler(col, doppler);
                    }
                    
                    finalColor.rgb = col;
                    

                        float fringeInTheta = theta_H;
                        float fringeOutTheta = theta_H * (1.0 + _FringeWidth);
                        
                        if (_FringeWidth > 0.0 && theta < fringeOutTheta)
                        {
                            half fringeFactor = (half)(smoothstep(fringeOutTheta, fringeInTheta, theta) * edgeFade);
                            half beaming = (half)pow(max(doppler, 0.0001), 3.0);
                            
                            // Boost the intensity of the skybox/background sample
                            finalColor.rgb *= (1.0 + fringeFactor * _FringeStrength * beaming);
                        }
                    
                    finalColor.a = edgeFade;
                }
                
                return finalColor;
            }
            ENDCG
        }
    }
}