using UdonSharp;
using UnityEngine;
using VRC.SDKBase;
using VRC.Udon;

namespace DarkRelativity
{
    [UdonBehaviourSyncMode(BehaviourSyncMode.None)]
    public class PlayerRelativityUdon : UdonSharpBehaviour
    {
        [Tooltip("The simulated speed of light in meters per second. Lower this (e.g. to 2.0 or 4.0) to see massive relativistic effects just by walking/running!")]
        public float speedOfLight = 4.0f;

        [Tooltip("Add all materials that should be updated with player velocity parameters.")]
        public Material[] materialsToUpdate;

        [Tooltip("Optional: Drag your screen-space CameraRelativity material here.")]
        public Material cameraRelativityMaterial;

        private void Update()
        {
            VRCPlayerApi localPlayer = Networking.LocalPlayer;
            if (localPlayer == null) return;

            // Retrieve the local player's actual velocity in world space
            Vector3 velocity = localPlayer.GetVelocity();
            float speed = velocity.magnitude;

            // Get the local player's head tracking data (representing the camera orientation in VR or Desktop)
            VRCPlayerApi.TrackingData headData = localPlayer.GetTrackingData(VRCPlayerApi.TrackingDataType.Head);
            Vector3 headForward = headData.rotation * Vector3.forward;

            // Calculate forward speed relative to where the player's camera is looking
            // Positive = moving forward (Blueshift/aberration compression), Negative = moving backward (Redshift/expansion)
            float forwardSpeed = Vector3.Dot(velocity, headForward);

            // Compute speed fraction beta (v/c), clamped below 1.0 to prevent division by zero / infinite gamma
            float c = Mathf.Max(speedOfLight, 0.001f);
            float speedFraction = Mathf.Clamp(speed / c, 0.0f, 0.999f);

            // Calculate the velocity direction (world space)
            Vector3 velocityDir = (speed > 0.001f) ? velocity.normalized : Vector3.forward;

            // Set variables directly on materials (Shader.SetGlobal is not supported in Udon)
            Vector4 velDir4 = new Vector4(velocityDir.x, velocityDir.y, velocityDir.z, 0.0f);
            
            if (materialsToUpdate != null)
            {
                for (int i = 0; i < materialsToUpdate.Length; i++)
                {
                    Material mat = materialsToUpdate[i];
                    if (mat != null)
                    {
                        mat.SetVector("_VelocityDir", velDir4);
                        mat.SetFloat("_SpeedFraction", speedFraction);
                        mat.SetFloat("_SpeedOfLight", c);
                    }
                }
            }

            // Explicitly sync the camera relativity material if assigned
            if (cameraRelativityMaterial != null)
            {
                cameraRelativityMaterial.SetFloat("_PlayerSpeed", forwardSpeed);
                cameraRelativityMaterial.SetFloat("_SpeedOfLight", c);
            }
        }
    }
}
