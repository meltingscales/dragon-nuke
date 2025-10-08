package com.dragonreboot.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.dragonreboot.app.databinding.ActivityMainBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.*

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private var serviceAccountJson: JSONObject? = null
    private val bucketName = "dragon-reboot-bucket"
    private val client = OkHttpClient()

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

        setupClickListeners()
        updateUI()
    }

    private fun setupClickListeners() {
        binding.btnLoadKey.setOnClickListener {
            pickServiceAccountFile()
        }

        binding.btnTriggerReboot.setOnClickListener {
            triggerReboot()
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
                    
                    Toast.makeText(this, "Service account loaded: $clientEmail", Toast.LENGTH_LONG).show()
                    updateUI()
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

    private fun triggerReboot() {
        if (serviceAccountJson == null) {
            Toast.makeText(this, "Please load a service account key first", Toast.LENGTH_SHORT).show()
            return
        }

        binding.btnTriggerReboot.isEnabled = false
        binding.btnTriggerReboot.text = "Triggering..."

        lifecycleScope.launch {
            try {
                val success = uploadRebootTrigger()
                withContext(Dispatchers.Main) {
                    if (success) {
                        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
                        binding.tvLastTrigger.text = "Last triggered: $timestamp"
                        Toast.makeText(this@MainActivity, "Reboot trigger sent to all servers!", Toast.LENGTH_LONG).show()
                    } else {
                        Toast.makeText(this@MainActivity, "Failed to trigger reboot", Toast.LENGTH_LONG).show()
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@MainActivity, "Error: ${e.message}", Toast.LENGTH_LONG).show()
                }
            } finally {
                withContext(Dispatchers.Main) {
                    binding.btnTriggerReboot.isEnabled = true
                    binding.btnTriggerReboot.text = "🔥 TRIGGER REBOOT"
                }
            }
        }
    }

    private suspend fun uploadRebootTrigger(): Boolean = withContext(Dispatchers.IO) {
        try {
            // Try direct upload to GCP Storage (requires public write access)
            val url = "https://$bucketName.storage.googleapis.com/reboot-trigger.txt"
            
            val requestBody = "REBOOT=TRUE".toRequestBody("text/plain".toMediaType())
            
            val request = Request.Builder()
                .url(url)
                .put(requestBody)
                .build()

            val response = client.newCall(request).execute()
            response.isSuccessful
        } catch (e: IOException) {
            false
        }
    }

    private fun updateUI() {
        val hasKey = serviceAccountJson != null
        binding.btnTriggerReboot.isEnabled = hasKey
        
        if (hasKey) {
            val email = serviceAccountJson?.optString("client_email", "Unknown")
            binding.tvKeyStatus.text = "✅ Key loaded: $email"
            binding.btnLoadKey.text = "🔄 Change Key"
        } else {
            binding.tvKeyStatus.text = "No service account key loaded"
            binding.btnLoadKey.text = "📁 Load Service Account Key"
        }
    }
}