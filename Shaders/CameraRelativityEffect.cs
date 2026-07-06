using UnityEngine;

namespace DarkRelativity
{
    [ExecuteAlways]
    [RequireComponent(typeof(Camera))]
    public class CameraRelativityEffect : MonoBehaviour
    {
        public Material relativityMaterial;
        
        [Header("Physics Settings")]
        [Tooltip("The simulated speed of light. Lower this to make walking feel like warp speed!")]
        public float speedOfLight = 10.0f;
        
        [Tooltip("Drag the player object (with Transform, Rigidbody, or CharacterController) here.")]
        public Transform playerTransform;
        
        [Tooltip("Manual speed override (if not using playerTransform)")]
        public float manualPlayerSpeed = 0.0f;

        private Vector3 lastPosition;
        private Vector3 calculatedVelocity;

        private void OnEnable()
        {
            if (playerTransform != null)
            {
                lastPosition = playerTransform.position;
            }
            else
            {
                lastPosition = transform.position;
            }
        }

        private void OnRenderImage(RenderTexture source, RenderTexture destination)
        {
            if (relativityMaterial == null)
            {
                Graphics.Blit(source, destination);
                return;
            }

            float forwardSpeed = manualPlayerSpeed;
            Transform target = (playerTransform != null) ? playerTransform : transform;

            // Track and calculate velocity
            Vector3 velocity = Vector3.zero;
            bool velocityFound = false;

            if (playerTransform != null)
            {
                // Try Rigidbody
                Rigidbody rb = playerTransform.GetComponent<Rigidbody>();
                if (rb != null)
                {
                    velocity = rb.velocity;
                    velocityFound = true;
                }
                
                // Try CharacterController
                if (!velocityFound)
                {
                    CharacterController cc = playerTransform.GetComponent<CharacterController>();
                    if (cc != null)
                    {
                        velocity = cc.velocity;
                        velocityFound = true;
                    }
                }
            }

            // Fallback: calculate velocity manually using position delta over time
            if (!velocityFound)
            {
                float dt = Time.deltaTime;
                if (dt > 0.0001f)
                {
                    Vector3 currentPos = target.position;
                    calculatedVelocity = (currentPos - lastPosition) / dt;
                    lastPosition = currentPos;
                }
                velocity = calculatedVelocity;
            }
            else
            {
                // Keep last position updated even when using component velocity
                lastPosition = target.position;
            }

            // Find speed along the camera's forward looking direction
            forwardSpeed = Vector3.Dot(velocity, transform.forward);

            // Send the data to the shader
            relativityMaterial.SetFloat("_PlayerSpeed", forwardSpeed);
            relativityMaterial.SetFloat("_SpeedOfLight", speedOfLight);

            // Blit the screen
            Graphics.Blit(source, destination, relativityMaterial);
        }
    }
}
