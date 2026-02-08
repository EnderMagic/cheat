package com.example.demo_ai_even.camera

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

object UvcCameraHelper {
    private const val TAG = "UvcCameraHelper"
    
    /**
     * 检查是否有USB相机设备连接
     */
    fun hasUsbCamera(context: Context): Boolean {
        try {
            val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
            if (usbManager == null) {
                Log.w(TAG, "UsbManager 为 null")
                return false
            }
            
            val deviceList = usbManager.deviceList
            Log.d(TAG, "检测到 ${deviceList.size} 个USB设备")
            
            deviceList.values.forEach { device ->
                Log.d(TAG, "USB设备: vendorId=0x${Integer.toHexString(device.vendorId)}, " +
                        "productId=0x${Integer.toHexString(device.productId)}, " +
                        "deviceClass=${device.deviceClass}, " +
                        "deviceSubclass=${device.deviceSubclass}, " +
                        "deviceProtocol=${device.deviceProtocol}")
            }
            
            // 更宽松的检测条件：检查设备类或接口类
            val hasVideoDevice = deviceList.values.any { device ->
                // 方法1: 检查设备类
                val isVideoClass = device.deviceClass == 14 || // USB_CLASS_VIDEO
                        device.deviceSubclass == 1 || // USB_SUBCLASS_VIDEOCONTROL
                        device.deviceProtocol == 1    // USB_PROTOCOL_VIDEO
            
                // 方法2: 检查接口类（更准确）
                var hasVideoInterface = false
                for (i in 0 until device.interfaceCount) {
                    val intf = device.getInterface(i)
                    if (intf.interfaceClass == 14) { // USB_CLASS_VIDEO
                        hasVideoInterface = true
                        Log.d(TAG, "找到视频接口: interface=${i}, subclass=${intf.interfaceSubclass}")
                        break
                    }
                }
                
                val result = isVideoClass || hasVideoInterface
                if (result) {
                    Log.d(TAG, "检测到UVC相机设备: ${device.deviceName}")
                }
                result
            }
            
            Log.d(TAG, "USB相机检测结果: $hasVideoDevice")
            return hasVideoDevice
        } catch (e: Exception) {
            Log.e(TAG, "检测USB相机时出错", e)
            return false
        }
    }
    
    /**
     * 获取USB相机设备列表
     */
    fun getUsbCameras(context: Context): List<UsbDevice> {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
        return usbManager?.deviceList?.values?.filter { device ->
            device.deviceClass == 14 || device.deviceSubclass == 1
        } ?: emptyList()
    }
    
    /**
     * 拍照（简化版本：使用系统相机API）
     * 注意：这是一个简化实现，实际UVC相机需要使用libusb或类似库
     */
    fun capturePhoto(context: Context, callback: (ByteArray?) -> Unit) {
        try {
            // 这里使用一个简化的实现
            // 实际UVC相机需要使用libusb或AndroidUSBCamera库
            // 为了演示，我们返回一个占位符
            Log.w(TAG, "UVC相机拍照功能需要完整的UVC库支持")
            callback(null)
        } catch (e: Exception) {
            Log.e(TAG, "拍照失败", e)
            callback(null)
        }
    }
    
    /**
     * 将Bitmap转换为Base64字符串
     */
    fun bitmapToBase64(bitmap: Bitmap, quality: Int = 80): String {
        val outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
        val byteArray = outputStream.toByteArray()
        return Base64.encodeToString(byteArray, Base64.NO_WRAP)
    }
    
    /**
     * 将Base64字符串转换为ByteArray
     */
    fun base64ToByteArray(base64: String): ByteArray {
        return Base64.decode(base64, Base64.NO_WRAP)
    }
}
