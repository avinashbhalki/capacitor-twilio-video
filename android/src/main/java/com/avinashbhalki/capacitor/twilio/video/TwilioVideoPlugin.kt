package com.avinashbhalki.capacitor.twilio.video

import android.Manifest
import android.content.Intent
import android.util.Log
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission
import com.twilio.video.Room

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
        val identity = call.getString("identity")
        val role = call.getString("role")
        val tenantId = call.getInt("tenantId")

        if (token == null || token.isEmpty()) {
            call.reject("Token is required")
            return
        }

        if ((roomName == null || roomName.isEmpty()) && (roomId == null || roomId.isEmpty())) {
            call.reject("Either roomName or roomId must be provided")
            return
        }

        // Validate role if provided
        if (role != null && !listOf("mht", "cct", "patient").contains(role)) {
            call.reject("Invalid role. Allowed values: mht, cct, patient")
            return
        }

        val intent = Intent(activity, VideoCallActivity::class.java)
        intent.putExtra("token", token)
        intent.putExtra("roomName", roomName ?: roomId)
        intent.putExtra("identity", identity)
        intent.putExtra("role", role)
        if (tenantId != null) {
            intent.putExtra("tenantId", tenantId)
        }

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

    @PluginMethod
    fun sendUsersList(call: PluginCall) {
        Log.d("TwilioVideoPlugin", "sendUsersList method invoked")

        val selectedRoleKey = call.getString("selectedRoleKey")
        val usersArray = call.getArray("users")

        if (selectedRoleKey == null || selectedRoleKey.isEmpty()) {
            Log.e("TwilioVideoPlugin", "sendUsersList failed: selectedRoleKey is required")
            call.reject("selectedRoleKey is required")
            return
        }

        if (!listOf("mht", "cct", "patient", "participant").contains(selectedRoleKey)) {
            Log.e("TwilioVideoPlugin", "sendUsersList failed: Invalid selectedRoleKey: $selectedRoleKey")
            call.reject("Invalid selectedRoleKey. Allowed values: mht, cct, patient, participant")
            return
        }

        val users = mutableListOf<Map<String, String>>()
        if (usersArray != null) {
            Log.d("TwilioVideoPlugin", "sendUsersList parsing ${usersArray.length()} users")
            for (i in 0 until usersArray.length()) {
                try {
                    val userObj = usersArray.getJSONObject(i)
                    val id = userObj.optString("id", "")
                    val userId = userObj.optString("user_id", "")
                    val fullName = userObj.optString("full_name", "")

                    if (id.isNotEmpty() && userId.isNotEmpty() && fullName.isNotEmpty()) {
                        Log.d("TwilioVideoPlugin", "sendUsersList parsed user: $fullName")
                        users.add(mapOf(
                            "id" to id,
                            "user_id" to userId,
                            "full_name" to fullName
                        ))
                    } else {
                        Log.w("TwilioVideoPlugin", "sendUsersList skipping incomplete user at index $i")
                    }
                } catch (e: Exception) {
                    Log.e("TwilioVideoPlugin", "sendUsersList error parsing user at index $i: ${e.message}")
                }
            }
        } else {
            Log.d("TwilioVideoPlugin", "sendUsersList received null users array")
        }

        Log.i("TwilioVideoPlugin", "sendUsersList calling handleUsersList with ${users.size} users for role: $selectedRoleKey")
        VideoCallActivity.getInstance()?.handleUsersList(selectedRoleKey, users)
        call.resolve()
    }

    @PluginMethod
    fun sendFormsList(call: PluginCall) {
        Log.d("TwilioVideoPlugin", "sendFormsList method invoked")

        val formsArray = call.getArray("forms")
        val forms = mutableListOf<Map<String, Any>>()

        if (formsArray != null) {
            Log.d("TwilioVideoPlugin", "sendFormsList parsing ${formsArray.length()} forms")
            for (i in 0 until formsArray.length()) {
                try {
                    val formObj = formsArray.getJSONObject(i)
                    val formMap = mutableMapOf<String, Any>()

                    formObj.keys().forEach { key ->
                        val value = formObj.get(key)
                        formMap[key] = value
                    }

                    forms.add(formMap)
                    Log.d("TwilioVideoPlugin", "sendFormsList parsed form: ${formObj.optString("name", "Unknown")}")
                } catch (e: Exception) {
                    Log.e("TwilioVideoPlugin", "sendFormsList error parsing form at index $i: ${e.message}")
                }
            }
        } else {
            Log.d("TwilioVideoPlugin", "sendFormsList received null forms array")
        }

        Log.i("TwilioVideoPlugin", "sendFormsList calling handleFormsList with ${forms.size} forms")
        VideoCallActivity.getInstance()?.handleFormsList(forms)
        call.resolve()
    }

    fun notifyRoomConnected(roomName: String) {
        val data = JSObject()
        data.put("roomName", roomName)
        notifyListeners("roomConnected", data)
    }

    fun notifyRoomDisconnected(room: com.twilio.video.Room) {
        // Build room object structure
        val roomData = JSObject()
        roomData.put("sid", room.sid)
        roomData.put("name", room.name)
        roomData.put("state", roomStateToString(room.state))

        // Add local participant
        room.localParticipant?.let { localParticipant ->
            val localParticipantData = JSObject()
            localParticipantData.put("sid", localParticipant.sid)
            localParticipantData.put("identity", localParticipant.identity)
            roomData.put("localParticipant", localParticipantData)
        }

        // Add remote participants
        val remoteParticipants = mutableListOf<JSObject>()
        room.remoteParticipants.forEach { participant ->
            val participantData = JSObject()
            participantData.put("sid", participant.sid)
            participantData.put("identity", participant.identity)
            remoteParticipants.add(participantData)
        }
        roomData.put("remoteParticipants", remoteParticipants)

        val data = JSObject()
        data.put("room", roomData)
        notifyListeners("roomDisconnected", data)
    }

    private fun roomStateToString(state: com.twilio.video.Room.State): String {
        return when (state) {
            com.twilio.video.Room.State.CONNECTING -> "connecting"
            com.twilio.video.Room.State.CONNECTED -> "connected"
            com.twilio.video.Room.State.RECONNECTING -> "reconnecting"
            com.twilio.video.Room.State.DISCONNECTED -> "disconnected"
        }
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

    fun notifyRoleSelected(selectedRoleKey: String, identity: String?, role: String?, tenantId: Int?, roomName: String?, roomSID: String?, secondParticipantRole: String?, secondParticipantIdentity: String?) {
        val data = JSObject()
        data.put("selectedRoleKey", selectedRoleKey)
        if (identity != null) data.put("identity", identity)
        if (role != null) data.put("role", role)
        if (tenantId != null) data.put("tenantId", tenantId)
        if (roomName != null) data.put("roomName", roomName)
        if (roomSID != null) data.put("roomSID", roomSID)
        if (secondParticipantRole != null) data.put("secondParticipantRole", secondParticipantRole)
        if (secondParticipantIdentity != null) data.put("secondParticipantIdentity", secondParticipantIdentity)
        notifyListeners("roleSelected", data)
    }

    fun notifyUsersListLoaded(selectedRoleKey: String, userCount: Int) {
        val data = JSObject()
        data.put("selectedRoleKey", selectedRoleKey)
        data.put("userCount", userCount)
        notifyListeners("usersListLoaded", data)
    }

    fun notifyUserSelected(id: String, userId: String, fullName: String, selectedRoleKey: String, tenantId: Int?, role: String?, roomName: String?, roomSID: String?) {
        val data = JSObject()
        data.put("id", id)
        data.put("user_id", userId)
        data.put("full_name", fullName)
        data.put("selectedRoleKey", selectedRoleKey)
        if (tenantId != null) data.put("tenantId", tenantId)
        if (role != null) data.put("role", role)
        if (roomName != null) data.put("roomName", roomName)
        if (roomSID != null) data.put("roomSID", roomSID)
        notifyListeners("userSelected", data)
    }

    fun notifyPopupDismissed(popupType: String, reason: String) {
        val data = JSObject()
        data.put("popupType", popupType)
        data.put("reason", reason)
        notifyListeners("popupDismissed", data)
    }

    fun notifyPopupError(message: String, popupType: String) {
        val data = JSObject()
        data.put("message", message)
        data.put("popupType", popupType)
        notifyListeners("popupError", data)
    }

    fun notifySplitScreenRequested() {
        val data = JSObject()
        data.put("timestamp", System.currentTimeMillis())
        notifyListeners("splitScreenRequested", data)
    }

    fun notifyFormSelected(form: Map<String, Any>) {
        val data = JSObject()

        form["id"]?.let { data.put("id", it) }
        form["name"]?.let { data.put("name", it) }
        form["links"]?.let { data.put("links", it) }
        form["tenant_id"]?.let { data.put("tenant_id", it) }

        notifyListeners("formSelected", data)
    }
}