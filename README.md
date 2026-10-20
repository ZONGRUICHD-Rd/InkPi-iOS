# InkPi iOS

The iOS companion app for InkPi, the Raspberry Pi brush-calligraphy grader. It does the same things as the Android app:

- **记录 (records):** cloud evaluation history with search, 好/中/坏 filters, summary stats, multi-select delete and paging. Each record opens a detail screen with the score ring, original and processed images, four-dimension scores, feedback, confidence values and raw JSON.
- **配网 (Wi-Fi setup):** provisions the device's Wi-Fi through the InkPi hotspot (`http://10.42.0.1`, the `inkpi-netd` API).
- **调试 (debug):** environment info, quick checks against the cloud, device, netd and hotspot, a free-form API console, a local request log, app logs, diagnostics sharing, an in-app web view and a local-data wipe.
- **我的 (me):** account, cloud server address, direct device address on the LAN, and theme.

It's a native SwiftUI app with an iOS 26 deployment target, using the system Liquid Glass components:

- `TabView` with `Tab`, `tabBarMinimizeBehavior(.onScrollDown)` and a `tabViewBottomAccessory` that shows connection status.
- Glass and glass-prominent button styles.
- `GlassEffectContainer` with `glassEffectID` for the morphing filter chips.
- `safeAreaBar` and `ToolbarSpacer`.
- Glass toasts using `glassEffectTransition(.materialize)`.
- SwiftUI `WebView` / `WebPage`.

Glass appears only on controls and navigation; content uses the standard grouped backgrounds.

## Build

GitHub Actions (`.github/workflows/build-ipa.yml`) builds the app on `macos-26` with Xcode 26:

1. XcodeGen generates the project from `project.yml`.
2. `xcodebuild` builds a Release configuration with code signing turned off.
3. The `.app` is zipped into `InkPi-unsigned.ipa`.

The IPA is uploaded as a workflow artifact and also attached to the rolling **latest** prerelease.

To build locally on a Mac:

```bash
brew install xcodegen && xcodegen generate && open InkPi.xcodeproj
```

## Install (unsigned IPA)

Download `InkPi-unsigned.ipa` from the [latest release](../../releases/tag/latest). Sign and install it with your own Apple ID using [Sideloadly](https://sideloadly.io) or AltStore.

- **Device requirement:** iOS 26 or later.
- **Free Apple ID limits:** the app must be re-signed every 7 days.
- **First launch:** allow **本地网络 (Local Network)** access. Without it the app can't reach the device on the LAN or the setup hotspot.

## Defaults

- **Cloud API:** `http://163.192.62.239:23334`
- **Setup hotspot:** `InkPi-xxxx` at `http://10.42.0.1`
- **Direct device address** (set in 我的, the Me tab): for example `http://192.168.0.47:5000`
