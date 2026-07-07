using UnityEngine;
using UnityEditor;
using System.IO;

namespace DarkRelativity
{
    public class SingularityShaderGUI : ShaderGUI
    {
        public enum MetricType
        {
            BlackHole_Schwarzschild = 0,
            Wormhole_Ellis = 1
        }

        public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
        {
            Material targetMat = materialEditor.target as Material;

            // Find properties
            MaterialProperty analyticMetric = FindProperty("_AnalyticMetric", properties);
            MaterialProperty realRadius = FindProperty("_RealRadius", properties);
            MaterialProperty distortionStrength = FindProperty("_DistortionStrength", properties);
            MaterialProperty distortionPower = FindProperty("_DistortionPower", properties);
            MaterialProperty screenBorderBlend = FindProperty("_ScreenBorderBlendWidth", properties);
            MaterialProperty outerEdgeBlend = FindProperty("_OuterEdgeBlendWidth", properties);
            MaterialProperty maxRings = FindProperty("_MaxRings", properties);
            
            MaterialProperty speedOfLight = FindProperty("_SpeedOfLight", properties);
            MaterialProperty rotationVelocity = FindProperty("_RotationVelocity", properties);
            MaterialProperty beamingIntensity = FindProperty("_BeamingIntensity", properties);
            
            MaterialProperty fringeWidth = FindProperty("_FringeWidth", properties);
            MaterialProperty fringeStrength = FindProperty("_FringeStrength", properties);
            MaterialProperty horizonLensingLimit = FindProperty("_HorizonLensingLimit", properties);
            
            MaterialProperty wormholeSkybox = FindProperty("_WormholeSkybox", properties);
            MaterialProperty skyboxBrightness = FindProperty("_SkyboxBrightness", properties);
            MaterialProperty innerRefraction = FindProperty("_InnerRefraction", properties);
            MaterialProperty innerCurvePower = FindProperty("_InnerCurvePower", properties);
            MaterialProperty edgeBlendWidth = FindProperty("_EdgeBlendWidth", properties);
            MaterialProperty timeDilationShift = FindProperty("_TimeDilationShift", properties);
            
            MaterialProperty useGeodesicLUT = FindProperty("_UseGeodesicLUT", properties);
            MaterialProperty geodesicLUT = FindProperty("_GeodesicLUT", properties);
            MaterialProperty lutMaxDistance = FindProperty("_LUTMaxDistance", properties);
            
            MaterialProperty useManualProbe = FindProperty("_UseManualProbe", properties, false);
            MaterialProperty manualEnvironmentMap = FindProperty("_ManualEnvironmentMap", properties);

            MaterialProperty otherSingularityPos = FindProperty("_OtherSingularityPos", properties);
            MaterialProperty otherSingularityRadius = FindProperty("_OtherSingularityRadius", properties);
            MaterialProperty otherSingularityType = FindProperty("_OtherSingularityType", properties);

            // Auto-detect other singularity in the active scene to dynamically lens each other
            Vector4 otherPos = Vector4.zero;
            float otherRadius = 0f;
            float otherType = 0f; // 0 = None, 1 = Black Hole, 2 = Wormhole
            
            Renderer[] renderers = Object.FindObjectsOfType<Renderer>();
            foreach (var r in renderers)
            {
                if (r == null || !r.gameObject.activeInHierarchy) continue;
                
                Material m = r.sharedMaterial;
                if (m == null || m == targetMat) continue;
                
                Shader s = m.shader;
                if (s == null) continue;
                
                if (s.name.Contains("DarkRelativity/Singularity"))
                {
                    Transform t = r.transform;
                    otherPos = t.position;
                    
                    float scale = Mathf.Max(t.lossyScale.x, Mathf.Max(t.lossyScale.y, t.lossyScale.z));
                    float realRad = m.HasProperty("_RealRadius") ? m.GetFloat("_RealRadius") : 0.15f;
                    
                    // Schwarzschild Black Hole apparent horizon is lensed to 2.598x, Wormhole throat is 1.0x
                    bool isBH = m.IsKeywordEnabled("_ANALYTICMETRIC_BLACKHOLE");
                    if (isBH)
                    {
                        otherType = 1.0f; // Black Hole
                        otherRadius = scale * realRad * 2.598076f;
                    }
                    else
                    {
                        otherType = 2.0f; // Wormhole
                        otherRadius = scale * realRad * 1.0f;
                    }
                    break; // Support one other singularity for interaction
                }
            }
            
            otherSingularityPos.vectorValue = otherPos;
            otherSingularityRadius.floatValue = otherRadius;
            otherSingularityType.floatValue = otherType;

            // 1. Choose Singularity Type at the top
            MetricType metric = (MetricType)analyticMetric.floatValue;
            EditorGUI.BeginChangeCheck();
            metric = (MetricType)EditorGUILayout.EnumPopup("Singularity Type", metric);
            if (EditorGUI.EndChangeCheck())
            {
                analyticMetric.floatValue = (float)metric;
                targetMat.SetFloat("_AnalyticMetric", (float)metric);
                
                // Toggle proper keyword fallback if not using LUT
                if (metric == MetricType.BlackHole_Schwarzschild)
                {
                    targetMat.EnableKeyword("_ANALYTICMETRIC_BLACKHOLE");
                    targetMat.DisableKeyword("_ANALYTICMETRIC_WORMHOLE");
                }
                else
                {
                    targetMat.DisableKeyword("_ANALYTICMETRIC_BLACKHOLE");
                    targetMat.EnableKeyword("_ANALYTICMETRIC_WORMHOLE");
                }
                EditorUtility.SetDirty(targetMat);
            }

            // 2. Shared Core Settings
            EditorGUILayout.Space();
            EditorGUILayout.LabelField("Core Lensing Settings", EditorStyles.boldLabel);
            materialEditor.ShaderProperty(realRadius, "Event Horizon / Throat Radius");
            materialEditor.ShaderProperty(distortionStrength, "Lensing Strength");
            materialEditor.ShaderProperty(distortionPower, "Lensing Falloff");
            materialEditor.ShaderProperty(screenBorderBlend, "Screen Border Blend Width");
            materialEditor.ShaderProperty(outerEdgeBlend, "Outer Mesh Edge Blend Width");
            materialEditor.ShaderProperty(maxRings, "Max Light Repeats (Rings)");

            // 3. Shared Relativistic Physics
            EditorGUILayout.Space();
            EditorGUILayout.LabelField("Relativistic Physics Settings", EditorStyles.boldLabel);
            materialEditor.ShaderProperty(speedOfLight, "Speed of Light (c)");
            materialEditor.ShaderProperty(rotationVelocity, "Rotation Velocity");
            materialEditor.ShaderProperty(beamingIntensity, "Relativistic Beaming Intensity");

            // 4. Type-Specific Parameters
            if (metric == MetricType.BlackHole_Schwarzschild)
            {
                EditorGUILayout.Space();
                EditorGUILayout.LabelField("Black Hole Settings", EditorStyles.boldLabel);
                materialEditor.ShaderProperty(fringeWidth, "Fringe Width");
                materialEditor.ShaderProperty(fringeStrength, "Fringe Strength");
                materialEditor.ShaderProperty(horizonLensingLimit, "Horizon Lensing Limit");
            }
            else
            {
                EditorGUILayout.Space();
                EditorGUILayout.LabelField("Wormhole Settings", EditorStyles.boldLabel);
                materialEditor.ShaderProperty(wormholeSkybox, "Wormhole Skybox (Universe B)");
                materialEditor.ShaderProperty(skyboxBrightness, "Skybox Brightness");
                materialEditor.ShaderProperty(innerRefraction, "Inner Refraction (Analytic)");
                materialEditor.ShaderProperty(innerCurvePower, "Inner Curve Power (Analytic)");
                materialEditor.ShaderProperty(edgeBlendWidth, "Edge Blend Width");
                materialEditor.ShaderProperty(timeDilationShift, "Time Dilation Shift (Doppler)");
            }

            // 5. Environment Fallbacks
            EditorGUILayout.Space();
            EditorGUILayout.LabelField("Environment Fallbacks", EditorStyles.boldLabel);
            if (useManualProbe != null)
            {
                materialEditor.ShaderProperty(useManualProbe, "Use Manual Environment Map");
            }
            materialEditor.ShaderProperty(manualEnvironmentMap, "Manual Environment Map");


            // 6. Geodesic Baking (with parameter persistence)
            EditorGUILayout.Space();
            EditorGUILayout.LabelField("Geodesic LUT Baker", EditorStyles.boldLabel);
            materialEditor.ShaderProperty(useGeodesicLUT, "Use Geodesic LUT");
            materialEditor.ShaderProperty(geodesicLUT, "Geodesic LUT Texture");
            materialEditor.ShaderProperty(lutMaxDistance, "LUT Max Distance");

            // Fetch persisted baker fields
            MaterialProperty bakerResProp = FindProperty("_BakerResolution", properties);
            MaterialProperty bakerMaxStepsProp = FindProperty("_BakerMaxSteps", properties);
            MaterialProperty bakerStepSizeProp = FindProperty("_BakerStepSize", properties);

            int resolution = (int)bakerResProp.floatValue;
            float maxDistance = lutMaxDistance.floatValue; // Directly synced with LUT Max Distance shader property!
            float throatRadius = 1.0f; // Scale-invariant integration unit (Rs = 1.0)
            int maxSteps = (int)bakerMaxStepsProp.floatValue;
            float stepSize = bakerStepSizeProp.floatValue;

            // Ensure sensible defaults if properties are unitialized (0)
            if (resolution <= 0) resolution = 512;
            if (maxDistance <= 0.0f) maxDistance = 10.0f;
            if (maxSteps <= 0) maxSteps = 10000;
            if (stepSize <= 0.0f) stepSize = 0.005f;

            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField("Baker Parameters (Saved in Material)", EditorStyles.miniBoldLabel);
            
            EditorGUI.BeginChangeCheck();
            resolution = EditorGUILayout.IntField("Baker Resolution", resolution);
            maxSteps = EditorGUILayout.IntField("Baker Max Steps", maxSteps);
            stepSize = EditorGUILayout.FloatField("Baker Step Size", stepSize);
            
            if (EditorGUI.EndChangeCheck())
            {
                bakerResProp.floatValue = resolution;
                bakerMaxStepsProp.floatValue = maxSteps;
                bakerStepSizeProp.floatValue = stepSize;
            }

            if (GUILayout.Button("Bake and Assign LUT", GUILayout.Height(30)))
            {
                BakeLUT(targetMat, metric, resolution, maxDistance, throatRadius, maxSteps, stepSize);
                GUIUtility.ExitGUI();
            }
            EditorGUILayout.EndVertical();
        }

