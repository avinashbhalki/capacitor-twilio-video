# Swift Package Manager (SPM) Setup & Troubleshooting

## Overview

This plugin supports **both CocoaPods and Swift Package Manager (SPM)** for iOS dependency management.

**Recommended**: Use **CocoaPods** for maximum stability with Capacitor plugins.

**SPM Support**: Available as an alternative, with pinned Twilio Video SDK version `5.8.2`.

---

## Option 1: CocoaPods (Recommended)

### Setup

1. The plugin uses CocoaPods by default via `CapacitorTwilioVideo.podspec`

2. After installing the plugin:
```bash
npm install capacitor-twilio-video
npx cap sync ios
```

3. Open the workspace:
```bash
cd ios/App
pod install
open App.xcworkspace
```

### Pinned Dependencies

The podspec pins:
- **TwilioVideo**: `5.8.2`
- **iOS Deployment Target**: `13.0`
- **Swift Version**: `5.1+`

### Troubleshooting

**Issue**: `pod install` fails with Twilio SDK version conflict

**Solution**:
```bash
cd ios/App
pod cache clean --all
pod deintegrate
pod install --repo-update
```

**Issue**: Linker errors with Twilio symbols

**Solution**: Ensure `TwilioVideo` framework is in "Link Binary With Libraries" build phase

---

## Option 2: Swift Package Manager (SPM)

### Prerequisites

- Xcode 13.0+
- iOS 13.0+ deployment target
- Capacitor 5.0+

### Setup

1. In Xcode, open your iOS app project
2. Go to **File → Add Packages...**
3. Add this plugin as a local package:
   - Click "Add Local..."
   - Navigate to `node_modules/capacitor-twilio-video`
   - Select the folder containing `Package.swift`

4. Add Twilio Video SDK:
   - URL: `https://github.com/twilio/twilio-video-ios`
   - Version: **Exact** `5.8.2`

5. Link the package products:
   - `CapacitorTwilioVideo`
   - `TwilioVideo`

### Package.swift Configuration

The plugin includes a `Package.swift` with pinned dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", branch: "main"),
    .package(url: "https://github.com/twilio/twilio-video-ios", .exact("5.8.2"))
]
```

### Required System Frameworks

Ensure these frameworks are linked (should be automatic):
- `AVFoundation`
- `AudioToolbox`
- `VideoToolbox`
- `CoreMedia`
- `CoreTelephony`

---

## Common SPM Issues & Solutions

### Issue 1: "Missing package product 'TwilioVideo'"

**Cause**: Twilio Video SDK package not added correctly

**Solution**:
1. In Xcode, go to project settings
2. Select your app target
3. Go to **General → Frameworks, Libraries, and Embedded Content**
4. Click **+** and add `TwilioVideo` from Swift packages
5. Ensure it's set to "Do Not Embed" (framework is statically linked)

---

### Issue 2: "No such module 'TwilioVideo'" in Swift files

**Cause**: Module not found in build settings

**Solution**:
1. In target Build Settings, search for "Import Paths"
2. Verify Swift package products are in import paths
3. Clean build folder: **Product → Clean Build Folder** (⇧⌘K)
4. Delete DerivedData:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```
5. Rebuild project

---

### Issue 3: Linker errors with duplicate symbols

**Cause**: Both CocoaPods and SPM are active simultaneously

**Solution**: **Choose one dependency manager only**

**To switch from CocoaPods to SPM:**
```bash
cd ios/App
pod deintegrate
rm Podfile.lock
# Remove CocoaPods references from .xcworkspace
```

**To switch from SPM to CocoaPods:**
1. In Xcode, select project
2. Go to **Package Dependencies**
3. Remove `CapacitorTwilioVideo` and `TwilioVideo` packages
4. Run:
```bash
cd ios/App
pod install
```

---

### Issue 4: "The package product 'TwilioVideo' requires minimum platform version 12.0"

**Cause**: Deployment target mismatch

**Solution**:
1. In project settings → General → Deployment Info
2. Set **iOS Deployment Target** to `13.0` or higher
3. Update `Package.swift` if needed:
```swift
platforms: [
    .iOS(.v13)
]
```

---

### Issue 5: Build fails with "SDK version too old"

**Cause**: Xcode version doesn't support Swift 5.5

**Solution**: Upgrade to Xcode 13.0 or later

---

### Issue 6: SPM package resolution is very slow

**Cause**: Xcode downloading and caching dependencies

**Solution**:
1. Be patient on first resolution (can take 5-10 minutes)
2. Subsequent builds will use cache
3. To reset package cache:
```bash
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/Developer/Xcode/DerivedData
```

---

## Verifying SPM Setup

### Check 1: Package Dependencies

1. In Xcode project navigator
2. Select your project (top item)
3. Select your app target
4. Go to **General** tab
5. Verify under **Frameworks, Libraries, and Embedded Content**:
   - `TwilioVideo.framework` (or similar)
   - Status should be "Do Not Embed" or "Embed & Sign" based on package type

### Check 2: Build Phases

1. Select target → **Build Phases**
2. Expand **Link Binary With Libraries**
3. Verify Twilio and plugin frameworks are listed

### Check 3: Import in Swift

Test import in a Swift file:
```swift
import TwilioVideo
import Capacitor

// Should compile without errors
```

---

## Platform Version Requirements

| Component | Minimum Version |
|-----------|----------------|
| iOS | 13.0 |
| Xcode | 13.0 |
| Swift | 5.1 |
| Twilio Video SDK | 5.8.2 (pinned) |
| Capacitor | 5.0+ |

---

## Fallback Strategy

**If SPM setup fails after troubleshooting:**

1. Remove SPM packages completely
2. Use CocoaPods (default, tested, stable)
3. The plugin works identically with both dependency managers
4. File an issue on GitHub with Xcode version and error logs

---

## Performance Notes

- **Binary size**: SPM and CocoaPods produce similar binary sizes (~25-30 MB for Twilio SDK)
- **Build time**: First SPM build may be slower due to package resolution
- **Runtime**: No difference in performance between SPM and CocoaPods

---

## Debugging SPM Issues

### Enable verbose logging:

```bash
xcodebuild -scheme YourAppScheme -destination 'platform=iOS Simulator,name=iPhone 14' clean build | tee build.log
```

### Check resolved packages:

```bash
# In your iOS app directory
swift package show-dependencies
```

### Verify package graph:

In Xcode:
1. **File → Packages → Resolve Package Versions**
2. Check Xcode console for resolution logs
3. Any errors will be shown with specific package names

---

## Additional Resources

- [Capacitor iOS Configuration](https://capacitorjs.com/docs/ios/configuration)
- [Twilio Video iOS SDK](https://github.com/twilio/twilio-video-ios)
- [Swift Package Manager Guide](https://swift.org/package-manager/)
