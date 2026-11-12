package com.example.dulni_project

import androidx.credentials.CreatePasswordRequest
import androidx.credentials.Credential
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPasswordOption
import androidx.credentials.PasswordCredential
import androidx.credentials.CreateCredentialResponse
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.example.dulni_project/credential_manager"
    private lateinit var credentialManager: CredentialManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        credentialManager = CredentialManager.create(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "savePassword" -> {
                    val email = call.argument<String>("email")?.trim()
                    val password = call.argument<String>("password")

                    if (email.isNullOrEmpty() || password.isNullOrEmpty()) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "Email and password are required.",
                            null
                        )
                    } else {
                        savePassword(email, password, result)
                    }
                }

                "getPassword" -> getPassword(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun savePassword(
        email: String,
        password: String,
        result: MethodChannel.Result
    ) {
        val request = CreatePasswordRequest(id = email, password = password)

        credentialManager.createCredentialAsync(
            this,
            request,
            null,
            mainExecutor,
            object : CredentialManagerCallback<
                CreateCredentialResponse,
                CreateCredentialException
                > {
                override fun onResult(response: CreateCredentialResponse) {
                    runOnUiThread { result.success(true) }
                }

                override fun onError(e: CreateCredentialException) {
                    runOnUiThread {
                        // Credential saving is optional; it must not undo a successful signup.
                        result.success(false)
                    }
                }
            }
        )
    }

    private fun getPassword(result: MethodChannel.Result) {
        val request = GetCredentialRequest.Builder()
            .addCredentialOption(GetPasswordOption())
            .build()

        credentialManager.getCredentialAsync(
            this,
            request,
            null,
            mainExecutor,
            object : CredentialManagerCallback<
                GetCredentialResponse,
                GetCredentialException
                > {
                override fun onResult(response: GetCredentialResponse) {
                    runOnUiThread {
                        val credential: Credential = response.credential
                        if (credential is PasswordCredential) {
                            result.success(
                                mapOf(
                                    "email" to credential.id,
                                    "password" to credential.password
                                )
                            )
                        } else {
                            result.error(
                                "UNSUPPORTED_CREDENTIAL",
                                "The selected credential is not a password credential.",
                                null
                            )
                        }
                    }
                }

                override fun onError(e: GetCredentialException) {
                    // Includes cancellation/no available credential. Flutter should
                    // continue to allow manual sign-in.
                    runOnUiThread { result.success(null) }
                }
            }
        )
    }
}
