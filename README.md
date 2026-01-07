# capacitor-twilio-video

A production-ready Capacitor 8 plugin for Twilio Video with enhanced multi-participant support, robust call state management, and comprehensive audio routing.

## ✨ Major Improvements

This enhanced version includes significant fixes and improvements:

### 🔧 **Multi-Participant Video Rendering**
- **Fixed last-joined participant seeing no video**
- **Stable thumbnail grid + selectable full-screen video**
- **Persistent renderers** - no recreation on layout changes
- **Eliminates flicker** with 3+ participants
- **Participant selection system** with user preference override

### 🎮 **Enhanced UI Controls**
- **Clear visual state feedback** for all buttons
- **Proper selected/active/disabled states**
- **Audio routing aware** - speaker button respects Bluetooth priority
- **State persistence** across orientation and lifecycle events

### 🔊 **Production-Grade Audio Routing**
- **Full Bluetooth headset support** (HFP/A2DP/LE)
- **Automatic priority**: Bluetooth > Wired Headset > Speaker/Earpiece
- **Seamless handoff** when devices connect/disconnect
- **Audio routing state tracking** and button state sync

### 🚀 **Hardened Call State Management**
- **Strict state machine**: IDLE → JOINING → CONNECTED → DISCONNECTING → DISCONNECTED
- **Prevents race conditions** and invalid state transitions
- **Guards all media operations** based on call state
- **Proper error handling** and recovery

### 📦 **Reliable SPM Integration**
- **Pinned Twilio Video SDK versions** for stability
- **Enhanced framework linking** with required system frameworks
- **CocoaPods fallback** documented for edge cases
- **Comprehensive troubleshooting guide**

## Features

