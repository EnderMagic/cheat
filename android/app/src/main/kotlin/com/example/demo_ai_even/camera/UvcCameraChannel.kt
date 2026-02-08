package com.example.demo_ai_even.camera

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class UvcCameraChannel(private val activity: Activity) {
    private val channelName = "com.example.demo_ai_even/uvc_camera"
    private var methodChannel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null
    private val REQUEST_CODE_CAMERA = 1001

    fun initChannel(flutterEngine: FlutterEngine) {
        Log.d("UvcCameraChannel", "初始化MethodChannel: $channelName")
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d("UvcCameraChannel", "收到方法调用: ${call.method}")
            when (call.method) {
                "initialize" -> {
                    Log.d("UvcCameraChannel", "处理initialize方法")
                    val hasCamera = UvcCameraHelper.hasUsbCamera(activity)
                    Log.d("UvcCameraChannel", "检测到USB相机: $hasCamera")
                    // 即使没有检测到USB相机，也返回true，允许使用系统相机
                    // 这样用户至少可以使用系统相机进行拍照
                    result.success(mapOf("hasCamera" to true, "isUsbCamera" to hasCamera))
                }
                "capture" -> {
                    pendingResult = result
                    // 使用系统相机API作为临时方案
                    // 实际UVC相机需要使用专门的库
                    openCamera()
                }
                "dispose" -> {
                    dispose()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun openCamera() {
        try {
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
            if (intent.resolveActivity(activity.packageManager) != null) {
                activity.startActivityForResult(intent, REQUEST_CODE_CAMERA)
            } else {
                pendingResult?.error("NO_CAMERA", "没有可用的相机", null)
                pendingResult = null
            }
        } catch (e: Exception) {
            Log.e("UvcCameraChannel", "打开相机失败", e)
            pendingResult?.error("CAMERA_ERROR", e.message, null)
            pendingResult = null
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_CODE_CAMERA) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val imageBitmap = data.extras?.get("data") as? Bitmap
                if (imageBitmap != null) {
                    val outputStream = ByteArrayOutputStream()
                    imageBitmap.compress(Bitmap.CompressFormat.JPEG, 80, outputStream)
                    val imageBytes = outputStream.toByteArray()
                    pendingResult?.success(mapOf("imageBytes" to imageBytes))
                } else {
                    pendingResult?.error("NO_IMAGE", "没有获取到图片", null)
                }
            } else {
                pendingResult?.error("CANCELLED", "用户取消了拍照", null)
            }
            pendingResult = null
        }
    }

    private fun dispose() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
    }
}
