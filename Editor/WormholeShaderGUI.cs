using UnityEngine;
using UnityEditor;
using System.IO;

namespace DarkRelativity
{
    public class WormholeShaderGUI : ShaderGUI
    {
        public enum MetricType
        {
            BlackHole_Schwarzschild,
            Wormhole_Ellis
        }

        private MetricType metric = MetricType.BlackHole_Schwarzschild;
        private int resolution = 512;
        private float maxDistance = 10.0f;
        private float throatRadius = 1.0f;
        private int maxSteps = 2000;
        private float stepSize = 0.01f;

        public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
        {
            // Draw default properties
            base.OnGUI(materialEditor, properties);

            Material targetMat = materialEditor.target as Material;

            // Draw custom LUT baker section
            EditorGUILayout.Space();
            EditorGUILayout.LabelField("Geodesic LUT Baker", EditorStyles.boldLabel);
            
            EditorGUILayout.HelpBox("Baking a Geodesic LUT will physically trace rays to simulate gravity, saving it as a high precision float texture and automatically applying it to the material.", MessageType.Info);

            metric = (MetricType)EditorGUILayout.EnumPopup("Metric Type", metric);
            resolution = EditorGUILayout.IntField("Texture Resolution", resolution);
            maxDistance = EditorGUILayout.FloatField("Max Camera Distance", maxDistance);
            throatRadius = EditorGUILayout.FloatField("Event Horizon / Throat (Rs)", throatRadius);
            maxSteps = EditorGUILayout.IntField("Max Integration Steps", maxSteps);
            
            if (metric == MetricType.BlackHole_Schwarzschild)
                stepSize = EditorGUILayout.FloatField("Integration Step Size (dPhi)", stepSize);
            else
                stepSize = EditorGUILayout.FloatField("Integration Step Size (dL)", stepSize);

            if (GUILayout.Button("Bake and Assign LUT", GUILayout.Height(30)))
            {
                BakeLUT(targetMat);
            }
        }

        private void BakeLUT(Material targetMat)
        {
            Texture2D lut = new Texture2D(resolution, resolution, TextureFormat.RGHalf, false);
            lut.filterMode = FilterMode.Bilinear;
            lut.wrapMode = TextureWrapMode.Clamp;

            Color[] pixels = new Color[resolution * resolution];

            for (int y = 0; y < resolution; y++)
            {
                float v = (float)y / (resolution - 1);
                float theta_initial = v * Mathf.PI; 
                
                EditorUtility.DisplayProgressBar("Baking Geodesic LUT", $"Row {y}/{resolution}", (float)y / resolution);

                for (int x = 0; x < resolution; x++)
                {
                    float u = (float)x / (resolution - 1);
                    float r_initial = Mathf.Lerp(throatRadius, maxDistance, u);

                    Vector2 result;
                    if (metric == MetricType.BlackHole_Schwarzschild)
                    {
                        result = ComputeSchwarzschildDeflection(r_initial, theta_initial);
                    }
                    else
                    {
                        result = ComputeEllisWormholeDeflection(r_initial, theta_initial);
                    }
                    
                    // R = totalPhi, G = UniverseID (-1=Horizon, 0=UniverseA, 1=UniverseB)
                    pixels[y * resolution + x] = new Color(result.x, result.y, 0, 1);
                }
            }

            lut.SetPixels(pixels);
            lut.Apply();

            byte[] exrBytes = lut.EncodeToEXR(Texture2D.EXRFlags.CompressZIP);
            string filename = metric == MetricType.BlackHole_Schwarzschild ? "BlackHoleGeodesicLUT" : "WormholeGeodesicLUT";
            
            string matPath = AssetDatabase.GetAssetPath(targetMat);
            string directory = Path.GetDirectoryName(matPath);
            if (string.IsNullOrEmpty(directory)) directory = "Assets";
            
            string fullPath = Path.Combine(directory, filename + ".exr");
            fullPath = AssetDatabase.GenerateUniqueAssetPath(fullPath);

            File.WriteAllBytes(fullPath, exrBytes);
            AssetDatabase.Refresh();
            
            TextureImporter importer = AssetImporter.GetAtPath(fullPath) as TextureImporter;
            if (importer != null)
            {
                importer.sRGBTexture = false;
                importer.mipmapEnabled = false;
                importer.textureCompression = TextureImporterCompression.Uncompressed;
                importer.wrapMode = TextureWrapMode.Clamp;
                importer.filterMode = FilterMode.Bilinear;
                importer.SaveAndReimport();
            }
            
            Texture2D loadedTex = AssetDatabase.LoadAssetAtPath<Texture2D>(fullPath);
            if (loadedTex != null && targetMat.HasProperty("_GeodesicLUT"))
            {
                targetMat.SetTexture("_GeodesicLUT", loadedTex);
                EditorUtility.SetDirty(targetMat);
            }
            
            Debug.Log($"Geodesic LUT saved successfully to {fullPath} and assigned to Material.");
            EditorUtility.ClearProgressBar();
            Object.DestroyImmediate(lut);
        }