- ✅ **Custom full-screen video UI** (not Twilio's default UI)
- ✅ **Capacitor 8.0.0** support
- ✅ **Pinned Twilio SDK versions** for stability
- ✅ **Robust multi-participant rendering** (3+ users, no flicker)
- ✅ **Thumbnail grid with selection** - tap any participant to focus
- ✅ **Production-grade call state machine**
- ✅ **Comprehensive Bluetooth audio support**
- ✅ **Enhanced UI button states** with clear visual feedback
- ✅ **Auto-close** when last participant leaves
- ✅ **Real-time participant events**
- ✅ **Network quality monitoring**
- ✅ **Dominant speaker detection** with smart debouncing
- ✅ **Audio/Video controls** with state guards
- ✅ **Camera flip support**
- ✅ **Swift Package Manager (SPM)** with enhanced configuration
- ✅ **Memory leak prevention** and proper cleanup

## Twilio SDK Versions

This plugin uses **pinned** Twilio SDK versions for maximum stability:

- **Android**: Twilio Video SDK `7.6.1`
- **iOS**: Twilio Video SDK `5.8.3` (latest stable)

## Call State Management

The plugin implements a **strict state machine** to ensure reliable operation:

### States
- **IDLE**: No active call
- **JOINING**: `joinRoom()` called, connecting to Twilio
- **CONNECTED**: Successfully connected to room
- **DISCONNECTING**: Leaving room or auto-close in progress
- **DISCONNECTED**: Call ended, ready for cleanup

### State Transitions
```
IDLE → JOINING → CONNECTED → DISCONNECTING → DISCONNECTED
         ↓           ↓
    DISCONNECTED  DISCONNECTED
    (on error)    (abnormal exit)
```

### Media Control Guards
All media operations (`muteAudio`, `enableVideo`, `flipCamera`, `setSpeaker`) are **guarded by call state**:
- Only functional when `callState == CONNECTED`
- Prevent duplicate operations
- Maintain button state consistency

## Multi-Participant Video Rendering

### Participant Rendering Manager
- **One persistent renderer per participant** - never recreated
- **Stable VideoView lifecycle** - renderers survive layout changes
- **Efficient track subscription** - immediate attachment on join

### Thumbnail Grid + Selection
- **Local video** always in thumbnail (top of grid)
- **Remote participants** in clickable thumbnails below
- **Tap any thumbnail** to promote to full-screen
- **User selection overrides** dominant speaker auto-switching
- **Smooth transitions** without flicker

### Focus Priority
1. **User selection** (tap thumbnail) - highest priority
2. **Dominant speaker** (when user hasn't selected)
3. **First remote participant** (on initial join)
4. **Local video** (fallback when no remotes)

## Audio Routing System

### Routing Priority
1. **Bluetooth** (HFP/A2DP/LE) - highest priority
2. **Wired Headset** - second priority
3. **Speaker** (user preference)
4. **Earpiece** (default fallback)

### Bluetooth Support
- **Automatic SCO management** on Android
- **Seamless A2DP/HFP handoff** on iOS
- **Route change detection** and automatic switching
- **Speaker button intelligently disabled** when Bluetooth active

### Audio Session Configuration
**iOS**: `playAndRecord` + `videoChat` + `allowBluetooth` + `allowBluetoothA2DP`
**Android**: `MODE_IN_COMMUNICATION` + automatic SCO + Bluetooth receiver

## Documentation

- **[Call State Management Details](CALL_STATE_MANAGEMENT.md)** - Deep dive into states and behavior
- **[SPM Setup & Troubleshooting](SPM_SETUP.md)** - Swift Package Manager guide
- **[Deployment Guide](DEPLOYMENT.md)** - Production deployment checklist
- **[Quick Reference](QUICK_REFERENCE.md)** - API and common patterns

## Installation

```bash
npm install capacitor-twilio-video
npx cap sync
```

## Android Setup

### 1. Permissions

Add the following permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

### 2. Minimum SDK Version

Ensure your `android/app/build.gradle` has:

```gradle
android {
    defaultConfig {
        minSdkVersion 22
    }
}
```

### 3. Kotlin Support

The plugin requires Kotlin. If not already configured, add to your `android/build.gradle`:

```gradle
buildscript {
    ext.kotlin_version = '1.6.21'
    dependencies {
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version"
    }
}
```

## iOS Setup

### 1. Privacy Permissions

Add the following to your `ios/App/App/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs access to the camera for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to the microphone for audio calls</string>
```

### 2. Install CocoaPods Dependencies

```bash
cd ios/App
pod install
cd ../..
```

**Alternative**: Use Swift Package Manager (SPM) - see [SPM Setup Guide](SPM_SETUP.md)

### 3. Minimum iOS Version

Ensure your `ios/App/Podfile` specifies iOS 13.0+:

```ruby
platform :ios, '13.0'
```

## Usage

### Import the Plugin

```typescript
import { TwilioVideo } from 'capacitor-twilio-video';
```

### Join a Room

```typescript
async function joinVideoCall() {
  try {
    await TwilioVideo.joinRoom({
      roomName: 'my-room',
      token: 'your-twilio-access-token',
    });
  } catch (error) {
    console.error('Failed to join room:', error);
  }
}
```

### Leave a Room

```typescript
async function leaveVideoCall() {
  await TwilioVideo.leaveRoom();
}
```

### Media Controls

All media control methods are **state-aware** and will only execute when the call is in `CONNECTED` state:

```typescript
// Mute/Unmute Audio
await TwilioVideo.muteAudio({ muted: true });  // Mute
await TwilioVideo.muteAudio({ muted: false }); // Unmute

// Enable/Disable Video
await TwilioVideo.enableVideo({ enabled: false }); // Turn off camera
await TwilioVideo.enableVideo({ enabled: true });  // Turn on camera

// Flip Camera (only works when video is enabled)
await TwilioVideo.flipCamera();

// Speaker Toggle (respects Bluetooth priority)
await TwilioVideo.setSpeaker({ enabled: true });  // Speaker
await TwilioVideo.setSpeaker({ enabled: false }); // Earpiece
```

### ⚠️ Important: Audio Routing Behavior

The **speaker toggle is intelligent** and respects audio device priority:

- **When Bluetooth headset connected**: Speaker button is **disabled**
- **When wired headset connected**: Speaker button is **disabled**
- **When no external audio devices**: Speaker/earpiece toggle works normally
- **Audio routing is automatic**: Bluetooth > Wired > Speaker/Earpiece

This prevents users from accidentally overriding Bluetooth audio routing.

## UI Behavior

### Multi-Participant Video Layout

- **Full-screen area**: Shows the focused participant's video
- **Thumbnail grid** (top-right): Shows all other participants
- **Local video thumbnail**: Always visible (can tap to focus)
- **Tap any thumbnail**: Promotes that participant to full-screen

### Button Visual States

All control buttons have **clear visual feedback**:

| Button | Normal | Selected/Active | Disabled |
|--------|---------|----------------|----------|
| **Mute** | Gray | 🟢 Green (muted) | Dark |
| **Video** | Gray | 🟢 Green (camera off) | Dark |
| **Flip** | Gray | - | Dark (when video off) |
| **Speaker** | Gray | 🟢 Green (speaker on) | Dark (Bluetooth active) |
| **Hangup** | 🔴 Red | - | Dark |

### Participant Selection Behavior

1. **Default focus**: First remote participant to join
2. **User selection**: Tap any thumbnail → overrides auto-switching
3. **Dominant speaker**: Auto-switches focus (unless user selected)
4. **User preference persists**: Until user taps a different thumbnail

## Advanced Event Handling

### Room State Events

```typescript
// Basic connection events
TwilioVideo.addListener('roomConnected', (event) => {
  console.log('✅ Connected to:', event.roomName);
});

TwilioVideo.addListener('roomDisconnected', (event) => {
  console.log('❌ Disconnected:', event.roomName, event.reason);
});

TwilioVideo.addListener('roomError', (event) => {
  console.error('🔥 Room error:', event.message, event.code);
  if (event.isFatal) {
    // Handle fatal error - user should retry
  }
});
```

### Participant Management

```typescript
// Track participants joining/leaving
TwilioVideo.addListener('participantJoined', (event) => {
  console.log('👋 Joined:', event.identity);
  // Update UI participant count
});

TwilioVideo.addListener('participantLeft', (event) => {
  console.log('👋 Left:', event.identity);
  // Update UI participant count
});

// Auto-close handling
TwilioVideo.addListener('roomAutoClosed', (event) => {
  console.log('🚪 Room auto-closed:', event.reason);
  // Navigate back to main screen
  // reason: "last-participant-left"
});
```

### Network Quality Monitoring

```typescript
TwilioVideo.addListener('networkQualityChanged', (event) => {
  const quality = ['No signal', 'Poor', 'Poor', 'Fair', 'Good', 'Excellent'][event.level];
  console.log(`📶 ${event.isLocal ? 'Your' : event.identity} connection: ${quality}`);

  if (event.isLocal && event.level < 2) {
    // Show network warning to user
    showNetworkWarning('Poor connection detected');
  }
});
```

### Dominant Speaker Tracking

```typescript
TwilioVideo.addListener('dominantSpeakerChanged', (event) => {
  if (event.identity) {
    console.log('🎙️ Now speaking:', event.identity);
    // Optional: Show speaker indicator in UI
  } else {
    console.log('🔇 No dominant speaker');
  }
});
```
});
```

### Remove Listeners

```typescript
// Remove specific listener
const listener = await TwilioVideo.addListener('roomConnected', (event) => {
  console.log('Connected:', event.roomName);
});
listener.remove();

