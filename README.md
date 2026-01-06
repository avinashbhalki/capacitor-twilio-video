# capacitor-twilio-video

A production-ready Capacitor 8 plugin for Twilio Video with custom full-screen UI for Android and iOS.

## Features

- ✅ Custom full-screen video UI (not Twilio's default UI)
- ✅ Support for Capacitor 8.0.0
- ✅ Pinned Twilio SDK versions for stability
- ✅ **Robust call state management** with strict state machine
- ✅ **Enhanced UI controls** with clear visual state feedback
- ✅ **Stable multi-participant rendering** (no flicker with 3+ participants)
- ✅ Auto-close when last participant leaves
- ✅ Real-time participant events
- ✅ Network quality monitoring
- ✅ Dominant speaker detection with debouncing
- ✅ Audio/Video mute controls with state persistence
- ✅ Speaker/Earpiece toggle
- ✅ Camera flip support
- ✅ **Swift Package Manager (SPM) support** with CocoaPods fallback
- ✅ Production-ready code with proper resource cleanup

## Twilio SDK Versions

This plugin uses **pinned** Twilio SDK versions for stability:

- **Android**: Twilio Video SDK `7.6.1`
- **iOS**: Twilio Video SDK `5.8.2`

## Documentation

- **[Call State Management & UI Behavior](CALL_STATE_MANAGEMENT.md)** - Detailed guide on call states, button states, and multi-participant rendering
- **[SPM Setup & Troubleshooting](SPM_SETUP.md)** - Swift Package Manager configuration and common issues

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

### Mute/Unmute Audio

```typescript
// Mute audio
await TwilioVideo.muteAudio({ muted: true });

// Unmute audio
await TwilioVideo.muteAudio({ muted: false });
```

### Enable/Disable Video

```typescript
// Disable video
await TwilioVideo.enableVideo({ enabled: false });

// Enable video
await TwilioVideo.enableVideo({ enabled: true });
```

### Flip Camera

```typescript
await TwilioVideo.flipCamera();
```

### Toggle Speaker

```typescript
// Enable speaker
await TwilioVideo.setSpeaker({ enabled: true });

// Enable earpiece
await TwilioVideo.setSpeaker({ enabled: false });
```

## Event Listeners

### Room Connected

```typescript
TwilioVideo.addListener('roomConnected', (event) => {
  console.log('Connected to room:', event.roomName);
});
```

### Room Disconnected

```typescript
TwilioVideo.addListener('roomDisconnected', (event) => {
  console.log('Disconnected from room:', event.roomName);
  console.log('Reason:', event.reason);
});
```

### Participant Joined

```typescript
TwilioVideo.addListener('participantJoined', (event) => {
  console.log('Participant joined:', event.identity);
});
```

### Participant Left

```typescript
TwilioVideo.addListener('participantLeft', (event) => {
  console.log('Participant left:', event.identity);
});
```

### Network Quality Changed

```typescript
TwilioVideo.addListener('networkQualityChanged', (event) => {
  console.log('Network quality for', event.identity);
  console.log('Level (0-5):', event.level);
  console.log('Is local:', event.isLocal);
});
```

### Dominant Speaker Changed

```typescript
TwilioVideo.addListener('dominantSpeakerChanged', (event) => {
  console.log('Dominant speaker:', event.identity);
});
```

### Room Auto-Closed

This event fires when all remote participants have left and the room is automatically closed.

```typescript
TwilioVideo.addListener('roomAutoClosed', (event) => {
  console.log('Room auto-closed:', event.reason);
  // reason will be "last-participant-left"
});
```

### Room Error

```typescript
TwilioVideo.addListener('roomError', (event) => {
  console.error('Room error:', event.message);
  console.error('Code:', event.code);
  console.error('Is fatal:', event.isFatal);
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

**Button states not updating:**
- This has been fixed - buttons now reflect actual call state
- Check console logs for state transition messages

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