        private Vector2 ComputeSchwarzschildDeflection(float r0, float theta0)
        {
            if (Mathf.Sin(theta0) < 0.0001f)
            {
                if (Mathf.Cos(theta0) > 0) return new Vector2(0.0f, -1.0f); // Straight into horizon
                return new Vector2(0.0f, 0.0f); // Straight out
            }

            float u = 1.0f / r0;
            float v = u * (1.0f / Mathf.Tan(theta0)) * Mathf.Sqrt(Mathf.Max(0.0f, 1.0f - throatRadius * u));
            
            float dphi = stepSize;
            float totalPhi = 0.0f;

            for (int i = 0; i < maxSteps; i++)
            {
                float k1_u = v;
                float k1_v = 1.5f * throatRadius * u * u - u;
                
                float u2 = u + 0.5f * dphi * k1_u;
                float v2 = v + 0.5f * dphi * k1_v;
                float k2_u = v2;
                float k2_v = 1.5f * throatRadius * u2 * u2 - u2;
                
                float u3 = u + 0.5f * dphi * k2_u;
                float v3 = v + 0.5f * dphi * k2_v;
                float k3_u = v3;
                float k3_v = 1.5f * throatRadius * u3 * u3 - u3;
                
                float u4 = u + dphi * k3_u;
                float v4 = v + dphi * k3_v;
                float k4_u = v4;
                float k4_v = 1.5f * throatRadius * u4 * u4 - u4;
                
                u += (dphi / 6.0f) * (k1_u + 2.0f * k2_u + 2.0f * k3_u + k4_u);
                v += (dphi / 6.0f) * (k1_v + 2.0f * k2_v + 2.0f * k3_v + k4_v);
                
                totalPhi += dphi;
                
                if (u > 1.0f / throatRadius) return new Vector2(totalPhi, -1.0f); // Event Horizon
                if (u < 1.0f / maxDistance) break;
            }
            
            return new Vector2(totalPhi, 0.0f); // Escaped to Universe A
        }

        private Vector2 ComputeEllisWormholeDeflection(float r0, float theta0)
        {
            float b0 = throatRadius;
            float b = r0 * Mathf.Sin(theta0);
            
            // If aiming straight at throat
            if (b < 0.0001f) 
            {
                if (Mathf.Cos(theta0) > 0) return new Vector2(0.0f, 1.0f); // Straight through to Universe B
                return new Vector2(0.0f, 0.0f); // Straight out to Universe A
            }

            float l = Mathf.Sqrt(Mathf.Max(0.0f, r0 * r0 - b0 * b0));
            
            // Velocity V_l = dl/dlambda
            float vl = -Mathf.Cos(theta0); 
            float phi = 0.0f;
            float dlambda = stepSize;
            
            for (int i = 0; i < maxSteps; i++)
            {
                float r_sq = b0 * b0 + l * l;
                
                // Euler integration for 2nd order ODE
                float dl = vl * dlambda;
                float dvl = (l * b * b) / (r_sq * r_sq) * dlambda;
                float dphi = b / r_sq * dlambda;
                
                l += dl;
                vl += dvl;
                phi += dphi;
                
                if (l > maxDistance) return new Vector2(phi, 0.0f); // Bounced back to Universe A
                if (l < -maxDistance) return new Vector2(phi, 1.0f); // Crossed throat to Universe B
            }
            
            // If it orbits forever (photon sphere) treat as crossing
            return new Vector2(phi, 1.0f);
        }
    }
}
