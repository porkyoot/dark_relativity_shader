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
    }
    
    SubShader
    {
        Tags 
        { 
            "Queue" = "Overlay+10" 
            "RenderType" = "Transparent" 
            "DisableBatching" = "True"
        }
        
        Pass
        {
            Tags { "LightMode" = "Always" }
            ZWrite Off
            Cull Off
            Blend SrcAlpha OneMinusSrcAlpha
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "BlackHoleCommon.cginc"
            
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
                
                if (cosTheta > cosTheta_H)
                {
                    // Event Horizon (completely dark)
                    finalColor = fixed4(0, 0, 0, edgeFade);
                }
                else
                {
                    // Compute radially symmetric perpendicular vector
                    float3 perpVec = rayDir - singularityDir * cosTheta;
                    float perpLen = length(perpVec);
                    float3 perpendicular = (perpLen > 1e-5) ? (perpVec / perpLen) : float3(0.0, 0.0, 0.0);
                    
                    // Compute Unified Doppler Factor
                    float doppler = GetUnifiedDoppler(rayDir, singularityDir, perpendicular, distToCenter, worldRs);
                    
                    if (distToCenter < worldRs)
                    {
                        // Inside the horizon: Sample the dynamic Reflection Probe cubemap directly in lensed directions (Quest)
                        float theta = acos(clamp(cosTheta, -1.0, 1.0));
                        float theta_H = acos(clamp(cosTheta_H, -1.0, 1.0));
                        
                        float oppositeFade = cos(theta * 0.5);
                        float distBase = theta_H / max(theta - theta_H * 0.85, 0.0001);
                        float distFactor = _DistortionStrength * pow(distBase, _DistortionPower) * oppositeFade;
                        
                        float maxDeflection = 3.14159265 * 1.2;
                        distFactor = min(distFactor, maxDeflection / max(theta_H, 0.0001));
                        
                        float theta_G = theta - theta_H * distFactor;
                        float3 ray_G = singularityDir * cos(theta_G) + perpendicular * sin(theta_G);
                        
                        half4 probeColor = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, ray_G, 0.0);
                        finalColor.rgb = DecodeHDR(probeColor, unity_SpecCube0_HDR);
                        
                        // Apply General Relativistic Doppler, Beaming, and Color Shifting inside on Quest
                        finalColor.rgb = ApplyBackgroundDoppler(finalColor.rgb, doppler);
                        finalColor.a = edgeFade;
                    }
                    else
                    {
                        // Outside event horizon: Add gravitational redshift fringe (photon ring)
                        float fringeIn = r_H;
                        float fringeOut = r_H * (1.0 + _FringeWidth);
                        if (_FringeWidth > 0.0 && r < fringeOut)
                        {
                            float fringeFactor = smoothstep(fringeOut, fringeIn, r) * edgeFade;
                            
                            // Procedural Doppler color shift for the fringe
                            float3 fringeColor = GetFringeColor(doppler);
                            
                            // Relativistic Beaming
                            float beaming = pow(max(doppler, 0.0001), 3.0);
                            float3 fringeGlow = fringeColor * fringeFactor * _FringeStrength * beaming;
                            
                            // Output the glowing ring with transparency
                            finalColor = fixed4(fringeGlow, fringeFactor * edgeFade);
                        }
                    }
                }
                
                return finalColor;
            }
            ENDCG
        }
    }
    
    Fallback "Transparent/Diffuse"
}
