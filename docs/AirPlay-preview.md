# SidePad AirPlay preview

Android 1.12-airplay-preview adds an opt-in AirPlay screen-mirroring receiver.
The iPhone uses Control Centre → Screen Mirroring; no iOS SidePad application,
Mac relay, Android developer mode, or USB cable is required for this mode.

## Use

1. Connect the iPhone and Android tablet to the same local Wi-Fi network.
   Guest networks with client isolation or multicast blocking may prevent discovery.
2. Open SidePad on the tablet and select **아이폰 화면 미러링**.
3. On the iPhone, select **SidePad · [tablet model]** in Screen Mirroring.
4. The tablet always displays a four-digit connection code while waiting.
   If the iPhone asks for an AirPlay password, enter that code.
5. Leaving the tablet activity stops discovery, streaming sockets and audio output.
   Opening SidePad from its icon always shows the connection-mode menu first,
   including after returning from a background receiver. Back also returns to it.

USB mode remains available. The Mac's existing explicit `.MainActivity` launch,
token, cursor, input and audio protocol are preserved. Android launcher entry now
points to `.HomeActivity`; the separate `.AirPlayActivity` is not exported.

## Scope

- Screen mirroring and its audio; optional pure AirPlay audio uses the same engine.
- H.264 video, hardware decoder preferred, software fallback when available.
- Advertised 1920×1080 / up to 60 fps. iOS chooses the actual stream dimensions
  and frame rate; portrait and landscape streams are fitted without stretching.
- Immediate decoded-frame rendering, bounded compressed queue and coalesced wakeups.
  Encoded-frame overflow resumes at an IDR with cached SPS/PPS, never by feeding
  dependent P-frames into a fresh decoder.
- Native Oboe audio output with the engine's adaptive buffer.
- Per-install persistent receiver identity and key, PIN-required pairing.
- No background receiver service, automatic boot start, overlay or storage permission.
- HLS URL playback, DRM-protected video and controlling the iPhone from tablet
  touch/pen are outside this preview's scope. HLS/HEVC capabilities are disabled.
- No claim of Apple certification or universal iOS compatibility.

## Build

The prototype imports **only four native libraries per ABI** from the official
`jqssun/android-airplay-server` v0.0.31 release APK. The upstream application is
not installed or launched. APK SHA-256 and each native library SHA-256 must match
`android/airplay/engine.lock.json` before anything is imported. Dependencies are
arm64-v8a, armeabi-v7a and x86_64; unknown architectures fail with a visible error.

```sh
python3 android/airplay/prepare_engine.py --download
SIDE_PAD_ANDROID_ONLY=1 PAD_DISPLAY_TOOLCHAIN=/path/to/toolchain \
  PAD_DISPLAY_OUTPUT=build-airplay bash build.sh
```

Alternatively pass `--apk /path/to/app-release.apk` for offline preparation.
`build.sh` only verifies already prepared libraries and never fetches an unpinned
latest release. Existing Android signing material under `private/` must be retained
to update an installed SidePad without deleting its app data.

## Source and redistribution

The AirPlay-enabled Android build and integration are GPL-3.0; see
`LICENSE-Android-AirPlay`. This does not assert a license change for existing Mac
source. Upstream notices are included as Android assets and accessible from the
mode menu. Native engine source is pinned to
`c8defdd70d7e6a04f4f1b71d353653682d594106`; submodule revisions, OpenSSL and Oboe
versions are recorded in `engine.lock.json`.

To reproduce the upstream native libraries from source:

```sh
git clone https://github.com/jqssun/android-airplay-server.git
cd android-airplay-server
git checkout c8defdd70d7e6a04f4f1b71d353653682d594106
git submodule update --init --recursive
./gradlew assembleRelease
```

Use the pinned repository's Android SDK/NDK settings, patch tasks and Gradle
wrapper. Signing can differ while the native source revision remains the same;
the release-import path intentionally accepts only the official APK hash.
Before publishing a modified APK, publish the SidePad integration source and the
complete corresponding native source/dependency notices with it. The public preview release includes a separate complete native source archive
(`SidePad-AirPlay-engine-source.zip`) and the SidePad integration source archive.

## Verification

`tests/run.sh` covers the compressed frame queue as well as existing cursor,
touch/pen, audio, foreground sessions, display acknowledgement, updater and Mac
layout behavior. Hash verification runs before every APK build.

For a real tablet on USB, validate RTSP independently of an iPhone:

```sh
adb devices -l
adb -s DEVICE_SERIAL forward tcp:17000 tcp:7000
python3 tests/airplay_probe.py
```

The probe requires a complete RTSP 200 response with a valid binary property list,
SidePad receiver name, device identity and capabilities. Plain HTTP `/info` is not
equivalent to this RTSP request.

First-frame success is logged only by the decoder's `OnFrameRenderedListener` as
`SidePad-AirPlay: first-frame-rendered`; service advertisement and PIN display alone
do not prove that the iPhone video or sound works. Live iPhone 15 Pro → Lenovo TB373FU rendering and AAC-ELD audio were confirmed.
The user confirmed working rotation after the SPS/IDR fix. Logs showed 1920×896
coded frames with a 1920×886 visible crop. A short receiver-side sample recorded
steady-state receive-to-render-callback p95 values around 61–94 ms, with a 169 ms
receive-to-ready startup sample. These are receiver components, not end-to-end
capture/network/input-to-photon latency, and are not an improvement percentage.
Other devices, protected content and long-session stability are not validated.