// Remove all listeners
await TwilioVideo.removeAllListeners();
```

## Complete Example

```typescript
import { TwilioVideo } from 'capacitor-twilio-video';

export class VideoCallService {
  private listeners: any[] = [];

  async startCall(roomName: string, accessToken: string) {
    // Setup event listeners
    this.setupListeners();

    // Join the room
    try {
      await TwilioVideo.joinRoom({
        roomName,
        token: accessToken,
      });
    } catch (error) {
      console.error('Failed to join:', error);
      throw error;
    }
  }

  async endCall() {
    await TwilioVideo.leaveRoom();
    this.removeListeners();
  }

  private setupListeners() {
    this.listeners.push(
      TwilioVideo.addListener('roomConnected', (event) => {
        console.log('✅ Connected to:', event.roomName);
      })
    );

    this.listeners.push(
      TwilioVideo.addListener('roomDisconnected', (event) => {
        console.log('❌ Disconnected from:', event.roomName);
      })
    );

    this.listeners.push(
      TwilioVideo.addListener('participantJoined', (event) => {
        console.log('👤 Participant joined:', event.identity);
      })
    );

    this.listeners.push(
      TwilioVideo.addListener('participantLeft', (event) => {
        console.log('👋 Participant left:', event.identity);
      })
    );

    this.listeners.push(
      TwilioVideo.addListener('roomAutoClosed', (event) => {
        console.log('🔒 Room auto-closed:', event.reason);
        this.removeListeners();
      })
    );

    this.listeners.push(
      TwilioVideo.addListener('roomError', (event) => {
        console.error('⚠️ Room error:', event.message);
      })
    );
  }

