package com.memorybox.memorybox

import android.content.ContentResolver
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val APP_CHANNEL = "com.memorybox.memorybox/app_launcher"
    private val SCREENSHOT_CHANNEL = "com.memorybox.memorybox/screenshots"

    private var screenshotObserver: ContentObserver? = null
    private var eventSink: EventChannel.EventSink? = null
    private var lastScreenshotTimestamp: Long = System.currentTimeMillis()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // App launcher channel (existing)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "bringToForeground") {
                    bringToForeground()
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }

        // Screenshot detection event channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startScreenshotObserver()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    stopScreenshotObserver()
                }
            })
    }

    private fun startScreenshotObserver() {
        if (screenshotObserver != null) return

        val handler = Handler(Looper.getMainLooper())
        screenshotObserver = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                if (uri == null) return
                handler.postDelayed({
                    checkForNewScreenshot()
                }, 500) // Small delay to let the file be fully written
            }
        }

        val contentUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        contentResolver.registerContentObserver(
            contentUri,
            true,
            screenshotObserver!!
        )
    }

    private fun stopScreenshotObserver() {
        screenshotObserver?.let {
            contentResolver.unregisterContentObserver(it)
        }
        screenshotObserver = null
    }

    private fun checkForNewScreenshot() {
        try {
            val projection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.DATE_ADDED
            )

            val selection = "${MediaStore.Images.Media.DATE_ADDED} > ?"
            val selectionArgs = arrayOf((lastScreenshotTimestamp / 1000).toString())
            val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"

            val cursor = contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )

            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
                    val dataIndex = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                    val dateIndex = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)

                    val name = it.getString(nameIndex).lowercase()
                    val path = it.getString(dataIndex)
                    val dateAdded = it.getLong(dateIndex)

                    // Check if it's a screenshot by filename
                    val isScreenshot = name.contains("screenshot") ||
                            name.contains("screencap") ||
                            name.contains("screen_shot") ||
                            name.contains("screen-shot") ||
                            name.contains("scrnshot") ||
                            path.lowercase().contains("/screenshots/")

                    if (isScreenshot && dateAdded > lastScreenshotTimestamp / 1000) {
                        lastScreenshotTimestamp = dateAdded * 1000
                        // Send screenshot path to Flutter
                        eventSink?.success(mapOf(
                            "path" to path,
                            "name" to it.getString(nameIndex),
                            "timestamp" to dateAdded
                        ))
                    }
                }
            }
        } catch (e: Exception) {
            eventSink?.error("SCREENSHOT_ERROR", e.message, null)
        }
    }

    private fun bringToForeground() {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }

    override fun onDestroy() {
        stopScreenshotObserver()
        super.onDestroy()
    }
}
