Shader "DarkRelativity/BlackHole_Quest"
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
        _BaseTemperature("Base Plasma Temp (K)", Range(1000, 15000)) = 6500.0
        _FringeWidth("Fringe Width", Range(0.0, 0.5)) = 0.08
        _FringeStrength("Fringe Strength", Range(0, 10)) = 3.0
        
        [Header(Depth Occlusion Settings)]
        [Toggle] _UseDepthOcclusion("Use Depth Occlusion", Float) = 0
        
        [Header(Advanced Calibration Settings)]
        _HorizonLensingLimit("Horizon Lensing Limit", Range(0.5, 0.99)) = 0.85
        _MaxDeflectionAngle("Max Deflection Angle (Rad)", Range(1.0, 10.0)) = 3.77
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
            
            #include "BlackHoleCommon.cginc"
            
            UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);
            
            v2f vert(appdata v)
            {
                return vert_common(v);
            }
            
            fixed4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                // Dynamic active eye position in world space to resolve VR stereoscopic disparity
                float3 eyePos = GetEyePos();
                
                float3 center = unity_ObjectToWorld._m03_m13_m23;
                float3 normalWorld = normalize(i.normalWorld);
                float3 rayDir = normalize(i.worldPos - eyePos);
                float distToCenter = distance(eyePos, center);
                
                float meshRadius = GetMeshRadius();
                
                // Backface culling optimization when outside sphere of influence
                if (distToCenter > meshRadius && dot(normalWorld, rayDir) > 0.0)
                {
                    discard;
                }
                
                // Viewport aspect ratio derived directly from projection matrix (VR/desktop safe)
                float aspect = UNITY_MATRIX_P[1][1] / UNITY_MATRIX_P[0][0];
                float2 aspectCorrect = float2(aspect, 1.0);
                
                float2 uv = i.grabPos.xy / i.grabPos.w;
                float2 centerUv = i.screenCenter.xy / i.screenCenter.w;
                float2 V = (uv - centerUv) * aspectCorrect;
                float r = length(V);
                
                // Scale-independent world event horizon radius
                float worldRs = meshRadius * saturate(_RealRadius / 0.5);
                
                // Calculate VR-safe screen-space radii mathematically using focal length
                float F = UNITY_MATRIX_P[1][1] * 0.5;
                float r_H = (worldRs / max(distToCenter, 0.0001)) * F;
                float r_mesh_screen = (meshRadius / max(distToCenter, 0.0001)) * F;
                
                // Edge fade factor based on the actual screen-space boundary of the mesh
                float edgeFade = (distToCenter > meshRadius) ? saturate((r_mesh_screen - r) / (r_mesh_screen * 0.15 + 1e-5)) : 1.0;
                
                fixed4 finalColor = fixed4(0, 0, 0, 0);
                
                // --- UNIFIED PATH (QUEST) ---
                float3 singularityDir = normalize(center - eyePos);
                float cosTheta = dot(rayDir, singularityDir); // 1.0 when looking straight at center, -1.0 when looking away
                
                // Depth Occlusion Sampling
                float screenRawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
                float sceneLinearDepth = LinearEyeDepth(screenRawDepth);
                
                if (_UseDepthOcclusion > 0.5 && distToCenter > meshRadius)
                {
                    if (sceneLinearDepth < i.grabPos.z)
                    {
                        discard;
                    }
                }
                
                // Compute Schwarzschild Horizon Boundary continuous across event horizon boundary
                float cosTheta_H;
                if (distToCenter >= worldRs)
                {
                    float sinTheta_H = worldRs / max(distToCenter, 0.0001);
                    cosTheta_H = sqrt(max(0.0, 1.0 - sinTheta_H * sinTheta_H));
                }
                else
                {
                    // Inside the horizon: cosTheta_H goes from 0.0 (at boundary) to -1.0 (at singularity), taking more than 180 degrees
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
                        bool isFarPlane = (screenRawDepth <= 1e-5);
                        occludedByScene = (screenRawDepth > horizonDepth) && !isFarPlane;
                        #else
                        bool isFarPlane = (screenRawDepth >= 0.99999);
                        occludedByScene = (screenRawDepth < horizonDepth) && !isFarPlane;
                        #endif
                    }
                }
                
                if (cosTheta > cosTheta_H && !occludedByScene)
                {
                    // Event Horizon (completely dark)
                    finalColor = fixed4(0, 0, 0, edgeFade);
                }
                else if (occludedByScene)
                {
                    // If occluded, do not render reflection probe or fringe over the opaque scene
                    finalColor = fixed4(0, 0, 0, 0);
                }
                else
                {
                    // Compute radially symmetric perpendicular vector
                    float3 perpVec = rayDir - singularityDir * cosTheta;
                    float perpLen = length(perpVec);
                    float3 perpendicular = (perpLen > 1e-5) ? (perpVec / perpLen) : float3(0.0, 0.0, 0.0);
                    
                    // Compute Unified Doppler Factor
                    float doppler = GetUnifiedDoppler(rayDir, singularityDir, perpendicular, distToCenter, worldRs);
                    
                    float theta = acos(clamp(cosTheta, -1.0, 1.0));
                    float theta_H = acos(clamp(cosTheta_H, -1.0, 1.0));
                    
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
                    
                    float theta_G = theta - theta_H * distFactor;
                    float3 ray_G = singularityDir * cos(theta_G) + perpendicular * sin(theta_G);
                    
                    // Sample the dynamic Reflection Probe cubemap to simulate lensing on Quest
                    half4 probeColor = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_G, 0.0);
                    finalColor.rgb = DecodeHDR(probeColor, unity_SpecCube0_HDR);
                    
                    // Apply General Relativistic Doppler, Beaming, and Color Shifting
                    finalColor.rgb = ApplyBackgroundDoppler(finalColor.rgb, doppler);
                    
                    if (distToCenter >= worldRs)
                    {
                        // Add gravitational redshift fringe (photon ring)
                        float fringeInTheta = theta_H;
                        float fringeOutTheta = theta_H * (1.0 + _FringeWidth);
                        
                        if (_FringeWidth > 0.0 && theta < fringeOutTheta)
                        {
                            float fringeFactor = smoothstep(fringeOutTheta, fringeInTheta, theta) * edgeFade;
                            float3 fringeColor = GetFringeColor(doppler);
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
    
    Fallback "Transparent/Diffuse"
}