  private async removeListeners() {
    for (const listener of this.listeners) {
      await listener.remove();
    }
    this.listeners = [];
  }
}
```

## UI Behavior

### Full-Screen Custom UI

The plugin presents a **custom full-screen video interface** on both platforms:

#### Layout
- **Primary View**: Remote participant video (full-screen) - shows dominant speaker
- **Thumbnail**: Local participant video (picture-in-picture, top-right corner)
- **Controls**: Bottom bar with state-aware buttons:
  - 🎤 Mute/Unmute audio (highlighted when muted)
  - 📹 Enable/Disable video (highlighted when disabled)
  - 🔄 Flip camera (disabled when video is off)
  - 🔊 Toggle speaker (highlighted when speaker is on)
  - 📞 Hang up (always enabled during call)

#### Button State Feedback

All control buttons provide **clear visual state feedback**:

- **Active/Selected**: Green highlight (action is currently active)
- **Inactive**: Gray (default state)
- **Disabled**: Dimmed/50% opacity (action unavailable for current call state)

States update immediately and persist across orientation changes and app lifecycle events.

See [Call State Management](CALL_STATE_MANAGEMENT.md) for detailed behavior.

#### Multi-Participant Rendering

**Stable video rendering with 3+ participants:**

- Each participant gets a unique, reusable video renderer
- Dominant speaker shown in full-screen primary view
- Smooth transitions with debouncing (300ms) to prevent flicker
- No video view recreation - renderers are reused for performance
- Participant identity correctly mapped to video tracks

#### Call State Machine

The plugin enforces a strict state machine:

```
IDLE → JOINING → CONNECTED → DISCONNECTING → DISCONNECTED
```

- **Media controls** only work when state is `CONNECTED`
- **Invalid transitions** are rejected with warning logs
- **State events** emitted at each transition
- See [Call State Management](CALL_STATE_MANAGEMENT.md) for full details

#### Auto-Close Behavior

When all remote participants leave the room:
1. `roomAutoClosed` event is emitted
2. `roomDisconnected` event is emitted
3. The full-screen UI is dismissed automatically
4. All resources are cleaned up

This prevents users from being stuck in an empty room.

## API Reference

### Methods

#### `joinRoom(options: JoinRoomOptions): Promise<void>`

Join a Twilio Video room and display the full-screen UI.

**Parameters:**
- `options.token` (string, required): Twilio access token
- `options.roomName` (string, optional): Room name
- `options.roomId` (string, optional): Room ID

Either `roomName` or `roomId` must be provided.

#### `leaveRoom(): Promise<void>`

Leave the current room and dismiss the UI.

#### `muteAudio(options: { muted: boolean }): Promise<void>`

Mute or unmute local audio.

#### `enableVideo(options: { enabled: boolean }): Promise<void>`

Enable or disable local video.

#### `flipCamera(): Promise<void>`

Flip between front and back camera.

#### `setSpeaker(options: { enabled: boolean }): Promise<void>`

Toggle between speaker and earpiece audio output.

### Events

| Event | Payload | Description |
|-------|---------|-------------|
| `roomConnected` | `{ roomName: string }` | Connected to room |
| `roomDisconnected` | `{ roomName: string, reason?: string }` | Disconnected from room |
| `participantJoined` | `{ identity: string }` | Participant joined |
| `participantLeft` | `{ identity: string }` | Participant left |
| `networkQualityChanged` | `{ identity: string, level: number, isLocal: boolean }` | Network quality changed (0-5) |
| `dominantSpeakerChanged` | `{ identity: string \| null }` | Dominant speaker changed |
| `roomAutoClosed` | `{ reason: string }` | Room auto-closed |
| `roomError` | `{ code: string, message: string, isFatal: boolean }` | Room error occurred |

## Error Handling

```typescript
try {
  await TwilioVideo.joinRoom({
    roomName: 'test-room',
    token: accessToken,
  });
} catch (error) {
  console.error('Join failed:', error);
}

