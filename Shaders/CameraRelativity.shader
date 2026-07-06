Shader "DarkRelativity/CameraRelativity"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _PlayerSpeed ("Player Speed", Float) = 0.0
        _SpeedOfLight ("Speed of Light (c)", Float) = 10.0
    }
    
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            sampler2D _MainTex;
            float _PlayerSpeed;
            float _SpeedOfLight;

            // Applies the Relativistic Color Shift & Beaming
            inline half3 ApplySpecialRelativityDoppler(half3 rgb, float doppler)
            {
                half3 col = rgb;
                if (doppler > 1.0)
                {
                    // Blueshift (Approaching)
                    half s = saturate(1.0 - 1.0 / doppler);
                    half3x3 M_blue = half3x3(
                        1.0 - s, 0.0,     0.0,
                        s,       1.0 - s, 0.0,
                        s * 0.5, s,       1.0
                    );
                    col = mul(M_blue, rgb);
                    // Desaturate to blinding white/UV at extreme speeds
                    col = lerp(col, dot(col, half3(0.299, 0.587, 0.114)), s * 0.8);
                }
                else
                {
                    // Redshift (Receding)
                    half s = saturate(1.0 - doppler);
                    half3x3 M_red = half3x3(
                        1.0,     s,       s * 0.5,
                        0.0,     1.0 - s, s,
                        0.0,     0.0,     1.0 - s
                    );
                    col = mul(M_red, rgb);
                }
                
                // Relativistic Beaming (Searchlight effect)
                // This naturally acts as a vignette, hiding the screen edges!
                float beaming = pow(max(doppler, 0.0001), 4.0); 
                return col * beaming;
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // Calculate Beta (v/c), clamped safely just below 1.0 to prevent division by zero
                float c = max(_SpeedOfLight, 0.001);
                float beta = clamp(_PlayerSpeed / c, -0.999, 0.999);
                
                float2 centeredUV = i.uv - 0.5;
                
                // Approximate angle based on distance from center of screen.
                // Assuming a standard ~90 degree FOV where the edge is ~45 degrees off center.
                float r = length(centeredUV) * 2.0; // 0 at center, 1 at edge
                float cosTheta = lerp(1.0, 0.707, r); // 1.0 looking straight, 0.707 looking at edge
                
                // Relativistic Aberration (Visual Tunneling)
                // As you approach c, the universe visually collapses into a bright point ahead of you.
                // We pinch the UVs to simulate this light bending.
                float pinch = (1.0 - abs(beta)) * 0.5 + 0.5; // Warps UVs inward as beta approaches 1
                float2 distortedUV = centeredUV * pinch + 0.5;
                
                // Fetch the distorted screen pixel
                half4 texColor = tex2D(_MainTex, distortedUV);
                
                // Calculate true Doppler Shift: D = sqrt(1 - beta^2) / (1 - beta * cosTheta)
                float gammaInv = sqrt(1.0 - beta * beta);
                float doppler = gammaInv / max(1.0 - beta * cosTheta, 0.0001);
                
                texColor.rgb = ApplySpecialRelativityDoppler(texColor.rgb, doppler);
                
                return texColor;
            }
            ENDCG
        }
    }
}