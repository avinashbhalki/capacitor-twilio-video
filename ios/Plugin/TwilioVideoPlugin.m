#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Define the plugin using the CAP_PLUGIN Macro, and
// each method the plugin supports using the CAP_PLUGIN_METHOD macro.
CAP_PLUGIN(TwilioVideoPlugin, "TwilioVideo",
    CAP_PLUGIN_METHOD(joinRoom, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(leaveRoom, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(muteAudio, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(enableVideo, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(flipCamera, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(setSpeaker, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(sendUsersList, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(sendFormList, CAPPluginReturnPromise);
)