// Also listen for runtime errors
TwilioVideo.addListener('roomError', (event) => {
  if (event.isFatal) {
    // Handle fatal error - might need to reconnect
    console.error('Fatal error:', event.message);
  } else {
    // Handle non-fatal error - can continue
    console.warn('Non-fatal error:', event.message);
  }
});
```

## Resource Cleanup

The plugin automatically handles cleanup when:
- `leaveRoom()` is called
- Room is disconnected
- Room auto-closes
- App goes to background
- Activity/ViewController is destroyed

Cleanup includes:
- Disconnecting from Twilio room
- Releasing audio/video tracks
- Stopping camera capture
- Removing all renderers
- Clearing all references

## Troubleshooting

### Android

**Camera not working:**
- Ensure CAMERA permission is granted at runtime
- Check that minSdkVersion is 22 or higher

**Audio issues:**
- Verify RECORD_AUDIO and MODIFY_AUDIO_SETTINGS permissions
- Check that no other app is using the audio device

**Video flickering with multiple participants:**
- This has been fixed in the latest version
- Ensure you're using stable participant-to-renderer mapping

### iOS

**Black screen:**
- Verify camera and microphone permissions in Info.plist
- Check that the app has been granted permissions in Settings

**CocoaPods errors:**
- Run `pod install` in `ios/App` directory
- Try `pod repo update` if dependency resolution fails
- See [SPM Setup Guide](SPM_SETUP.md) for Swift Package Manager alternative

**Swift Package Manager issues:**
- See comprehensive guide: [SPM Setup & Troubleshooting](SPM_SETUP.md)
- Common issues: missing module, linker errors, version conflicts

## Migration Guide

### Upgrading from Previous Version

If you're upgrading from an earlier version, please note these behavioral changes:

#### ✅ **What's Improved**
- **Multi-participant support**: No more missing video for last-joined participant
- **Button states**: Clear visual feedback for all controls
- **Audio routing**: Proper Bluetooth headset support with priority
- **Call state management**: Prevents race conditions and invalid operations
- **Memory usage**: Better cleanup prevents memory leaks

#### 🔄 **Breaking Changes**
- **Speaker button behavior**: Now respects Bluetooth priority (may appear disabled when Bluetooth active)
- **Auto-close timing**: Slightly faster cleanup when last participant leaves
- **Event timing**: Some events may fire in slightly different order due to state machine

#### 📱 **UI Changes**
- **Thumbnail layout**: Vertical stack instead of single thumbnail
- **Button appearance**: Enhanced visual states (selected/disabled)
- **Participant selection**: Tap thumbnails to focus (new feature)

## Testing

### Test Multi-Participant Scenarios

1. **Join 3+ participants** to verify rendering stability
2. **Test last-joined participant** sees everyone's video
3. **Verify thumbnail selection** by tapping different participants
4. **Check dominant speaker switching** works smoothly
5. **Test Bluetooth headset** connect/disconnect during call

### Test Audio Routing

1. **Start call with Bluetooth connected** → should route to Bluetooth
2. **Disconnect Bluetooth mid-call** → should fall back to speaker
3. **Connect wired headset** → should route to headset
4. **Test speaker button** only works when no external devices

### Test State Management

1. **Call media methods before joining** → should be ignored
2. **Leave room multiple times** → should not crash
3. **Background/foreground app** → should maintain call state
4. **Kill and restart app** during call → should handle gracefully

## Performance Considerations

### Video Rendering
- **Renderer reuse**: Video views are never recreated, only moved between containers
- **Track subscription**: Immediate attachment prevents rendering delays
- **Memory efficiency**: Proper cleanup prevents accumulation of video renderers

### Audio Management
- **Bluetooth SCO**: Efficiently managed to prevent audio dropouts
- **Route changes**: Debounced to prevent rapid switching
- **Session management**: Proper setup and teardown for each call

### State Management
- **Minimal state storage**: Only essential state tracked
- **Efficient transitions**: State changes are validated and logged
- **Event debouncing**: Dominant speaker changes debounced to prevent flicker

## Production Deployment

### Checklist

#### 🛠️ **Pre-deployment Testing**
- [ ] Test with 3+ participants
- [ ] Verify Bluetooth headset support
- [ ] Test network interruption recovery
- [ ] Validate memory cleanup (no leaks)
- [ ] Test audio routing priority
- [ ] Verify button state accuracy

#### 📱 **Platform-Specific**
- [ ] **Android**: Test on API 22+ devices
- [ ] **Android**: Verify permissions at runtime
- [ ] **iOS**: Test with various iOS versions (13.0+)
- [ ] **iOS**: Validate SPM or CocoaPods setup

#### 🔒 **Security & Compliance**
- [ ] Secure token generation and renewal
- [ ] Proper permission handling
- [ ] Audio/video privacy compliance
- [ ] Background app behavior

### Production Configuration

#### Twilio Token Service
Ensure your backend generates tokens with appropriate permissions:

```javascript
// Backend token generation example
const AccessToken = require('twilio').jwt.AccessToken;
const VideoGrant = AccessToken.VideoGrant;

