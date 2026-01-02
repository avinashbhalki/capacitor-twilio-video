package com.avinashbhalki.capacitor.twilio.video

import android.Manifest
import android.content.Intent
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission

@CapacitorPlugin(
    name = "TwilioVideo",
    permissions = [
        Permission(strings = [Manifest.permission.CAMERA], alias = "camera"),
        Permission(strings = [Manifest.permission.RECORD_AUDIO], alias = "audio")
    ]
)
class TwilioVideoPlugin : Plugin() {

    companion object {
        private var pluginInstance: TwilioVideoPlugin? = null

        fun getInstance(): TwilioVideoPlugin? {
            return pluginInstance
        }
    }

    init {
        pluginInstance = this
    }

    @PluginMethod
    fun joinRoom(call: PluginCall) {
        val token = call.getString("token")
        val roomName = call.getString("roomName")
        val roomId = call.getString("roomId")

        if (token == null || token.isEmpty()) {
            call.reject("Token is required")
            return
        }

        if ((roomName == null || roomName.isEmpty()) && (roomId == null || roomId.isEmpty())) {
            call.reject("Either roomName or roomId must be provided")
            return
        }

        val intent = Intent(activity, VideoCallActivity::class.java)
        intent.putExtra("token", token)
        intent.putExtra("roomName", roomName ?: roomId)

        activity.startActivity(intent)
        call.resolve()
    }

    @PluginMethod
    fun leaveRoom(call: PluginCall) {
        VideoCallActivity.getInstance()?.disconnect()
        call.resolve()
    }

    @PluginMethod
    fun muteAudio(call: PluginCall) {
        val muted = call.getBoolean("muted", false) ?: false
        VideoCallActivity.getInstance()?.muteAudio(muted)
        call.resolve()
    }

    @PluginMethod
    fun enableVideo(call: PluginCall) {
        val enabled = call.getBoolean("enabled", true) ?: true
        VideoCallActivity.getInstance()?.enableVideo(enabled)
        call.resolve()
    }

    @PluginMethod
    fun flipCamera(call: PluginCall) {
        VideoCallActivity.getInstance()?.flipCamera()
        call.resolve()
    }

    @PluginMethod
    fun setSpeaker(call: PluginCall) {
        val enabled = call.getBoolean("enabled", true) ?: true
        VideoCallActivity.getInstance()?.setSpeaker(enabled)
        call.resolve()
    }

    fun notifyRoomConnected(roomName: String) {
        val data = JSObject()
        data.put("roomName", roomName)
        notifyListeners("roomConnected", data)
    }

    fun notifyRoomDisconnected(roomName: String, reason: String?) {
        val data = JSObject()
        data.put("roomName", roomName)
        if (reason != null) {
            data.put("reason", reason)
        }
        notifyListeners("roomDisconnected", data)
    }

    fun notifyParticipantJoined(identity: String) {
        val data = JSObject()
        data.put("identity", identity)
        notifyListeners("participantJoined", data)
    }

    fun notifyParticipantLeft(identity: String) {
        val data = JSObject()
        data.put("identity", identity)
        notifyListeners("participantLeft", data)
    }

    fun notifyNetworkQualityChanged(identity: String, level: Int, isLocal: Boolean) {
        val data = JSObject()
        data.put("identity", identity)
        data.put("level", level)
        data.put("isLocal", isLocal)
        notifyListeners("networkQualityChanged", data)
    }

    fun notifyDominantSpeakerChanged(identity: String?) {
        val data = JSObject()
        data.put("identity", identity)
        notifyListeners("dominantSpeakerChanged", data)
    }

    fun notifyRoomAutoClosed(reason: String) {
        val data = JSObject()
        data.put("reason", reason)
        notifyListeners("roomAutoClosed", data)
    }

    fun notifyRoomError(code: String, message: String, isFatal: Boolean) {
        val data = JSObject()
        data.put("code", code)
        data.put("message", message)
        data.put("isFatal", isFatal)
        notifyListeners("roomError", data)
    }
}
