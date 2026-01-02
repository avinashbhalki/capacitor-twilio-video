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

        DispatchQueue.main.async {
            let vc = VideoCallViewController()
            vc.accessToken = token
            vc.roomName = room
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
}
