import Foundation
import Capacitor
import TwilioVideo

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
        print("TwilioVideoPlugin: sendUsersList method invoked")

        guard let selectedRoleKey = call.getString("selectedRoleKey"), !selectedRoleKey.isEmpty else {
            print("TwilioVideoPlugin: sendUsersList failed - selectedRoleKey is required")
            call.reject("selectedRoleKey is required")
            return
        }

        guard ["mht", "cct", "patient", "participant"].contains(selectedRoleKey) else {
            print("TwilioVideoPlugin: sendUsersList failed - invalid selectedRoleKey: \(selectedRoleKey)")
            call.reject("Invalid selectedRoleKey. Allowed values: mht, cct, patient, participant")
            return
        }

        let usersArray = call.getArray("users") as? [[String: Any]] ?? []
        var users: [[String: String]] = []

        print("TwilioVideoPlugin: sendUsersList parsing \(usersArray.count) users")

        for (index, userDict) in usersArray.enumerated() {

            let idValue = userDict["id"]
            let userIdValue = userDict["user_id"]
            let fullName = userDict["full_name"] as? String

            let idStr = (idValue as? String) ?? (idValue as? Int).map { String($0) }
            let userIdStr = (userIdValue as? String) ?? (userIdValue as? Int).map { String($0) }

            if let id = idStr, !id.isEmpty,
               let userId = userIdStr, !userId.isEmpty,
               let name = fullName, !name.isEmpty {

                print("TwilioVideoPlugin: sendUsersList parsed user[\(index)]: \(name) (id=\(id), user_id=\(userId))")

                users.append([
                    "id": id,
                    "user_id": userId,
                    "full_name": name
                ])
            } else {
                print("""
                ⚠️ TwilioVideoPlugin: sendUsersList skipping user[\(index)]
                   raw = \(userDict)
                   idValue = \(String(describing: idValue))
                   userIdValue = \(String(describing: userIdValue))
                   fullName = \(String(describing: fullName))
                """)
            }
        }

        print("TwilioVideoPlugin: sendUsersList calling handleUsersList with \(users.count) users for role: \(selectedRoleKey)")

        DispatchQueue.main.async {
            self.videoViewController?.handleUsersList(selectedRoleKey: selectedRoleKey, users: users)
        }

        call.resolve()
    }

    @objc func sendFormList(_ call: CAPPluginCall) {
        print("TwilioVideoPlugin: sendFormList method invoked")

        let formsArray = call.getArray("forms") as? [[String: Any]] ?? []
        var validatedForms: [[String: Any]] = []

        print("TwilioVideoPlugin: sendFormList parsing \(formsArray.count) forms")

        // Validate and parse only required fields, ignore optional ones safely
        for (index, formDict) in formsArray.enumerated() {
            guard let id = formDict["id"] as? Int,
                  let tenantId = formDict["tenant_id"] as? Int,
                  let name = formDict["name"] as? String, !name.isEmpty,
                  let links = formDict["links"] as? String, !links.isEmpty else {
                print("TwilioVideoPlugin: sendFormList skipping invalid form at index \(index)")
                continue
            }

            // Create validated form with only required fields
            let validatedForm: [String: Any] = [
                "id": id,
                "tenant_id": tenantId,
                "name": name,
                "links": links
            ]

            validatedForms.append(validatedForm)
            print("TwilioVideoPlugin: sendFormList parsed form: \(name) (id=\(id))")
        }

        print("TwilioVideoPlugin: sendFormList calling handleFormsList with \(validatedForms.count) validated forms")

        DispatchQueue.main.async {
            self.videoViewController?.handleFormsList(forms: validatedForms)
        }

        call.resolve()
    }

    // Event notification methods
    public func notifyRoomConnected(roomName: String) {
        notifyListeners("roomConnected", data: ["roomName": roomName])
    }

    public func notifyRoomDisconnected(room: Room) {
        // Build room object structure
        var roomData: [String: Any] = [
            "sid": room.sid,
            "name": room.name,
            "state": roomStateToString(room.state)
        ]

        // Add local participant
        if let localParticipant = room.localParticipant {
            roomData["localParticipant"] = [
                "sid": localParticipant.sid,
                "identity": localParticipant.identity
            ]
        }

        // Add remote participants
        var remoteParticipants: [[String: Any]] = []
        for participant in room.remoteParticipants {
            remoteParticipants.append([
                "sid": participant.sid,
                "identity": participant.identity
            ])
        }
        roomData["remoteParticipants"] = remoteParticipants

        let data: [String: Any] = ["room": roomData]
        notifyListeners("roomDisconnected", data: data)
    }

    private func roomStateToString(_ state: Room.State) -> String {
        switch state {
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reconnecting:
            return "reconnecting"
        case .disconnected:
            return "disconnected"
        @unknown default:
            return "unknown"
        }
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

    public func notifyRoleSelected(selectedRoleKey: String, identity: String?, role: String?, tenantId: Int?, roomName: String?, roomSID: String?, secondParticipantRole: String?, secondParticipantIdentity: String?) {
        var data: [String: Any] = ["selectedRoleKey": selectedRoleKey]
        if let identity = identity { data["identity"] = identity }
        if let role = role { data["role"] = role }
        if let tenantId = tenantId { data["tenantId"] = tenantId }
        if let roomName = roomName { data["roomName"] = roomName }
        if let roomSID = roomSID { data["roomSID"] = roomSID }
        if let secondParticipantRole = secondParticipantRole { data["secondParticipantRole"] = secondParticipantRole }
        if let secondParticipantIdentity = secondParticipantIdentity { data["secondParticipantIdentity"] = secondParticipantIdentity }
        notifyListeners("roleSelected", data: data)
    }

    public func notifyUsersListLoaded(selectedRoleKey: String, userCount: Int) {
        notifyListeners("usersListLoaded", data: [
            "selectedRoleKey": selectedRoleKey,
            "userCount": userCount
        ])
    }

    public func notifyUserSelected(id: String, userId: String, fullName: String, selectedRoleKey: String, tenantId: Int?, role: String?, roomName: String?, roomSID: String?) {
        var data: [String: Any] = [
            "id": id,
            "user_id": userId,
            "full_name": fullName,
            "selectedRoleKey": selectedRoleKey
        ]
        if let tenantId = tenantId { data["tenantId"] = tenantId }
        if let role = role { data["role"] = role }
        if let roomName = roomName { data["roomName"] = roomName }
        if let roomSID = roomSID { data["roomSID"] = roomSID }
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

    public func notifySplitScreenRequested() {
        notifyListeners("splitScreenRequested", data: [
            "timestamp": Date().timeIntervalSince1970 * 1000
        ])
    }

    public func notifyFormSelected(form: [String: Any]) {
        var data: [String: Any] = [:]

        if let id = form["id"] as? Int {
            data["id"] = id
        }
        if let name = form["name"] as? String {
            data["name"] = name
        }
        if let links = form["links"] as? String {
            data["links"] = links
        }
        if let tenantId = form["tenant_id"] as? Int {
            data["tenant_id"] = tenantId
        }

        notifyListeners("formSelected", data: data)
    }
}