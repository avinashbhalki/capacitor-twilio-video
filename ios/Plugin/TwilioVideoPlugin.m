import Foundation
import Capacitor

@objc(TwilioVideoPlugin)
public class TwilioVideoPlugin: CAPPlugin {
    @objc func joinRoom(_ call: CAPPluginCall) {}
    @objc func leaveRoom(_ call: CAPPluginCall) {}
    @objc func muteAudio(_ call: CAPPluginCall) {}
    @objc func enableVideo(_ call: CAPPluginCall) {}
    @objc func flipCamera(_ call: CAPPluginCall) {}
    @objc func setSpeaker(_ call: CAPPluginCall) {}
}
