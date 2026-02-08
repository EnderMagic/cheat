package com.example.demo_ai_even

import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.example.demo_ai_even.bluetooth.BleChannelHelper
import com.example.demo_ai_even.bluetooth.BleManager
import com.example.demo_ai_even.cpp.Cpp
import com.example.demo_ai_even.camera.UvcCameraChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity(), EventChannel.StreamHandler {

    private var uvcCameraChannel: UvcCameraChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Cpp.init()
        BleManager.instance.initBluetooth(this)
        uvcCameraChannel = UvcCameraChannel(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i(this::class.simpleName, "configureFlutterEngine 被调用")
        BleChannelHelper.initChannel(this, flutterEngine)
        // 如果uvcCameraChannel还未初始化，则初始化它
        if (uvcCameraChannel == null) {
            Log.i(this::class.simpleName, "创建 UvcCameraChannel")
            uvcCameraChannel = UvcCameraChannel(this)
        }
        Log.i(this::class.simpleName, "初始化 UvcCameraChannel")
        uvcCameraChannel?.initChannel(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        uvcCameraChannel?.handleActivityResult(requestCode, resultCode, data)
    }

    /// Interface - EventChannel.StreamHandler
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.i(this::class.simpleName,"EventChannel.StreamHandler - OnListen: arguments = $arguments ,events = $events")
        BleChannelHelper.addEventSink(arguments as String?, events)
    }

    /// Interface - EventChannel.StreamHandler
    override fun onCancel(arguments: Any?) {
        Log.i(this::class.simpleName,"EventChannel.StreamHandler - OnCancel: arguments = $arguments")
        BleChannelHelper.removeEventSink(arguments as String?)
    }

}