        private void BakeLUT(Material targetMat, MetricType metric, int resolution, float maxDistance, float throatRadius, int maxSteps, float stepSize)
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
                    float u_sq = u * u; // Allocate more resolution to the volatile area near the horizon
                    float r_initial = Mathf.Lerp(throatRadius * 1.001f, maxDistance, u_sq);

                    Vector2 result;
                    if (metric == MetricType.BlackHole_Schwarzschild)
                    {
                        result = ComputeSchwarzschildDeflection(r_initial, theta_initial, throatRadius, maxDistance, maxSteps, stepSize);
                    }
                    else
                    {
                        result = ComputeEllisWormholeDeflection(r_initial, theta_initial, throatRadius, maxDistance, maxSteps, stepSize);
                    }
                    
                    pixels[y * resolution + x] = new Color(result.x, result.y, 0, 1);
                }
            }

            lut.SetPixels(pixels);
            lut.Apply();

            byte[] exrBytes = lut.EncodeToEXR(Texture2D.EXRFlags.CompressZIP);
            string filename = metric == MetricType.BlackHole_Schwarzschild ? "BlackHoleGeodesicLUT" : "WormholeGeodesicLUT";
            
            string shaderPath = AssetDatabase.GetAssetPath(targetMat.shader);
            string shaderDir = Path.GetDirectoryName(shaderPath);
            if (string.IsNullOrEmpty(shaderDir)) shaderDir = "Assets";
            
            string lutDir = Path.Combine(shaderDir, "LUTs");
            if (!Directory.Exists(lutDir))
            {
                Directory.CreateDirectory(lutDir);
            }
            
            string fullPath = Path.Combine(lutDir, filename + ".exr");

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

        // Shared helper for calculating the flat-space asymptotic correction
        private float GetAsymptoticCorrection(float b, float rFinal)
        {
            return Mathf.Asin(Mathf.Clamp01(b / rFinal));
        }

        private Vector2 ComputeSchwarzschildDeflection(float r0, float theta0, float Rs, float maxDistance, int maxSteps, float stepSize)
        {
            if (Mathf.Sin(theta0) < 0.0001f)
            {
                if (Mathf.Cos(theta0) > 0) return new Vector2(0.0f, 0.0f); // Event Horizon (0.0)
                return new Vector2(0.0f, 0.5f); // Escape (0.5)
            }

            float u = 1.0f / r0;
            float v = u * (1.0f / Mathf.Tan(theta0)) * Mathf.Sqrt(Mathf.Max(0.0f, 1.0f - Rs * u));
            
            float b = (r0 * Mathf.Sin(theta0)) / Mathf.Sqrt(Mathf.Max(0.0001f, 1.0f - Rs / r0));
            float dphi = stepSize;
            float totalPhi = 0.0f;

            for (int i = 0; i < maxSteps; i++)
            {
                float k1_u = v;
                float k1_v = 1.5f * Rs * u * u - u;
                
                float u2 = u + 0.5f * dphi * k1_u;
                float v2 = v + 0.5f * dphi * k1_v;
                float k2_u = v2;
                float k2_v = 1.5f * Rs * u2 * u2 - u2;
                
                float u3 = u + 0.5f * dphi * k2_u;
                float v3 = v + 0.5f * dphi * k2_v;
                float k3_u = v3;
                float k3_v = 1.5f * Rs * u3 * u3 - u3;
                
                float u4 = u + dphi * k3_u;
                float v4 = v + dphi * k3_v;
                float k4_u = v4;
                float k4_v = 1.5f * Rs * u4 * u4 - u4;
                
                u += (dphi / 6.0f) * (k1_u + 2.0f * k2_u + 2.0f * k3_u + k4_u);
                v += (dphi / 6.0f) * (k1_v + 2.0f * k2_v + 2.0f * k3_v + k4_v);
                
                totalPhi += dphi;
                
                if (float.IsNaN(u) || float.IsInfinity(u)) return new Vector2(totalPhi, 0.0f); // Singularity/numerical instability
                if (u > 1.0f / Rs) return new Vector2(totalPhi, 0.0f); // Event Horizon (0.0)
                if (u < 1.0f / maxDistance)
                {
                    totalPhi += GetAsymptoticCorrection(b, 1.0f / u);
                    float flatSpacePhi_esc = Mathf.PI - theta0;
                    return new Vector2(totalPhi - flatSpacePhi_esc, 0.5f); // Escaped to Universe A (0.5)
                }
            }
            
            // If we exceeded maxSteps without escaping, treat as Event Horizon (0.0)
            return new Vector2(totalPhi, 0.0f);
        }

        private Vector2 ComputeEllisWormholeDeflection(float r0, float theta0, float b0, float maxDistance, int maxSteps, float stepSize)
        {
            float b = r0 * Mathf.Sin(theta0);
            
            if (b < 0.0001f) 
            {
                if (Mathf.Cos(theta0) > 0) return new Vector2(0.0f, 1.0f); // Universe B (1.0)
                return new Vector2(0.0f, 0.5f); // Universe A (0.5)
            }

            float l = Mathf.Sqrt(Mathf.Max(0.0f, r0 * r0 - b0 * b0));
            
            float vl = -Mathf.Cos(theta0); 
            float phi = 0.0f;
            float dlambda = stepSize;
            
            for (int i = 0; i < maxSteps; i++)
            {
                float r_sq = b0 * b0 + l * l;
                
                float dl = vl * dlambda;
                float dvl = (l * b * b) / (r_sq * r_sq) * dlambda;
                float dphi = b / r_sq * dlambda;
                
                l += dl;
                vl += dvl;
                phi += dphi;
                
                if (l > maxDistance)
                {
                    float r_final = Mathf.Sqrt(b0 * b0 + l * l);
                    phi += GetAsymptoticCorrection(b, r_final);
                    float flatSpacePhi = Mathf.PI - theta0;
                    return new Vector2(phi - flatSpacePhi, 0.5f); // Bounced to Universe A (0.5)
                }
                if (l < -maxDistance)
                {
                    float r_final = Mathf.Sqrt(b0 * b0 + l * l);
                    phi += GetAsymptoticCorrection(b, r_final);
                    return new Vector2(phi - Mathf.PI, 1.0f); // Crossed to Universe B (1.0)
                }
            }
            
            if (l >= 0)
            {
                float flatSpacePhi = Mathf.PI - theta0;
                return new Vector2(phi - flatSpacePhi, 0.5f); // Timeout in Universe A (0.5)
            }
            else
            {
                return new Vector2(phi - Mathf.PI, 1.0f); // Timeout in Universe B (1.0)
            }
        }
    }
}
