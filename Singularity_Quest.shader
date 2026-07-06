Shader "DarkRelativity/Singularity (Quest)"
{
    Properties
    {
        // === METRIC TYPE (drives inspector layout) ===
        [KeywordEnum(BlackHole, Wormhole)] _AnalyticMetric("Singularity Type", Float) = 0
        
        // === SHARED CORE ===
        _RealRadius("Event Horizon / Throat Radius", Range(0.01, 0.49)) = 0.15
        _DistortionStrength("Lensing Strength", Range(0.1, 15.0)) = 1.0
        _DistortionPower("Lensing Falloff", Range(0.5, 3.0)) = 1.2
        _ScreenBorderBlendWidth("Screen Border Blend Width", Range(0.01, 0.5)) = 0.15
        _MaxRings("Max Light Repeats (Rings)", Range(0.0, 20.0)) = 3.0
        
        // === RELATIVISTIC PHYSICS (shared) ===
        _SpeedOfLight("Speed of Light (c)", Float) = 100.0
        _RotationVelocity("Rotation Velocity", Float) = 50.0
        _BeamingIntensity("Relativistic Beaming Intensity", Range(0.0, 1.0)) = 0.15
        
        // === BLACK HOLE ONLY ===
        _FringeWidth("Fringe Width", Range(0.0, 0.5)) = 0.08
        _FringeStrength("Fringe Strength", Range(0, 10)) = 3.0
        _HorizonLensingLimit("Horizon Lensing Limit", Range(0.5, 0.99)) = 0.85
        
        // === WORMHOLE ONLY ===
        [NoScaleOffset] _WormholeSkybox("Wormhole Skybox (Universe B)", Cube) = "_Skybox" {}
        _SkyboxBrightness("Skybox Brightness", Range(0, 10)) = 1.0
        _InnerRefraction("Inner Refraction (Analytic)", Range(0.1, 5.0)) = 1.0
        _InnerCurvePower("Inner Curve Power (Analytic)", Range(1.0, 8.0)) = 3.0
        _EdgeBlendWidth("Edge Blend Width", Range(0.001, 0.2)) = 0.05
        _TimeDilationShift("Time Dilation Shift (Doppler)", Range(-5.0, 5.0)) = 0.0
        
        // === GEODESIC LUT ===
        [Toggle(USE_GEODESIC_LUT)] _UseGeodesicLUT("Use Geodesic LUT", Float) = 0
        [NoScaleOffset] _GeodesicLUT("Geodesic LUT (Baked)", 2D) = "black" {}
        _LUTMaxDistance("LUT Max Distance", Float) = 10.0
        
        // === ENVIRONMENT (Required for Quest) ===
        [NoScaleOffset] _ManualEnvironmentMap("Manual Environment Map", Cube) = "black" {}
        
        // === BAKER PERSISTENCE (hidden, set by ShaderGUI) ===
        [HideInInspector] _BakerResolution("Baker Resolution", Float) = 512
        [HideInInspector] _BakerMaxSteps("Baker Max Steps", Float) = 10000
        [HideInInspector] _BakerStepSize("Baker Step Size", Float) = 0.005
    }
    
    SubShader
    {
        Tags 
        { 
            "Queue" = "Transparent+10" 
            "RenderType" = "Transparent" 
            "DisableBatching" = "True"
        }
        
        // NO GRABPASS FOR QUEST PERFORMANCE
        
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
            #pragma shader_feature USE_GEODESIC_LUT
            #pragma shader_feature _ANALYTICMETRIC_BLACKHOLE _ANALYTICMETRIC_WORMHOLE
            
            #include "SingularityCommon.cginc"
            
            samplerCUBE _WormholeSkybox;
            half4 _WormholeSkybox_HDR;
            samplerCUBE _ManualEnvironmentMap;
            half4 _ManualEnvironmentMap_HDR;
            sampler2D _GeodesicLUT;
            
            float _LUTMaxDistance;
            float _SkyboxBrightness;
            float _InnerRefraction;
            float _InnerCurvePower;
            float _TimeDilationShift;
            float _EdgeBlendWidth;
            float _MaxRings;
            
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
                
                if (distToCenter > meshRadius && dot(normalWorld, rayDir) > 0.0)
                {
                    discard;
                }
                
                float3 localY = normalize(float3(unity_ObjectToWorld._m01, unity_ObjectToWorld._m11, unity_ObjectToWorld._m21));
                float spinAlignment = dot(rayDir, localY);
                float squeeze = 1.0 - (spinAlignment * spinAlignment) * abs(_RotationVelocity) * 0.5;
                
                // Scale worldRs by squeeze value only for Black Hole metric (both analytic and LUT paths)
                float worldRs = meshRadius * saturate(_RealRadius / 0.5);
                #if defined(_ANALYTICMETRIC_BLACKHOLE)
                    float squeezeFactor = saturate(abs(_RotationVelocity) / max(_SpeedOfLight, 0.001));
                    float squeezeVal = 1.0 - (spinAlignment * spinAlignment) * squeezeFactor * 0.4;
                    worldRs *= squeezeVal;
                #endif
                
                // Simplified screen edge fade for Quest (spherical approximation instead of UVs)
                float r_mesh = meshRadius / max(distToCenter, 0.0001);
                float r_ray = sin(acos(dot(rayDir, normalize(center - eyePos))));
                float edgeFade = (distToCenter > meshRadius) ? saturate((r_mesh - r_ray) / (r_mesh * 0.15 + 1e-5)) : 1.0;
                
                fixed4 finalColor = fixed4(0, 0, 0, edgeFade);
                
                float3 singularityDir = normalize(center - eyePos);
                float cosTheta = dot(rayDir, singularityDir); 
                
                float cosTheta_H;
                #if defined(_ANALYTICMETRIC_BLACKHOLE)
                    // Schwarzschild lensed shadow size (3*sqrt(3)/2 = 2.598076 multiplier)
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
                        cosTheta_H = - (1.0 - distToCenter / max(worldRs, 0.0001));
                    }
                #endif
                
                float theta = acos(clamp(cosTheta, -1.0, 1.0));
                float theta_H = acos(clamp(cosTheta_H, -1.0, 1.0));
                
                // Calculate physical, world-space relative fringe size to keep it independent of camera distance
                float fringeOutTheta = theta_H;
                if (_FringeWidth > 0.0)
                {
                    float worldFringe = worldRs * (1.0 + _FringeWidth);
                    if (distToCenter >= worldFringe)
                    {
                        float sinTheta_Fringe = worldFringe / max(distToCenter, 0.0001);
                        fringeOutTheta = acos(clamp(sqrt(max(0.0, 1.0 - sinTheta_Fringe * sinTheta_Fringe)), -1.0, 1.0));
                    }
                    else
                    {
                        fringeOutTheta = 3.1415926535; // Cap to entire hemisphere if inside
                    }
                }
                
                float3 perpVec = rayDir - singularityDir * cosTheta;
                float perpLen = length(perpVec);
                float3 perpendicular = (perpLen > 1e-5) ? (perpVec / perpLen) : float3(0.0, 0.0, 0.0);
                
                half3 col_Outside = half3(0,0,0);
                half3 col_Inside = half3(0,0,0);
                float doppler = 1.0;
                float insideFactor = 0.0;
                
                #ifdef USE_GEODESIC_LUT
                
                    bool useLut = (distToCenter >= worldRs);
                    float u = saturate((distToCenter / max(worldRs, 0.0001) - 1.0) / max(_LUTMaxDistance - 1.0, 0.0001));
                    float v = saturate(theta / 3.1415926535);
                    
                    half4 texData = tex2Dlod(_GeodesicLUT, float4(u, v, 0, 0));
                    float totalPhi = useLut ? texData.r : 0.0;
                    float universeId = useLut ? texData.g : 0.5;
                    
                    if (!useLut)
                    {
                        #if defined(_ANALYTICMETRIC_BLACKHOLE)
                            universeId = (cosTheta > cosTheta_H) ? 0.0 : 0.5; // Horizon (0.0) vs Escape (0.5)
                        #else
                            universeId = (cosTheta > 0.0) ? 1.0 : 0.5; // Crossed Throat (1.0) vs Escape (0.5)
                        #endif
                    }
                    
                    // Mesh-edge blend: smoothly fade deflection to 0 at the mesh boundary
                    float meshBlend = 1.0;
                    if (distToCenter > meshRadius)
                    {
                        float sinTheta_mesh = meshRadius / distToCenter;
                        float cosTheta_mesh = sqrt(max(0.0, 1.0 - sinTheta_mesh * sinTheta_mesh));
                        float theta_mesh = acos(clamp(cosTheta_mesh, -1.0, 1.0));
                        meshBlend = saturate((theta_mesh - theta) / max(theta_mesh * 0.3, 0.0001));
                    }
                    
                    totalPhi *= meshBlend;
                    // At mesh edge, force Universe A (no throat crossing at the periphery, value 0.5)
                    universeId = (meshBlend < 0.01) ? 0.5 : universeId;
                    
                    if (universeId < 0.25) 
                    {
                        // UniverseID = 0.0 (Event Horizon) - Must be pure black
                        return fixed4(0, 0, 0, edgeFade);
                    }
                    else if (universeId < 0.75)
                    {
                        // UniverseID = 0.5 (Universe A, Escaped/Bounced)
                        // R channel stores NET DEFLECTION (0 = no bending at mesh edge)
                        float deflection = totalPhi;
                        float theta_Lensed = theta - deflection;
                        float3 ray_Lensed = singularityDir * cos(theta_Lensed) + perpendicular * sin(theta_Lensed);
                        
                        half4 probeColRaw = texCUBElod(_ManualEnvironmentMap, float4(ray_Lensed, 0.0));
                        col_Outside = DecodeHDR(probeColRaw, _ManualEnvironmentMap_HDR);
                        
                        // Rotational Doppler
                        doppler = GetUnifiedDoppler(rayDir, singularityDir, perpendicular, distToCenter, worldRs);
                        finalColor.rgb = ApplyBackgroundDoppler(col_Outside, doppler);
                        
                        // Apply Schwarzschild Event Horizon Fringe on the outside of the black hole
                        if (_FringeWidth > 0.0 && theta_Lensed < fringeOutTheta)
                        {
                            float fringeInTheta = theta_H;
                            half fringeFactor = (half)(smoothstep(fringeOutTheta, fringeInTheta, theta_Lensed) * edgeFade);
                            half beaming = (half)pow(max(doppler, 0.0001), 3.0);
                            finalColor.rgb *= (1.0 + fringeFactor * _FringeStrength * beaming);
                        }
                    }
                    else
                    {
                        // UniverseID = 1 (Universe B, Crossed Throat)
                        float theta_Lensed = totalPhi;
                        float3 ray_Lensed = singularityDir * cos(theta_Lensed) + perpendicular * sin(theta_Lensed);
                        
                        half4 skyColor = texCUBElod(_WormholeSkybox, float4(ray_Lensed, 0.0));
                        col_Inside = DecodeHDR(skyColor, _WormholeSkybox_HDR) * _SkyboxBrightness;
                        
                        // Wormhole Time Dilation Doppler: peaks at the center (theta=0) and falls off to the edge (theta_H)
                        float dilationFalloff = pow(saturate(1.0 - theta / max(theta_H, 0.0001)), 2.0);
                        float dopplerFactor = exp(_TimeDilationShift * dilationFalloff);
                        finalColor.rgb = ApplyBackgroundDoppler(col_Inside, dopplerFactor);
                    }
                    
                #else
                
                // -- ANALYTIC APPROXIMATION PATH --
                
                #if defined(_ANALYTICMETRIC_BLACKHOLE)
                    if (cosTheta > cosTheta_H)
                    {
                        finalColor = fixed4(0, 0, 0, edgeFade);
                    }
                    else
                    {
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
                        
                        distFactor = min(distFactor, (_MaxRings * 6.283185307) / max(theta_H, 0.0001));
                        
                        doppler = GetUnifiedDoppler(rayDir, singularityDir, perpendicular, distToCenter, worldRs);
                        float theta_Lensed = theta - theta_H * distFactor;
                        float3 ray_Lensed = singularityDir * cos(theta_Lensed) + perpendicular * sin(theta_Lensed);
                        
                        half4 probeColor = texCUBElod(_ManualEnvironmentMap, float4(ray_Lensed, 0.0));
                        col_Outside = DecodeHDR(probeColor, _ManualEnvironmentMap_HDR);
                        finalColor.rgb = ApplyBackgroundDoppler(col_Outside, doppler);
                        
                        float fringeInTheta = theta_H;
                        
                        if (_FringeWidth > 0.0 && theta_Lensed < fringeOutTheta)
                        {
                            half fringeFactor = (half)(smoothstep(fringeOutTheta, fringeInTheta, theta_Lensed) * edgeFade);
                            half beaming = (half)pow(max(doppler, 0.0001), 3.0);
                            finalColor.rgb *= (1.0 + fringeFactor * _FringeStrength * beaming);
                        }
                    }
                #else
                    // _ANALYTICMETRIC_WORMHOLE
                    float normalizedTheta = theta / max(theta_H, 0.0001);
                    float baseMapping = normalizedTheta * 3.1415926535 * _InnerRefraction;
                    float distBase_Inner = normalizedTheta / max(1.0 - normalizedTheta, 0.0001);
                    float infiniteRings = _InnerCurvePower * pow(distBase_Inner, _DistortionPower);
                    infiniteRings = min(infiniteRings, _MaxRings * 6.283185307);
                    float theta_out = baseMapping + infiniteRings;
                    float3 ray_Wormhole = singularityDir * cos(theta_out) + perpendicular * sin(theta_out);
                    
                    half4 skyColor = texCUBElod(_WormholeSkybox, float4(ray_Wormhole, 0.0));
                    col_Inside = DecodeHDR(skyColor, _WormholeSkybox_HDR) * _SkyboxBrightness;
                    
                    float fade = 1.0;
                    if (distToCenter > meshRadius)
                    {
                        float sinTheta_mesh = meshRadius / distToCenter;
                        float cosTheta_mesh = sqrt(max(0.0, 1.0 - sinTheta_mesh * sinTheta_mesh));
                        float theta_mesh = acos(clamp(cosTheta_mesh, -1.0, 1.0));
                        fade = saturate((theta_mesh - theta) / max(theta_mesh * 0.15, 0.0001));
                    }
                    
                    float distBase = theta_H / max(theta - theta_H, 0.0001);
                    float oppositeFade = cos(theta * 0.5);
                    float distFactor = _DistortionStrength * pow(distBase, _DistortionPower) * fade * oppositeFade;
                    distFactor = min(distFactor, (_MaxRings * 6.283185307) / max(theta_H, 0.0001));
                    
                    float theta_Lensed = theta - theta_H * distFactor;
                    float3 ray_Lensed = singularityDir * cos(theta_Lensed) + perpendicular * sin(theta_Lensed);
                    
                    half4 probeColRaw = texCUBElod(_ManualEnvironmentMap, float4(ray_Lensed, 0.0));
                    col_Outside = DecodeHDR(probeColRaw, _ManualEnvironmentMap_HDR);
                    
                    insideFactor = 1.0 - smoothstep(theta_H - _EdgeBlendWidth, theta_H + _EdgeBlendWidth, theta);
                    finalColor.rgb = lerp(col_Outside, col_Inside, insideFactor);
                    
                    // Wormhole Time Dilation Doppler: peaks at the center (theta=0) and falls off to the edge (theta_H)
                    float dilationFalloff = pow(saturate(1.0 - theta / max(theta_H, 0.0001)), 2.0);
                    float dopplerFactor = exp(_TimeDilationShift * dilationFalloff);
                    finalColor.rgb = ApplyBackgroundDoppler(finalColor.rgb, dopplerFactor);
                #endif // _ANALYTICMETRIC_WORMHOLE
                
                #endif // USE_GEODESIC_LUT
                
                finalColor.a = edgeFade;
                return finalColor;
            }
            ENDCG
        }
    }
    CustomEditor "DarkRelativity.SingularityShaderGUI"
    Fallback "Transparent/Diffuse"
}
