package com.andrew.alarm

import WarmAlarmApi
import io.flutter.embedding.engine.plugins.FlutterPlugin

class WarmAlarmPlugin : FlutterPlugin, WarmAlarmApi {
    companion object {
        private const val TAG = "WarmAlarmPlugin"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        WarmAlarmApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        WarmAlarmApi.setUp(binding.binaryMessenger, null)
    }

    override fun getPlatformName(callback: (Result<String?>) -> Unit) {
        callback(Result.success("Android ${android.os.Build.VERSION.RELEASE}"))
    }
}