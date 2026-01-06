# Call State Management & UI Behavior

## Call State Lifecycle

The plugin implements a strict state machine to ensure predictable call behavior on both Android and iOS.

### Call States

```
IDLE → JOINING → CONNECTED → DISCONNECTING → DISCONNECTED
        ↓                         ↑
        └── (connection failed) ──┘
```

| State | Description | Valid Actions |
|-------|-------------|---------------|
| `IDLE` | No active call | `joinRoom()` only |
| `JOINING` | Connecting to room | `leaveRoom()` |
| `CONNECTED` | Active call in progress | All media controls, `leaveRoom()` |
| `DISCONNECTING` | Leaving room | None (in progress) |
| `DISCONNECTED` | Call ended | None (terminal state) |

### State Transitions

**Valid transitions:**
- `IDLE → JOINING` - User calls `joinRoom()`
- `JOINING → CONNECTED` - Room connection successful
- `JOINING → DISCONNECTED` - Connection failed (token error, network issue)
- `CONNECTED → DISCONNECTING` - User calls `leaveRoom()` or auto-close triggered
- `DISCONNECTING → DISCONNECTED` - Cleanup complete
- `CONNECTED → DISCONNECTED` - Abnormal disconnect (network drop, SDK error)

**Invalid transitions are rejected** with a warning log entry.

### Events

- `roomConnected` - Emitted when entering `CONNECTED` state
- `roomDisconnected` - Emitted when entering `DISCONNECTED` state
- State always resets to `IDLE` after activity destruction

---

## UI Button States

All call control buttons reflect their current state with visual feedback.

### Button State Logic

#### Mute Button 🎤
- **Enabled**: Only when `callState == CONNECTED`
- **Selected/Highlighted**: When audio is muted (`isAudioMuted == true`)
- **Color**:
  - Android: Green when selected, Gray when normal, Dark Gray when disabled
  - iOS: Green background when muted, Gray when unmuted, 50% opacity when disabled

#### Video Button 📹
- **Enabled**: Only when `callState == CONNECTED`
- **Selected/Highlighted**: When video is disabled (`isVideoEnabled == false`)
- **Color**:
  - Android: Green when video off, Gray when video on, Dark Gray when disabled
  - iOS: Green background when video off, Gray when video on, 50% opacity when disabled

#### Flip Camera Button 🔄
- **Enabled**: Only when `callState == CONNECTED` AND `isVideoEnabled == true`
- **Disabled**: When video is off (no point flipping a disabled camera)
- **Color**: 50% opacity when disabled

#### Speaker Button 🔊
- **Enabled**: Only when `callState == CONNECTED`
- **Selected/Highlighted**: When speaker is on (`isSpeakerEnabled == true`)
- **Color**:
  - Android: Green when speaker on, Gray when speaker off, Dark Gray when disabled
  - iOS: Green background when speaker on, Gray when speaker off, 50% opacity when disabled

#### Hangup Button 📞
- **Enabled**: When `callState == JOINING` OR `callState == CONNECTED`
- **Always Visible**: Red background
- **Disabled**: Only in `DISCONNECTING` or `DISCONNECTED` states

### State Persistence

Button states persist across:
- Orientation changes (Android handles via retained state)
- App backgrounding/foregrounding
- Temporary network interruptions (reconnecting state)

---

## Multi-Participant Video Rendering

### Architecture

Both platforms use **stable participant-to-renderer mapping**:

#### Android
- Each participant gets a **unique, reusable `VideoView`** instance
- Stored in `participantVideoViews: Map<String, VideoView>`
- Keyed by `participant.identity`
- Views are **never recreated** unless participant leaves permanently
- Dominant speaker changes only swap which view is shown in primary container

#### iOS
- Each participant gets a **unique, reusable `VideoView`** instance
- Stored in `participantVideoViews: [String: VideoView]`
- Keyed by `participant.identity`
- Strong references maintained to prevent deallocation
- Smooth transitions via view reparenting (no add/remove cycles)

### Rendering Logic

1. **First participant joins**: Video shown in full-screen primary view
2. **Additional participants join**: Each gets their own VideoView
3. **Dominant speaker changes**:
   - Debounced by 300ms to prevent flicker
   - Primary view is updated to show dominant speaker's VideoView
   - Previous view remains alive but removed from primary container
4. **Participant leaves**: Their VideoView is cleaned up and removed

### No Flicker Guarantee

- ✅ **Reuse** VideoView instances (never destroy/recreate)
- ✅ **Debounce** dominant speaker changes
- ✅ **Single render surface** per participant
- ✅ **No layout thrashing** (updates on main thread only)
- ✅ **Stable track subscriptions** (add/remove sink only once per track)

---

## Thread Safety

### Android
- All UI updates via `runOnUiThread {}`
- Dominant speaker debounced via `Handler(Looper.getMainLooper())`
- VideoView operations guaranteed on main thread

### iOS
- All UI updates via `DispatchQueue.main.async {}`
- Dominant speaker debounced via `Timer.scheduledTimer`
- VideoView operations guaranteed on main thread

---

## Logging & Debugging

### Enable verbose logging:

**Android:**
```bash
adb logcat | grep VideoCallActivity
```

**iOS:**
```bash
# In Xcode console, filter for:
# - "Call state transition"
# - "Created new VideoView"
# - "Updated primary view"
```

### Key Log Messages

- `"Call state transition: X -> Y"` - State changes
- `"Created new VideoView for participant: X"` - New renderer allocated
- `"Updated primary view to show participant: X"` - Dominant speaker switch
- `"Invalid state transition"` - Attempted illegal state change
- `"Cannot X, not connected. State: Y"` - Action blocked by state machine

---

## Error Handling

### Connection Failures
- State transitions to `DISCONNECTED`
- `roomError` event emitted with fatal flag
- Activity/ViewController dismissed automatically

### Abnormal Disconnects
- SDK error or network drop
- State transitions `CONNECTED → DISCONNECTED` (bypasses DISCONNECTING)
- Cleanup performed automatically
- `roomDisconnected` event emitted with error reason

### Duplicate Actions
- Multiple `joinRoom()` calls while `JOINING` or `CONNECTED`: Rejected silently
- Multiple `leaveRoom()` calls: Only first one executes
- Media control actions while not `CONNECTED`: Rejected with warning log
