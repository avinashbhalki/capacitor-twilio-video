import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(TwilioVideoPlugin)
public class TwilioVideoPlugin: CAPPlugin {

    private static weak var sharedInstance: TwilioVideoPlugin?
    private var videoViewController: VideoCallViewController?

    override public func load() {
        TwilioVideoPlugin.sharedInstance = self
    }

    public static func getInstance() -> TwilioVideoPlugin? {
        return sharedInstance
    }

    @objc func joinRoom(_ call: CAPPluginCall) {
        guard let token = call.getString("token"), !token.isEmpty else {
            call.reject("Token is required")
            return
        }

        let roomName = call.getString("roomName") ?? call.getString("roomId")

        guard let room = roomName, !room.isEmpty else {
            call.reject("Either roomName or roomId must be provided")
            return
        }

        let identity = call.getString("identity")
        let role = call.getString("role")
        let tenantId = call.getInt("tenantId")

        // Validate role if provided
        if let role = role, !["mht", "cct", "patient"].contains(role) {
            call.reject("Invalid role. Allowed values: mht, cct, patient")
            return
        }

        DispatchQueue.main.async {
            let vc = VideoCallViewController()
            vc.accessToken = token
            vc.roomName = room
            vc.userIdentity = identity
            vc.userRole = role
            vc.tenantId = tenantId
            vc.modalPresentationStyle = .fullScreen

            self.bridge?.viewController?.present(vc, animated: true, completion: nil)
            self.videoViewController = vc
        }

        call.resolve()
    }

    @objc func leaveRoom(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.videoViewController?.disconnect()
        }
        call.resolve()
    }

    @objc func muteAudio(_ call: CAPPluginCall) {
        let muted = call.getBool("muted") ?? false
        DispatchQueue.main.async {
            self.videoViewController?.muteAudio(muted: muted)
        }
        call.resolve()
    }

    @objc func enableVideo(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? true
        DispatchQueue.main.async {
            self.videoViewController?.enableVideo(enabled: enabled)
        }
        call.resolve()
    }

    @objc func flipCamera(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.videoViewController?.flipCamera()
        }
        call.resolve()
    }

    @objc func setSpeaker(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? true
        DispatchQueue.main.async {
            self.videoViewController?.setSpeaker(enabled: enabled)
        }
        call.resolve()
    }

    @objc func sendUsersList(_ call: CAPPluginCall) {
        guard let selectedRoleKey = call.getString("selectedRoleKey"), !selectedRoleKey.isEmpty else {
            call.reject("selectedRoleKey is required")
            return
        }

        guard ["mht", "cct", "patient", "participant"].contains(selectedRoleKey) else {
            call.reject("Invalid selectedRoleKey. Allowed values: mht, cct, patient, participant")
            return
        }

        let usersArray = call.getArray("users") as? [[String: Any]] ?? []
        var users: [[String: String]] = []

        for userDict in usersArray {
            if let id = userDict["id"] as? String, !id.isEmpty,
               let userId = userDict["user_id"] as? String, !userId.isEmpty,
               let fullName = userDict["full_name"] as? String, !fullName.isEmpty {
                users.append([
                    "id": id,
                    "user_id": userId,
                    "full_name": fullName
                ])
            }
        }

        DispatchQueue.main.async {
            self.videoViewController?.handleUsersList(selectedRoleKey: selectedRoleKey, users: users)
        }

        call.resolve()
    }

    // Event notification methods
    public func notifyRoomConnected(roomName: String) {
        notifyListeners("roomConnected", data: ["roomName": roomName])
    }

    public func notifyRoomDisconnected(roomName: String, reason: String?) {
        var data: [String: Any] = ["roomName": roomName]
        if let reason = reason {
            data["reason"] = reason
        }
        notifyListeners("roomDisconnected", data: data)
    }

    public func notifyParticipantJoined(identity: String) {
        notifyListeners("participantJoined", data: ["identity": identity])
    }

    public func notifyParticipantLeft(identity: String) {
        notifyListeners("participantLeft", data: ["identity": identity])
    }

    public func notifyNetworkQualityChanged(identity: String, level: Int, isLocal: Bool) {
        notifyListeners("networkQualityChanged", data: [
            "identity": identity,
            "level": level,
            "isLocal": isLocal
        ])
    }

    public func notifyDominantSpeakerChanged(identity: String?) {
        var data: [String: Any] = [:]
        if let identity = identity {
            data["identity"] = identity
        } else {
            data["identity"] = NSNull()
        }
        notifyListeners("dominantSpeakerChanged", data: data)
    }

    public func notifyRoomAutoClosed(reason: String) {
        notifyListeners("roomAutoClosed", data: ["reason": reason])
    }

    public func notifyRoomError(code: String, message: String, isFatal: Bool) {
        notifyListeners("roomError", data: [
            "code": code,
            "message": message,
            "isFatal": isFatal
        ])
    }

    public func notifyRoleSelected(selectedRoleKey: String, identity: String?, role: String?, tenantId: Int?, roomName: String?) {
        var data: [String: Any] = ["selectedRoleKey": selectedRoleKey]
        if let identity = identity { data["identity"] = identity }
        if let role = role { data["role"] = role }
        if let tenantId = tenantId { data["tenantId"] = tenantId }
        if let roomName = roomName { data["roomName"] = roomName }
        notifyListeners("roleSelected", data: data)
    }

    public func notifyUsersListLoaded(selectedRoleKey: String, userCount: Int) {
        notifyListeners("usersListLoaded", data: [
            "selectedRoleKey": selectedRoleKey,
            "userCount": userCount
        ])
    }

    public func notifyUserSelected(id: String, userId: String, fullName: String, selectedRoleKey: String, tenantId: Int?, role: String?) {
        var data: [String: Any] = [
            "id": id,
            "user_id": userId,
            "full_name": fullName,
            "selectedRoleKey": selectedRoleKey
        ]
        if let tenantId = tenantId { data["tenantId"] = tenantId }
        if let role = role { data["role"] = role }
        notifyListeners("userSelected", data: data)
    }

    public func notifyPopupDismissed(popupType: String, reason: String) {
        notifyListeners("popupDismissed", data: [
            "popupType": popupType,
            "reason": reason
        ])
    }

    public func notifyPopupError(message: String, popupType: String) {
        notifyListeners("popupError", data: [
            "message": message,
            "popupType": popupType
        ])
    }
}
