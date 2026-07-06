using UnityEngine;

namespace DarkRelativity
{
    [ExecuteAlways]
    public class RelativisticObject : MonoBehaviour
    {
        public Vector3 velocityDirection = Vector3.forward;
        [Range(0f, 0.999f)] public float speedFractionOfC = 0.8f;
        
        private Renderer cachedRenderer;
        private Material originalMaterial;
        private Material relativisticMaterial;

        void OnEnable()
        {
            cachedRenderer = GetComponent<Renderer>();
            SetupMaterials();
        }

        void OnDisable()
        {
            RestoreMaterials();
        }

        void Update()
        {
            if (cachedRenderer == null)
            {
                cachedRenderer = GetComponent<Renderer>();
                SetupMaterials();
            }

            if (cachedRenderer != null && relativisticMaterial != null)
            {
                // Sync texture and color in case the original material changes in the editor
                if (originalMaterial != null)
                {
                    Texture srcTex = originalMaterial.mainTexture;
                    if (srcTex == null)
                    {
                        if (originalMaterial.HasProperty("_BaseMap")) srcTex = originalMaterial.GetTexture("_BaseMap");
                        else if (originalMaterial.HasProperty("_MainTex")) srcTex = originalMaterial.GetTexture("_MainTex");
                    }

                    if (srcTex != null)
                    {
                        relativisticMaterial.mainTexture = srcTex;
                        
                        if (originalMaterial.HasProperty("_BaseMap"))
                        {
                            relativisticMaterial.mainTextureScale = originalMaterial.GetTextureScale("_BaseMap");
                            relativisticMaterial.mainTextureOffset = originalMaterial.GetTextureOffset("_BaseMap");
                        }
                        else if (originalMaterial.HasProperty("_MainTex"))
                        {
                            relativisticMaterial.mainTextureScale = originalMaterial.GetTextureScale("_MainTex");
                            relativisticMaterial.mainTextureOffset = originalMaterial.GetTextureOffset("_MainTex");
                        }
                    }

                    Color tintColor = Color.white;
                    bool hasColorValue = false;
                    
                    if (originalMaterial.HasProperty("_Color"))
                    {
                        tintColor = originalMaterial.color;
                        hasColorValue = true;
                    }
                    else if (originalMaterial.HasProperty("_BaseColor"))
                    {
                        tintColor = originalMaterial.GetColor("_BaseColor");
                        hasColorValue = true;
                    }

                    if (hasColorValue && relativisticMaterial.HasProperty("_BaseColor"))
                    {
                        relativisticMaterial.SetColor("_BaseColor", tintColor);
                    }
                }

                // Apply special relativity parameters to the material
                if (relativisticMaterial.HasProperty("_VelocityDir"))
                {
                    relativisticMaterial.SetVector("_VelocityDir", velocityDirection.normalized);
                }
                if (relativisticMaterial.HasProperty("_SpeedFraction"))
                {
                    relativisticMaterial.SetFloat("_SpeedFraction", speedFractionOfC);
                }
            }
        }

        private Mesh originalMesh;
        private Bounds originalSkinnedBounds;

        private void SetupMaterials()
        {
            if (cachedRenderer == null) return;

            // Disable occlusion culling so the object is never culled when out of its original bounds
            cachedRenderer.allowOcclusionWhenDynamic = false;

            // Expand bounds to prevent frustum culling when the shader displaces/skews the object's vertices
            if (cachedRenderer is SkinnedMeshRenderer smr)
            {
                originalSkinnedBounds = smr.localBounds;
                smr.localBounds = new Bounds(Vector3.zero, Vector3.one * 10000f);
            }
            else
            {
                MeshFilter mf = GetComponent<MeshFilter>();
                if (mf != null)
                {
                    originalMesh = mf.sharedMesh;
                    if (originalMesh != null)
                    {
                        // Instantiates the mesh to safely modify bounds without affecting the project asset
                        Mesh instancedMesh = mf.mesh; 
                        instancedMesh.bounds = new Bounds(Vector3.zero, Vector3.one * 10000f);
                    }
                }
            }

            Material[] mats = cachedRenderer.sharedMaterials;
            if (mats == null || mats.Length == 0) return;

            // If already swapped, do not replace again
            if (mats[0] != null && mats[0].shader != null && mats[0].shader.name == "DarkRelativity/SpecialRelativityObject")
            {
                relativisticMaterial = mats[0];
                return;
            }

            // Save the original material
            originalMaterial = mats[0];

            // Create a runtime instance of the relativistic material
            Shader relativisticShader = Shader.Find("DarkRelativity/SpecialRelativityObject");
            if (relativisticShader != null)
            {
                relativisticMaterial = new Material(relativisticShader);
                relativisticMaterial.name = originalMaterial.name + " (Relativistic)";

                // Replace the renderer's materials array with ONLY the relativistic material
                cachedRenderer.sharedMaterials = new Material[] { relativisticMaterial };
            }
        }

        private void RestoreMaterials()
        {
            if (cachedRenderer != null)
            {
                cachedRenderer.allowOcclusionWhenDynamic = true;

                if (cachedRenderer is SkinnedMeshRenderer smr)
                {
                    smr.localBounds = originalSkinnedBounds;
                }
                else
                {
                    MeshFilter mf = GetComponent<MeshFilter>();
                    if (mf != null && originalMesh != null)
                    {
                        mf.sharedMesh = originalMesh;
                    }
                }

                if (originalMaterial != null)
                {
                    cachedRenderer.sharedMaterials = new Material[] { originalMaterial };
                }

                originalMesh = null;
                originalMaterial = null;
                relativisticMaterial = null;
            }
        }
    }
}
