package com.skyspire.spiregame

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter engine and bridges the AperturePane's file-picker
 * ("canvas uploads") to the native system picker.
 *
 * We DO NOT use the `file_picker` pub package — version 10.x switched to a
 * Kotlin-only plugin layout that collides with Flutter's built-in Kotlin
 * plugin, and 8.x is EOL. A hand-rolled MethodChannel is simpler and
 * ships zero extra Dalvik classes.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CANVAS_CHANNEL = "spire/canvas-picker"
        private const val PICK_REQUEST = 0x7A12
    }

    private var pendingResult: MethodChannel.Result? = null
    private var allowMultiple: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANVAS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> {
                        if (pendingResult != null) {
                            result.success(emptyList<String>())
                            return@setMethodCallHandler
                        }
                        allowMultiple = (call.argument<Boolean>("allowMultiple")) ?: false
                        val types = call.argument<List<String>>("types") ?: emptyList()
                        pendingResult = result
                        launchPicker(types)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchPicker(types: List<String>) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
            if (types.isNotEmpty()) {
                putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
            }
        }
        try {
            startActivityForResult(intent, PICK_REQUEST)
        } catch (t: Throwable) {
            pendingResult?.success(emptyList<String>())
            pendingResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_REQUEST) return
        val sink = pendingResult ?: return
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            sink.success(emptyList<String>())
            return
        }
        val uris = mutableListOf<Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) {
                clip.getItemAt(i)?.uri?.let { uris.add(it) }
            }
        } else {
            data.data?.let { uris.add(it) }
        }
        val paths = uris.mapNotNull { it.toString().takeIf { s -> s.isNotEmpty() } }
        sink.success(paths)
    }
}