const token = new AccessToken(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_API_KEY_SID,
  process.env.TWILIO_API_KEY_SECRET,
  { identity: user.identity }
);

const videoGrant = new VideoGrant({
  room: roomName,
});

token.addGrant(videoGrant);
return token.toJwt();
```

#### App Store / Play Store

**iOS App Store:**
- Include microphone/camera usage descriptions
- Test with release build configuration
- Verify SPM dependencies resolve correctly

**Google Play Store:**
- Declare required permissions in manifest
- Test with release signing key
- Verify ProGuard rules if using code obfuscation

## Support & Contributing

### Getting Help

1. **Check documentation**: [Call State Management](CALL_STATE_MANAGEMENT.md), [SPM Setup](SPM_SETUP.md)
2. **Review examples**: See usage patterns above
3. **Enable logging**: Check console output for state transitions and errors
4. **Test with minimal setup**: Isolate issues by testing basic join/leave flow

### Reporting Issues

When reporting issues, please include:

- **Platform**: Android/iOS version
- **Plugin version**: Check package.json
- **Twilio SDK versions**: Android 7.6.1, iOS 5.8.3
- **Call scenario**: Number of participants, network conditions
- **Console logs**: Full error messages and state transitions
- **Reproduction steps**: Minimal steps to reproduce

### Contributing

This plugin follows production-ready patterns:

- **Strict state management** for reliability
- **Comprehensive error handling** and cleanup
- **Clear separation of concerns** (UI, media, networking)
- **Extensive logging** for debugging
- **Memory leak prevention** with proper resource management

## License

[License details would go here]

---

## 🎉 Ready for Production

This enhanced version of `capacitor-twilio-video` provides:

- ✅ **Enterprise-grade stability** with strict state management
- ✅ **Seamless multi-participant experience** with no rendering issues
- ✅ **Professional audio routing** with full Bluetooth support
- ✅ **Clear visual feedback** for all user interactions
- ✅ **Comprehensive error handling** and recovery
- ✅ **Memory-efficient** resource management

Perfect for production video calling applications requiring reliability and professional user experience.

---

*Enhanced with ❤️ for production video calling*

### General

**Call state issues:**
- Enable verbose logging to see state transitions
- See [Call State Management](CALL_STATE_MANAGEMENT.md) for debugging
- Check that you're not calling methods before room is connected

**Performance:**
- Multi-participant rendering is optimized for 3+ participants
- Dominant speaker changes are debounced (300ms)
- Video renderers are reused, never recreated

## Contributing

Contributions are welcome! Please open an issue or pull request on GitHub.

## License

MIT

## Repository

https://github.com/avinashbhalki/capacitor-twilio-video

## Support

For issues and questions, please use the GitHub issue tracker.