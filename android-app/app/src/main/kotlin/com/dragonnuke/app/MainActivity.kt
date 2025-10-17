package com.dragonnuke.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import android.view.MotionEvent
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
    private val heartbeatFileName = "hosts-heartbeat.json"
    private val client = OkHttpClient()

    // ARM/DISARM state
    private var isArmed = false

    // Hold-to-trigger state
    private var holdStartTime = 0L
    private var isHolding = false
    private val holdDurationMs = 5000L // 5 seconds

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

        // ARM/DISARM button toggle
        binding.btnArmDisarm.setOnClickListener {
            isArmed = !isArmed
            updateArmDisarmButton()
            updateTriggerButtonState()
        }

        // Hold-to-trigger functionality
        binding.btnTriggerNuke.setOnTouchListener { view, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    if (!isArmed) {
                        Toast.makeText(this, "System must be ARMED first", Toast.LENGTH_SHORT).show()
                        return@setOnTouchListener true
                    }

                    isHolding = true
                    holdStartTime = System.currentTimeMillis()
                    startHoldProgress()
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (isHolding) {
                        val holdDuration = System.currentTimeMillis() - holdStartTime
                        isHolding = false

                        if (holdDuration >= holdDurationMs) {
                            // Successfully held for 5 seconds, trigger nuke
                            triggerNuke()
                        } else {
                            // Released too early
                            binding.btnTriggerNuke.text = "🔥 TRIGGER NUKE\n(Hold for 5 seconds)"
                            Toast.makeText(this, "Hold for full 5 seconds to trigger", Toast.LENGTH_SHORT).show()
                        }
                    }
                    true
                }
                else -> false
            }
        }

        binding.btnRefreshValue.setOnClickListener {
            refreshCurrentValue()
        }

        binding.btnRefreshHeartbeat.setOnClickListener {
            refreshHeartbeat()
        }
    }

    private fun updateArmDisarmButton() {
        if (isArmed) {
            binding.btnArmDisarm.text = "🔒 ARMED"
            binding.btnArmDisarm.backgroundTintList = getColorStateList(android.R.color.holo_orange_dark)
        } else {
            binding.btnArmDisarm.text = "🔓 DISARMED"
            binding.btnArmDisarm.backgroundTintList = getColorStateList(android.R.color.darker_gray)
        }
    }

    private fun updateTriggerButtonState() {
        val hasKey = serviceAccountJson != null
        binding.btnTriggerNuke.isEnabled = hasKey && isArmed

        // Update visual appearance based on armed state
        if (isArmed && hasKey) {
            binding.btnTriggerNuke.alpha = 1.0f
            binding.btnTriggerNuke.backgroundTintList = getColorStateList(android.R.color.holo_red_dark)
        } else {
            binding.btnTriggerNuke.alpha = 0.4f
            binding.btnTriggerNuke.backgroundTintList = getColorStateList(android.R.color.darker_gray)
        }
    }

    private val holdProgressHandler = Handler(Looper.getMainLooper())
    private val holdProgressRunnable = object : Runnable {
        override fun run() {
            if (!isHolding) return

            val elapsed = System.currentTimeMillis() - holdStartTime
            val progress = (elapsed.toFloat() / holdDurationMs * 100).toInt()

            if (elapsed < holdDurationMs) {
                val remaining = ((holdDurationMs - elapsed) / 1000.0).toInt() + 1
                binding.btnTriggerNuke.text = "🔥 TRIGGERING...\n${remaining}s remaining (${progress}%)"
                holdProgressHandler.postDelayed(this, 100)
            } else {
                binding.btnTriggerNuke.text = "🔥 FIRING NUKE!"
            }
        }
    }

    private fun startHoldProgress() {
        holdProgressHandler.post(holdProgressRunnable)
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

                    // Refresh current value
                    refreshCurrentValue()
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

                    // Refresh current value when connection is verified
                    refreshCurrentValue()
                    // Refresh heartbeat when connection is verified
                    refreshHeartbeat()
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

        if (!isArmed) {
            Toast.makeText(this, "System must be ARMED first", Toast.LENGTH_SHORT).show()
            return
        }

        binding.btnTriggerNuke.isEnabled = false
        binding.btnArmDisarm.isEnabled = false
        binding.btnTriggerNuke.text = "Triggering..."

        lifecycleScope.launch {
            try {
                val success = uploadNukeTrigger()
                withContext(Dispatchers.Main) {
                    if (success) {
                        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
                        binding.tvLastTrigger.text = "Last triggered: $timestamp"
                        Toast.makeText(this@MainActivity, "Nuke trigger sent to all servers!", Toast.LENGTH_LONG).show()

                        // Auto-disarm after successful trigger
                        isArmed = false
                        updateArmDisarmButton()

                        // Refresh current value after successful trigger
                        refreshCurrentValue()
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
                    binding.btnTriggerNuke.text = "🔥 TRIGGER NUKE\n(Hold for 5 seconds)"
                    binding.btnArmDisarm.isEnabled = true
                    updateTriggerButtonState()
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

    private fun refreshCurrentValue() {
        if (serviceAccountJson == null) {
            binding.tvCurrentValue.text = "No service account key loaded"
            binding.tvCurrentValue.setTextColor(getColor(android.R.color.darker_gray))
            return
        }

        binding.tvCurrentValue.text = "Loading..."
        binding.tvCurrentValue.setTextColor(getColor(android.R.color.darker_gray))
        binding.btnRefreshValue.isEnabled = false

        lifecycleScope.launch {
            try {
                val currentValue = getCurrentTriggerValue()
                withContext(Dispatchers.Main) {
                    if (currentValue != null) {
                        binding.tvCurrentValue.text = currentValue
                        // Color code based on value
                        if (currentValue.contains("NUKE=TRUE", ignoreCase = true)) {
                            binding.tvCurrentValue.setTextColor(getColor(android.R.color.holo_red_dark))
                        } else if (currentValue.contains("safe", ignoreCase = true)) {
                            binding.tvCurrentValue.setTextColor(getColor(android.R.color.holo_green_dark))
                        } else {
                            binding.tvCurrentValue.setTextColor(getColor(android.R.color.black))
                        }
                    } else {
                        binding.tvCurrentValue.text = "Failed to fetch current value"
                        binding.tvCurrentValue.setTextColor(getColor(android.R.color.holo_red_dark))
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    binding.tvCurrentValue.text = "Error: ${e.message}"
                    binding.tvCurrentValue.setTextColor(getColor(android.R.color.holo_red_dark))
                }
            } finally {
                withContext(Dispatchers.Main) {
                    binding.btnRefreshValue.isEnabled = true
                }
            }
        }
    }

    private suspend fun getCurrentTriggerValue(): String? = withContext(Dispatchers.IO) {
        try {
            val accessToken = getAccessToken()
            if (accessToken == null) {
                Log.e(TAG, "Failed to obtain access token for reading")
                return@withContext null
            }

            Log.d(TAG, "Got access token, fetching current trigger value...")

            val url = "https://$bucketName.storage.googleapis.com/nuke-trigger.txt"

            val request = Request.Builder()
                .url(url)
                .get()
                .header("Authorization", "Bearer $accessToken")
                .build()

            val response = client.newCall(request).execute()
            val responseBody = response.body?.string()

            Log.d(TAG, "Fetch response code: ${response.code}")
            Log.d(TAG, "Fetch response body: $responseBody")

            if (response.isSuccessful && responseBody != null) {
                responseBody.trim()
            } else {
                Log.e(TAG, "Failed to fetch current value with code ${response.code}: $responseBody")
                null
            }
        } catch (e: IOException) {
            Log.e(TAG, "IOException during fetch", e)
            null
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error during fetch", e)
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

    private fun refreshHeartbeat() {
        if (serviceAccountJson == null) {
            binding.tvHeartbeatStatus.text = "No service account key loaded"
            binding.tvHeartbeatStatus.setTextColor(getColor(android.R.color.darker_gray))
            binding.tvStaleHeartbeats.text = "No service account key loaded"
            binding.tvStaleHeartbeats.setTextColor(getColor(android.R.color.darker_gray))
            return
        }

        binding.tvHeartbeatStatus.text = "Loading heartbeats..."
        binding.tvHeartbeatStatus.setTextColor(getColor(android.R.color.darker_gray))
        binding.tvStaleHeartbeats.text = "Loading..."
        binding.tvStaleHeartbeats.setTextColor(getColor(android.R.color.darker_gray))
        binding.btnRefreshHeartbeat.isEnabled = false

        lifecycleScope.launch {
            try {
                val heartbeats = getHeartbeats()
                withContext(Dispatchers.Main) {
                    if (heartbeats.isNotEmpty()) {
                        val now = System.currentTimeMillis()
                        val oneHourAgo = now - (60 * 60 * 1000) // 1 hour in milliseconds

                        // Parse timestamps and separate into recent and stale
                        val allParsed = heartbeats.mapNotNull { (hostname, timestamp) ->
                            val time = try {
                                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).apply {
                                    timeZone = TimeZone.getTimeZone("UTC")
                                }.parse(timestamp.replace("Z", ""))?.time ?: 0L
                            } catch (e: Exception) {
                                0L
                            }

                            if (time > 0L) {
                                Triple(hostname, timestamp, time)
                            } else {
                                null
                            }
                        }

                        // Split into recent (last hour) and stale (older than 1 hour)
                        val recentHeartbeats = allParsed.filter { it.third >= oneHourAgo }
                            .sortedByDescending { it.third }
                        val staleHeartbeats = allParsed.filter { it.third < oneHourAgo }
                            .sortedByDescending { it.third }

                        // Display recent heartbeats
                        if (recentHeartbeats.isNotEmpty()) {
                            val heartbeatText = buildString {
                                recentHeartbeats.forEach { (hostname, _, time) ->
                                    val ageMinutes = ((now - time) / 1000 / 60).toInt()
                                    append("$hostname: ${ageMinutes}m ago\n")
                                }
                            }
                            binding.tvHeartbeatStatus.text = heartbeatText.trim()
                            binding.tvHeartbeatStatus.setTextColor(getColor(android.R.color.black))
                        } else {
                            binding.tvHeartbeatStatus.text = "No hosts found in last hour"
                            binding.tvHeartbeatStatus.setTextColor(getColor(android.R.color.darker_gray))
                        }

                        // Display stale heartbeats
                        if (staleHeartbeats.isNotEmpty()) {
                            val staleText = buildString {
                                staleHeartbeats.forEach { (hostname, _, time) ->
                                    val ageHours = ((now - time) / 1000 / 60 / 60).toInt()
                                    val ageMinutes = ((now - time) / 1000 / 60).toInt() % 60
                                    if (ageHours > 0) {
                                        append("$hostname: ${ageHours}h ${ageMinutes}m ago\n")
                                    } else {
                                        append("$hostname: ${ageMinutes}m ago\n")
                                    }
                                }
                            }
                            binding.tvStaleHeartbeats.text = staleText.trim()
                            binding.tvStaleHeartbeats.setTextColor(getColor(android.R.color.holo_orange_dark))
                        } else {
                            binding.tvStaleHeartbeats.text = "No stale hosts"
                            binding.tvStaleHeartbeats.setTextColor(getColor(android.R.color.darker_gray))
                        }
                    } else {
                        binding.tvHeartbeatStatus.text = "No hosts found"
                        binding.tvHeartbeatStatus.setTextColor(getColor(android.R.color.darker_gray))
                        binding.tvStaleHeartbeats.text = "No hosts found"
                        binding.tvStaleHeartbeats.setTextColor(getColor(android.R.color.darker_gray))
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    binding.tvHeartbeatStatus.text = "Error: ${e.message}"
                    binding.tvHeartbeatStatus.setTextColor(getColor(android.R.color.holo_red_dark))
                    binding.tvStaleHeartbeats.text = "Error: ${e.message}"
                    binding.tvStaleHeartbeats.setTextColor(getColor(android.R.color.holo_red_dark))
                }
            } finally {
                withContext(Dispatchers.Main) {
                    binding.btnRefreshHeartbeat.isEnabled = true
                }
            }
        }
    }

    private suspend fun getHeartbeats(): Map<String, String> = withContext(Dispatchers.IO) {
        try {
            val accessToken = getAccessToken()
            if (accessToken == null) {
                Log.e(TAG, "Failed to obtain access token for heartbeats")
                return@withContext emptyMap()
            }

            Log.d(TAG, "Got access token, fetching heartbeats...")

            // List files in hosts-heartbeat/ prefix
            val url = "https://storage.googleapis.com/storage/v1/b/$bucketName/o?prefix=hosts-heartbeat/"

            val request = Request.Builder()
                .url(url)
                .get()
                .header("Authorization", "Bearer $accessToken")
                .build()

            val response = client.newCall(request).execute()
            val responseBody = response.body?.string()

            Log.d(TAG, "List response code: ${response.code}")

            if (response.isSuccessful && responseBody != null) {
                val json = JSONObject(responseBody)
                val items = json.optJSONArray("items")
                val heartbeats = mutableMapOf<String, String>()

                if (items != null) {
                    for (i in 0 until items.length()) {
                        val item = items.getJSONObject(i)
                        val name = item.getString("name")
                        // Extract hostname from path like "hosts-heartbeat/hostname.txt"
                        if (name.startsWith("hosts-heartbeat/") && name.endsWith(".txt")) {
                            val hostname = name.substring("hosts-heartbeat/".length, name.length - 4)
                            // Fetch the timestamp from the file
                            val fileUrl = "https://$bucketName.storage.googleapis.com/$name"
                            val fileRequest = Request.Builder()
                                .url(fileUrl)
                                .get()
                                .header("Authorization", "Bearer $accessToken")
                                .build()
                            val fileResponse = client.newCall(fileRequest).execute()
                            val timestamp = fileResponse.body?.string()?.trim()
                            if (timestamp != null) {
                                heartbeats[hostname] = timestamp
                            }
                        }
                    }
                }

                heartbeats
            } else {
                Log.e(TAG, "Failed to list heartbeats with code ${response.code}: $responseBody")
                emptyMap()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching heartbeats", e)
            emptyMap()
        }
    }

    private fun updateUI() {
        val hasKey = serviceAccountJson != null
        binding.btnArmDisarm.isEnabled = hasKey
        binding.btnRefreshValue.isEnabled = hasKey
        binding.btnRefreshHeartbeat.isEnabled = hasKey

        // Update ARM/DISARM button appearance
        updateArmDisarmButton()

        // Update trigger button based on both key and armed state
        updateTriggerButtonState()

        if (hasKey) {
            val email = serviceAccountJson?.optString("client_email", "Unknown")
            binding.tvKeyStatus.text = "✅ Key loaded: $email"
            binding.btnLoadKey.text = "🔄 Change Key"
        } else {
            binding.tvKeyStatus.text = "No service account key loaded"
            binding.btnLoadKey.text = "📁 Load Service Account Key"
            binding.tvConnectionStatus.text = "Load a service account key to check connection"
            binding.tvConnectionStatus.setTextColor(getColor(android.R.color.darker_gray))
            binding.tvCurrentValue.text = "No service account key loaded"
            binding.tvCurrentValue.setTextColor(getColor(android.R.color.darker_gray))
            binding.tvHeartbeatStatus.text = "No service account key loaded"
            binding.tvHeartbeatStatus.setTextColor(getColor(android.R.color.darker_gray))
            binding.tvStaleHeartbeats.text = "No service account key loaded"
            binding.tvStaleHeartbeats.setTextColor(getColor(android.R.color.darker_gray))
        }
    }
}