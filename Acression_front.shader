Shader "DarkRelativity/ForegroundAccretionDisk"
{
    Properties
    {
        _MainTex ("Disk Texture", 2D) = "white" {}
        _Color ("Tint Color", Color) = (1,1,1,1)
        _Emission ("Emission Multiplier", Range(0, 10)) = 1.0
    }
    
    SubShader
    {
        // On le force à se rendre APRÈS le trou noir
        Tags { "Queue"="Transparent+20" "RenderType"="Transparent" }
        
        ZWrite Off
        Cull Off // Pour voir le disque de dessus et de dessous
        Blend SrcAlpha OneMinusSrcAlpha

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
                float3 worldPos : TEXCOORD1;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _Color;
            float _Emission;

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                // On récupère la position du pixel dans le monde 3D
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // On trouve le centre de l'objet (le pivot du disque)
                float3 centerWorld = unity_ObjectToWorld._m03_m13_m23;

                // On calcule les distances par rapport à la caméra
                float distToPixel = distance(_WorldSpaceCameraPos, i.worldPos);
                float distToCenter = distance(_WorldSpaceCameraPos, centerWorld);

                // ==========================================
                // LA MAGIE OPÈRE ICI
                // Si la partie du disque est plus éloignée que le centre, 
                // c'est qu'elle est "derrière". On l'efface totalement !
                // ==========================================
                if (distToPixel > distToCenter)
                {
                    discard;
                }

                // Pour la partie avant (qui a survécu au discard) :
                fixed4 col = tex2D(_MainTex, i.uv) * _Color;
                col.rgb *= _Emission; // Rendre le disque brillant
                
                return col;
            }
            ENDCG
        }
    }
}