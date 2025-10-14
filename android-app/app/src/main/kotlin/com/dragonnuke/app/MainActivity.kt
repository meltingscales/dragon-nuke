package com.dragonnuke.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Base64
import android.util.Log
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.dragonnuke.app.databinding.ActivityMainBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.PKCS8EncodedKeySpec
import java.text.SimpleDateFormat
import java.util.*

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private var serviceAccountJson: JSONObject? = null
    private val bucketName = "dragon-nuke-bucket"
    private val client = OkHttpClient()

    companion object {
        private const val TAG = "DragonNuke"
        private const val PREFS_NAME = "dragon_nuke_prefs"
        private const val KEY_SERVICE_ACCOUNT = "service_account_json"
    }

    private val filePickerLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data?.data?.let { uri ->
                loadServiceAccountKey(uri)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        loadSavedServiceAccount()
        setupClickListeners()
        updateUI()
    }

    private fun loadSavedServiceAccount() {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val savedJson = prefs.getString(KEY_SERVICE_ACCOUNT, null)

        if (savedJson != null) {
            try {
                serviceAccountJson = JSONObject(savedJson)
                val clientEmail = serviceAccountJson?.optString("client_email", "Unknown")
                Toast.makeText(this, "Restored saved key: $clientEmail", Toast.LENGTH_SHORT).show()

                // Test connection on boot
                testConnection()
            } catch (e: Exception) {
                // If saved JSON is corrupted, clear it
                prefs.edit().remove(KEY_SERVICE_ACCOUNT).apply()
            }
        }
    }

    private fun setupClickListeners() {
        binding.btnLoadKey.setOnClickListener {
            pickServiceAccountFile()
        }

        binding.btnTriggerNuke.setOnClickListener {
            triggerNuke()
        }
    }

    private fun pickServiceAccountFile() {
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "application/json"
            addCategory(Intent.CATEGORY_OPENABLE)
        }
        filePickerLauncher.launch(intent)
    }

    private fun loadServiceAccountKey(uri: Uri) {
        try {
            val inputStream = contentResolver.openInputStream(uri)
            val jsonString = inputStream?.bufferedReader()?.use { it.readText() }

            if (jsonString != null) {
                serviceAccountJson = JSONObject(jsonString)
                val clientEmail = serviceAccountJson?.optString("client_email", "Unknown")

                // Validate it's a service account key
                if (serviceAccountJson?.optString("type") == "service_account" &&
                    serviceAccountJson?.has("private_key") == true &&
                    serviceAccountJson?.has("client_email") == true) {

                    // Save to SharedPreferences
                    val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                    prefs.edit().putString(KEY_SERVICE_ACCOUNT, jsonString).apply()

                    Toast.makeText(this, "Service account loaded: $clientEmail", Toast.LENGTH_LONG).show()
                    updateUI()

                    // Test connection immediately
                    testConnection()
                } else {
                    Toast.makeText(this, "Invalid service account key file", Toast.LENGTH_LONG).show()
                    serviceAccountJson = null
                }
            }
        } catch (e: Exception) {
            Toast.makeText(this, "Error loading file: ${e.message}", Toast.LENGTH_LONG).show()
            serviceAccountJson = null
        }
    }

    private fun testConnection() {
        // Show checking status
        binding.tvConnectionStatus.text = "🔍 Checking GCP connection..."
        binding.tvConnectionStatus.setTextColor(getColor(android.R.color.darker_gray))

        lifecycleScope.launch {
            try {
                val connectionWorks = withContext(Dispatchers.IO) {
                    try {
                        val url = "https://$bucketName.storage.googleapis.com/"
                        val request = Request.Builder()
                            .url(url)
                            .head()
                            .build()

                        val response = client.newCall(request).execute()
                        response.isSuccessful || response.code == 403 // 403 means bucket exists but no read access
                    } catch (e: IOException) {
                        false
                    }
                }

                if (!connectionWorks) {
                    binding.tvConnectionStatus.text = "⚠️ Cannot connect to GCP bucket. Check network."
                    binding.tvConnectionStatus.setTextColor(getColor(android.R.color.holo_orange_dark))
                } else {
                    binding.tvConnectionStatus.text = "✅ GCP connection verified"
                    binding.tvConnectionStatus.setTextColor(getColor(android.R.color.holo_green_dark))
                }
            } catch (e: Exception) {
                binding.tvConnectionStatus.text = "⚠️ Connection test failed: ${e.message}"
                binding.tvConnectionStatus.setTextColor(getColor(android.R.color.holo_orange_dark))
            }
        }
    }

    private fun triggerNuke() {
        if (serviceAccountJson == null) {
            Toast.makeText(this, "Please load a service account key first", Toast.LENGTH_SHORT).show()
            return
        }

        binding.btnTriggerNuke.isEnabled = false
        binding.btnTriggerNuke.text = "Triggering..."

        lifecycleScope.launch {
            try {
                val success = uploadNukeTrigger()
                withContext(Dispatchers.Main) {
                    if (success) {
                        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
                        binding.tvLastTrigger.text = "Last triggered: $timestamp"
                        Toast.makeText(this@MainActivity, "Nuke trigger sent to all servers!", Toast.LENGTH_LONG).show()
                    } else {
                        Toast.makeText(this@MainActivity, "Failed to trigger nuke", Toast.LENGTH_LONG).show()
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@MainActivity, "Error: ${e.message}", Toast.LENGTH_LONG).show()
                }
            } finally {
                withContext(Dispatchers.Main) {
                    binding.btnTriggerNuke.isEnabled = true
                    binding.btnTriggerNuke.text = "🔥 TRIGGER NUKE"
                }
            }
        }
    }

    private suspend fun getAccessToken(): String? = withContext(Dispatchers.IO) {
        try {
            val serviceAccount = serviceAccountJson ?: return@withContext null

            val clientEmail = serviceAccount.getString("client_email")
            val privateKeyPem = serviceAccount.getString("private_key")
                .replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replace("\\n", "")
                .replace("\n", "")
                .trim()

            // Create JWT
            val now = System.currentTimeMillis() / 1000
            val exp = now + 3600

            val header = JSONObject().apply {
                put("alg", "RS256")
                put("typ", "JWT")
            }

            val payload = JSONObject().apply {
                put("iss", clientEmail)
                put("scope", "https://www.googleapis.com/auth/devstorage.read_write")
                put("aud", "https://oauth2.googleapis.com/token")
                put("exp", exp)
                put("iat", now)
            }

            val headerEncoded = Base64.encodeToString(
                header.toString().toByteArray(),
                Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
            )
            val payloadEncoded = Base64.encodeToString(
                payload.toString().toByteArray(),
                Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
            )

            val signatureInput = "$headerEncoded.$payloadEncoded"

            // Sign with private key
            val keyBytes = Base64.decode(privateKeyPem, Base64.DEFAULT)
            val keySpec = PKCS8EncodedKeySpec(keyBytes)
            val keyFactory = KeyFactory.getInstance("RSA")
            val privateKey = keyFactory.generatePrivate(keySpec)

            val signature = Signature.getInstance("SHA256withRSA")
            signature.initSign(privateKey)
            signature.update(signatureInput.toByteArray())
            val signatureBytes = signature.sign()

            val signatureEncoded = Base64.encodeToString(
                signatureBytes,
                Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
            )

            val jwt = "$signatureInput.$signatureEncoded"

            Log.d(TAG, "Generated JWT, requesting access token...")

            // Exchange JWT for access token
            val tokenRequestBody = FormBody.Builder()
                .add("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
                .add("assertion", jwt)
                .build()

            val tokenRequest = Request.Builder()
                .url("https://oauth2.googleapis.com/token")
                .post(tokenRequestBody)
                .build()

            val tokenResponse = client.newCall(tokenRequest).execute()
            val tokenResponseBody = tokenResponse.body?.string()

            Log.d(TAG, "Token response code: ${tokenResponse.code}")
            Log.d(TAG, "Token response: $tokenResponseBody")

            if (tokenResponse.isSuccessful && tokenResponseBody != null) {
                val tokenJson = JSONObject(tokenResponseBody)
                tokenJson.getString("access_token")
            } else {
                Log.e(TAG, "Failed to get access token: $tokenResponseBody")
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting access token", e)
            null
        }
    }

    private suspend fun uploadNukeTrigger(): Boolean = withContext(Dispatchers.IO) {
        try {
            val accessToken = getAccessToken()
            if (accessToken == null) {
                Log.e(TAG, "Failed to obtain access token")
                return@withContext false
            }

            Log.d(TAG, "Got access token, uploading file...")

            val url = "https://$bucketName.storage.googleapis.com/nuke-trigger.txt"

            Log.d(TAG, "Attempting to upload nuke trigger to: $url")

            val requestBody = "NUKE=TRUE".toRequestBody("text/plain".toMediaType())

            val request = Request.Builder()
                .url(url)
                .put(requestBody)
                .header("Authorization", "Bearer $accessToken")
                .build()

            val response = client.newCall(request).execute()
            val responseBody = response.body?.string()

            Log.d(TAG, "Upload response code: ${response.code}")
            Log.d(TAG, "Upload response message: ${response.message}")
            Log.d(TAG, "Upload response body: $responseBody")

            if (!response.isSuccessful) {
                Log.e(TAG, "Upload failed with code ${response.code}: $responseBody")
            }

            response.isSuccessful
        } catch (e: IOException) {
            Log.e(TAG, "IOException during upload", e)
            false
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error during upload", e)
            false
        }
    }

    private fun updateUI() {
        val hasKey = serviceAccountJson != null
        binding.btnTriggerNuke.isEnabled = hasKey

        if (hasKey) {
            val email = serviceAccountJson?.optString("client_email", "Unknown")
            binding.tvKeyStatus.text = "✅ Key loaded: $email"
            binding.btnLoadKey.text = "🔄 Change Key"
        } else {
            binding.tvKeyStatus.text = "No service account key loaded"
            binding.btnLoadKey.text = "📁 Load Service Account Key"
            binding.tvConnectionStatus.text = "Load a service account key to check connection"
            binding.tvConnectionStatus.setTextColor(getColor(android.R.color.darker_gray))
        }
    }
}