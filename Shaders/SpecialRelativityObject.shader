Shader "DarkRelativity/SpecialRelativityObject"
{
    Properties
    {
        _MainTex ("Base Texture", 2D) = "white" {}
        [HDR] _BaseColor ("Base Color/Emission", Color) = (1,1,1,1)
        
        [Header(Relativistic Parameters)]
        _SpeedFraction ("Speed Fraction (% of c)", Range(0.0, 0.999)) = 0.0
        _VelocityDir ("Velocity Direction (World Space)", Vector) = (0, 0, 1, 0)
        _SpeedOfLight ("Simulated Speed of Light", Float) = 100.0
        
        [Toggle(USE_TERRELL_EFFECT)] _UseTerrellEffect ("Enable Optical Delay (Terrell Rotation)", Float) = 1
        
        [Header(Rendering Blend Modes)]
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Source Blend", Float) = 1.0 // Default One
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Destination Blend", Float) = 0.0 // Default Zero
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 1.0 // Default On
    }
    
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100
        Cull Back

        Pass
        {
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature USE_TERRELL_EFFECT
            #pragma multi_compile_instancing
            
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            half4 _BaseColor;
            
            float _SpeedFraction;
            float4 _VelocityDir;
            float _SpeedOfLight;

            // Applies the Relativistic Color Shift
            inline half3 ApplySpecialRelativityDoppler(half3 rgb, float doppler)
            {
                half3 col = rgb;
                if (doppler > 1.0)
                {
                    // Blueshift
                    half s = saturate(1.0 - 1.0 / doppler);
                    half3x3 M_blue = half3x3(
                        1.0 - s, 0.0,     0.0,
                        s,       1.0 - s, 0.0,
                        s * 0.5, s,       1.0
                    );
                    col = mul(M_blue, rgb);
                    // Desaturate at extreme blueshift (UV/X-ray glow)
                    col = lerp(col, dot(col, half3(0.299, 0.587, 0.114)), s * 0.7);
                }
                else
                {
                    // Redshift
                    half s = saturate(1.0 - doppler);
                    half3x3 M_red = half3x3(
                        1.0,     s,       s * 0.5,
                        0.0,     1.0 - s, s,
                        0.0,     0.0,     1.0 - s
                    );
                    col = mul(M_red, rgb);
                }
                
                // Beaming (Searchlight effect)
                float beaming = pow(max(doppler, 0.0001), 3.0);
                return col * beaming;
            }

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                
                float beta = _SpeedFraction;
                if (beta < 0.0001)
                {
                    o.pos = UnityObjectToClipPos(v.vertex);
                    o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                    return o;
                }
                
                // 1. Get Base World Position
                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                float3 pivot = unity_ObjectToWorld._m03_m13_m23;
                
                // Ensure velocity is normalized
                float3 vDir = normalize(_VelocityDir.xyz + float3(1e-5,0,0));
                
                // 2. Physical Length Contraction (Lorentz Transform)
                // gamma = 1 / sqrt(1 - beta^2)
                float gamma = 1.0 / sqrt(max(1.0 - beta * beta, 0.0001));
                
                float3 offset = worldPos - pivot;
                float parallelComp = dot(offset, vDir);
                float3 perpComp = offset - parallelComp * vDir;
                
                // Contract the space along the velocity vector
                parallelComp /= gamma; 
                worldPos = pivot + parallelComp * vDir + perpComp;

                // 3. Optical Delay (Terrell Rotation / Skew)
                #ifdef USE_TERRELL_EFFECT
                    float distToCam = distance(_WorldSpaceCameraPos, worldPos);
                    // Time it took light to reach camera
                    float lightTravelTime = distToCam / max(_SpeedOfLight, 0.001);
                    
                    // The object was further back along its path when this light was emitted
                    float distanceTravelledDuringDelay = (_SpeedOfLight * beta) * lightTravelTime;
                    worldPos -= vDir * distanceTravelledDuringDelay;
                #endif

                o.worldPos = worldPos;
                
                // Convert modified world position back to clip space
                o.pos = mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));
                
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                
                half4 texColor = tex2D(_MainTex, i.uv) * _BaseColor;
                
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
                float3 vDir = normalize(_VelocityDir.xyz + float3(1e-5,0,0));
                
                // cosTheta: 1 = moving directly at camera, -1 = moving away
                float cosTheta = dot(viewDir, vDir);
                float beta = _SpeedFraction;
                
                // 4. Special Relativity Doppler Equation
                // D = sqrt(1 - beta^2) / (1 - beta * cosTheta)
                float numerator = sqrt(max(1.0 - beta * beta, 0.0001));
                float denominator = max(1.0 - beta * cosTheta, 0.0001);
                float doppler = numerator / denominator;
                
                texColor.rgb = ApplySpecialRelativityDoppler(texColor.rgb, doppler);
                
                return texColor;
            }
            ENDCG
        }
    }
}