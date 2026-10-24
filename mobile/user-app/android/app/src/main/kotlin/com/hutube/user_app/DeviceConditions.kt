package com.hutube.user_app

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class DeviceConditions(context: Context, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val network = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val handler = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "hutube/device_conditions")
    private val events = EventChannel(messenger, "hutube/device_conditions/events")
    private var sink: EventChannel.EventSink? = null
    private var watching = false
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(n: Network, caps: NetworkCapabilities) = emit()
        override fun onLost(n: Network) = emit()
    }
    private val audioCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(devices: Array<out AudioDeviceInfo>) = emit()
        override fun onAudioDevicesRemoved(devices: Array<out AudioDeviceInfo>) = emit()
    }
    init {
        methods.setMethodCallHandler { call, result ->
            if (call.method == "snapshot") result.success(snapshot()) else result.notImplemented()
        }
        events.setStreamHandler(this)
    }
    private fun snapshot(): Map<String, Boolean> {
        val caps = network.getNetworkCapabilities(network.activeNetwork)
        val connected = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        val wifi = connected && caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true &&
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
        val external = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
            it.type in setOf(AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_LINE_ANALOG, AudioDeviceInfo.TYPE_LINE_DIGITAL,
                AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLE_SPEAKER)
        }
        return mapOf("connected" to connected, "wifi" to wifi, "externalAudio" to external)
    }
    private fun emit() { handler.post { sink?.success(snapshot()) } }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
        if (!watching) {
            network.registerDefaultNetworkCallback(networkCallback)
            audio.registerAudioDeviceCallback(audioCallback, handler)
            watching = true
        }
        emit()
    }
    override fun onCancel(arguments: Any?) {
        sink = null
        if (watching) {
            network.unregisterNetworkCallback(networkCallback)
            audio.unregisterAudioDeviceCallback(audioCallback)
            watching = false
        }
    }
    fun close() {
        onCancel(null)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }
}
