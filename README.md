<p align="center"><img src="assets/PadDisplay-rounded.png" width="150" alt="SidePad icon"></p>

# SidePad

**USB-C로 안드로이드 패드를 Mac의 확장 모니터로 사용합니다.**

A native macOS + Android experiment for a wired second display, with a separate low-latency cursor channel, pen input and finger touch.

현재 버전: **1.9** · [변경 내역](CHANGELOG.md)

**[배포 페이지](https://github.com/studioprxs-cmd/sidepad/releases/latest)** · [Mac 앱 다운로드](https://github.com/studioprxs-cmd/sidepad/releases/latest/download/SidePad-macOS.zip) · [Android APK 다운로드](https://github.com/studioprxs-cmd/sidepad/releases/latest/download/SidePad.apk)

## 기능

| 항목 | 지원 범위 |
| --- | --- |
| 화면 | 확장 모니터 또는 주 화면 복제 |
| 원본 해상도 | 2944 × 1840 실제 픽셀 |
| Retina | 1472 × 920 작업 공간을 2배 픽셀로 표시 |
| 주사율 | 가상 디스플레이와 지원하는 Android 패널에 120Hz 요청 |
| 커서 | 영상과 분리하여 움직일 때 최대 120Hz 전송, 실제 macOS 커서 모양 반영 |
| 영상 | H.264 하드웨어 인코딩·디코딩, 최대 60fps 또는 30fps |
| 손가락 | 탭, 더블 탭, 드래그, 두 손가락 스크롤 |
| 펜 | 클릭, 드래그, 필압, 기울기, 옆 버튼을 누른 채 접촉해 오른쪽 클릭 |
| 소리 | Mac 재생 소리를 패드 내장 스피커로 전달, 48kHz 스테레오 PCM |

120Hz 패널·커서와 영상 프레임 속도는 서로 다릅니다. 이 버전은 영상 120fps를 제공하지 않습니다. 해상도 옵션은 현재 검증한 패드에 맞춰 구성했으며, 다른 패드에서는 화면 비율과 성능이 달라질 수 있습니다.

## 설치와 사용

필요 환경: macOS 14 이상, Android 9 이상, 데이터 전송이 가능한 USB 케이블, Mac의 ADB. 현재 실제 기기 검증 환경은 Apple Silicon Mac Studio(macOS 27)와 Lenovo Idea Tab Pro(Android 16), Lenovo Tab Pen Plus입니다.

1. Mac에 ADB를 설치합니다. Homebrew를 사용한다면 `brew install --cask android-platform-tools`로 설치할 수 있습니다.
2. 패드의 개발자 옵션에서 USB 디버깅을 켠 뒤 USB-C로 연결하고, 이 Mac의 디버깅 요청을 허용합니다.
3. 압축을 푼 `SidePad.app`을 **응용 프로그램** 폴더로 옮겨 실행합니다. Mac 앱이 포함된 Android APK를 설치·업데이트하고 연결합니다.
4. 처음 실행할 때 macOS **개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음**에서 SidePad를 허용합니다.
5. 터치·펜을 사용하려면 앱의 **펜·터치 권한** 버튼을 눌러 **손쉬운 사용** 권한을 허용합니다.
6. 기본값은 확장 모니터, 원본 Retina 해상도, 영상 최대 60fps입니다. 처음 연결한 구성에서는 주 화면 오른쪽에 생성됩니다. **디스플레이 배치**에서 위치를 조정하면 저장되고 다음 연결에 복원됩니다.

해상도나 프레임 속도를 바꾸려면 **중지 → 옵션 선택 → 연결 시작** 순서로 조작합니다. 창을 닫아도 메뉴 막대의 `▣ SidePad`에서 전송이 유지됩니다. **종료**하면 가상 모니터와 이 앱의 USB 포트 연결이 해제됩니다.

### 패드 앱을 나갔다가 다시 연결하기

패드에서 홈 화면이나 다른 앱으로 이동하면 화면·소리·입력 전송과 가상 모니터를 정리합니다. Mac이 패드 앱을 다시 실행하거나 화면을 켜지 않습니다. Mac 앱과 USB 연결을 유지한 상태에서 **패드의 SidePad를 다시 열면** 기존 연결 정보, 화면 모드, 해상도, 프레임 속도, 소리 출력과 저장한 모니터 배열로 다시 연결됩니다. Mac의 **연결 시작**으로도 다시 열 수 있습니다.

Mac에서 **중지**를 누른 경우에는 같은 연결의 재시도가 중지를 취소하지 않습니다. 패드에서 앱을 나갔다가 다시 열거나 Mac의 연결 시작을 누르세요. USB 케이블 복구는 연결 경로만 복원하며 앱을 강제로 실행하지 않습니다. 다른 패드로 바꾸면 Mac에서 연결 시작을 눌러 새 기기를 연결하세요.

### 앱 업데이트

Mac 창의 **업데이트 확인** 버튼 또는 **SidePad → 업데이트 확인…** 메뉴를 누르세요. 새 버전이 있으면 **업데이트 설치**로 다운로드·설치·재실행합니다. 기존 설정을 유지하고, 연결된 패드 앱도 함께 설치·업데이트합니다. Mac 앱과 Android 앱은 같은 버전을 사용하세요.

업데이트 확인에는 인터넷이 필요합니다. 공식 GitHub의 최신 정식 배포만 확인하며 파일 크기, SHA-256, 앱 식별자·버전·서명을 검사한 뒤 교체합니다. 확인·다운로드·검증 실패 시 기존 앱을 유지하며, 교체 실패 시 이전 앱을 복원합니다. 앱과 앱이 있는 폴더에 쓰기 권한이 필요합니다. 자동 확인이나 정기 다운로드는 하지 않습니다.

### 화면 기록 승인이 켜져 있는데 연결되지 않을 때

이전 개발 버전의 코드 해시에 묶인 승인은 새 버전에 적용되지 않을 수 있습니다. 앱 메뉴의 **화면 기록 승인 복구… → 승인 다시 등록**을 누르면 **SidePad의 화면 기록 승인만** 초기화하고 새 승인을 요청합니다. 시스템 설정에서 SidePad를 허용한 다음 앱을 종료했다가 다시 여세요. 펜·터치의 손쉬운 사용 승인은 별도로 켜야 합니다.

화면 기록이 거부된 뒤에는 연결 재시도가 시스템 승인창을 반복해서 띄우지 않습니다. 이 복구 작업은 사용자가 메뉴에서 직접 선택할 때만 실행합니다.

### 처음 실행이 차단될 때

Mac 앱은 로컬 개발용 서명이며 Apple 공증을 받지 않았습니다. 공식 배포판인지 확인한 뒤 다음 절차를 따르세요.

1. 압축을 푼 `SidePad.app`을 한 번 실행합니다. ‘SidePad을(를) 열지 않음’ 경고가 나오면 **완료**를 누릅니다.
2. 압축 파일에 함께 들어 있는 **실행 승인 설정 열기.webloc**을 열어 **개인정보 보호 및 보안**으로 이동합니다.
3. 아래쪽 **보안**에서 SidePad의 **그래도 열기**를 누르고, 이어지는 확인 창에서 **열기**와 Mac 인증을 진행합니다.

바로가기가 열리지 않으면 ** → 시스템 설정 → 개인정보 보호 및 보안 → 보안**으로 이동하세요. ‘그래도 열기’가 없으면 앱을 다시 실행해 경고를 확인한 직후 다시 확인하세요. 자세한 순서는 함께 제공한 **처음 실행 안내.html**과 [Apple 공식 안내](https://support.apple.com/ko-kr/102445)에 있습니다.

실행 후에는 앱 창의 **실행 승인 설정** 버튼 또는 **SidePad → 실행 승인 설정 열기…** 메뉴를 사용할 수 있습니다. **설치·권한 안내…** 메뉴는 같은 안내 문서를 엽니다. 이 기능은 설정 화면만 열며, 실제 실행 승인은 사용자가 직접 선택합니다.

Mac 앱은 USB 디버깅을 허용한 연결 기기에 포함된 Android APK를 자동 설치·업데이트합니다. **Mac 앱만 설치하는 경우와 두 앱을 직접 설치하는 경우 모두 패드의 개발자 옵션·USB 디버깅이 필요합니다.** 현재 USB 전송이 ADB를 사용하기 때문이며, APK를 직접 설치해도 이 조건은 같습니다.

자동 설치는 기종별 성능 최적화를 의미하지 않습니다. 현재 기본 해상도는 Lenovo Idea Tab Pro에 맞춘 2944×1840이며, 다른 기기는 화면 크기에 맞는 해상도를 직접 선택하세요. iPlay60 mini Pro는 가로 기준 1920×1200, 패널 최대 60Hz를 보고하므로 **1920×1200 · 균형** 옵션을 사용하세요. 커서 전송 상한과 패널의 실제 주사율은 다릅니다.

### 모니터 배치 기억

연결 중에 **디스플레이 배치**에서 패드를 위·아래·왼쪽·오른쪽으로 옮기면 모니터들의 위치와 주 모니터를 자동 저장합니다. 중지·종료 후 다시 연결하거나 앱을 재실행해도 같은 모니터 구성과 해상도에서는 마지막 배열을 복원합니다. 패드마다 따로 기억하며, 이 설정은 Mac에만 저장됩니다.

모니터 연결 구성, 회전 또는 논리 해상도가 달라지면 별도 배열로 기억합니다. 새 구성에는 기존 배열을 억지로 적용하지 않고 패드를 기본 위치에 배치합니다. 화면 복제 모드에는 이 기능을 적용하지 않습니다. 앱을 다시 열면 이미 실행 중인 SidePad를 활성화해 중복 연결을 막습니다.

### 패드 스피커

Mac 앱의 **소리 출력**에서 **Mac + 패드 · 둘 다 / 패드만 / Mac만**을 선택합니다. 메뉴 막대의 SidePad에도 같은 메뉴가 있습니다. 기본값은 둘 다이며 선택을 기억합니다. 패드의 미디어 볼륨 버튼으로 음량을 조절합니다. Mac에서 재생되는 시스템 오디오를 전달하며 마이크는 수집하지 않습니다. 패드만 선택하면 연결 중 Mac 출력을 음소거합니다. 다른 출력을 선택하거나 연결을 끊거나 앱을 종료하면 앱이 변경한 음소거 상태를 복원합니다. 음소거를 지원하지 않는 Mac 출력 장치는 둘 다로 유지합니다.

영상·커서와 별도 USB 경로를 사용하고, 무압축 PCM 48kHz / 스테레오 / 16비트로 전송합니다. 대역폭은 약 1.54Mbps이며 Android 내장 스피커를 우선 선택합니다. 기기나 재생 앱에 따라 영상과 소리의 지연 차이가 있을 수 있습니다.

### 터치와 펜

- 한 손가락으로 톡 누르면 클릭, 두 번 누르면 더블 클릭입니다.
- 한 손가락을 움직이면 누른 위치에서 드래그합니다.
- 두 손가락을 함께 움직이면 가로·세로 스크롤합니다.
- 펜이 화면에 닿거나 가까이 호버하는 동안에는 손가락 입력을 억제합니다. 펜을 충분히 떼고 약 0.6초 후 다시 손가락을 사용할 수 있습니다.
- 취소·연결 해제·앱 중지 시 누른 버튼을 해제합니다.

두 손가락 확대·축소와 손가락 길게 눌러 오른쪽 클릭은 아직 구현하지 않았습니다. 펜 필압은 macOS 태블릿 이벤트로 전달하며, 실제 그리기 효과는 대상 앱의 지원과 브러시 설정에 따라 달라집니다.

## 작동 구조

```text
Mac virtual display → ScreenCaptureKit → VideoToolbox H.264
  → localhost TCP → ADB USB reverse → Android MediaCodec → SurfaceView

macOS cursor position + image → separate USB channel → Android SurfaceControl
Android pen + finger events → same channel in reverse → macOS CoreGraphics input
Mac system audio → dedicated USB channel → Android AudioTrack → built-in speaker
```

영상용 `127.0.0.1:28765`, 커서·입력용 `127.0.0.1:28766`, 오디오용 `127.0.0.1:28767`을 사용하고 실행마다 생성하는 임의 토큰으로 연결을 인증합니다. 앱 전송에는 인터넷·클라우드 서버를 사용하지 않으며 영상·소리 파일을 저장하지 않습니다. 3K 영상 목표 비트레이트는 36Mbps입니다.

커서 위치는 최대 120Hz로 확인합니다. 움직임이 없거나 패드 밖에 있으면 위치 패킷은 약 10Hz 연결 확인용으로 줄이고, Android는 동일 위치·표시 상태의 중복 합성 작업을 생략합니다. macOS 커서 모양은 최대 15Hz로 확인하고 바뀔 때만 PNG와 hotspot을 보냅니다. UI의 **USB 왕복 시간**은 통신 측정치이며, 손가락부터 화면까지의 전체 지연을 뜻하지 않습니다.

화면 캡처 표면 풀은 3개이며 인코더 대기는 최대 2개로 제한합니다. Android 출력은 밀린 영상에서 최신 프레임을 표시합니다. 정지 화면의 실제 fps는 화면 변경량에 따라 낮아집니다.

## 빌드

Mac에서 Xcode Command Line Tools, JDK 17, Android SDK API 35와 Build Tools 35.0.0이 필요합니다. Gradle 없이 Android와 macOS 앱을 함께 빌드합니다.

```sh
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
# Android SDK command-line tools의 sdkmanager로 설치:
sdkmanager 'platforms;android-35' 'build-tools;35.0.0' 'platform-tools'
bash build.sh
```

결과는 `build/SidePad.app`, `build/SidePad.apk`입니다. `PAD_DISPLAY_OUTPUT`으로 출력 폴더를, `ANDROID_BUILD_TOOLS_VERSION`으로 Build Tools 버전을 바꿀 수 있습니다. 경로에 공백이 있으면 환경 변수 값을 따옴표로 감싸세요.

기존 묶음 도구를 재사용하려면 `PAD_DISPLAY_TOOLCHAIN=/path/to/toolchain`을 지정할 수 있습니다. 이 옵션은 `jdk/jdk-17.0.20.1+1/Contents/Home`, `build-tools/android-15`, `platform/android-35/android.jar` 구조를 사용합니다. `JAVA_HOME`을 따로 지정하면 그 JDK를 우선합니다.

Android 서명 키는 최초 빌드 때 `private/`에 생성됩니다. 이후 기존 APK를 업데이트하려면 같은 키를 보관해야 합니다. 키는 Git 추적 대상에서 제외되어 있습니다. macOS 로컬 앱은 동일 식별자의 designated requirement를 사용합니다. 이전 코드 해시에 묶인 승인은 새로 등록해야 하며, Apple 공증 또는 Developer ID 서명을 제공하는 것은 아닙니다.

## 검증

```sh
bash tests/run.sh
```

제스처 상태 전환, 터치·펜 패킷 파싱, 필압 필드, 버튼 해제, 픽셀 스크롤과 잘못된 입력 거부를 검사합니다. 오디오 테스트는 평면·인터리브 float PCM, 채널 순서, 리틀 엔디언 변환, 클리핑, 비정상 값과 잘못된 버퍼 거부를 확인합니다. 이 테스트는 Mac에 실제 입력을 게시하거나 소리를 재생하지 않습니다.

연결 상태 테스트는 앱 재진입과 USB 재시도, 수동 중지, 이전 연결의 늦은 재시도, 인증 실패를 검사합니다. 업데이트 테스트는 버전 비교, 공식 배포 주소, 미완성·시험 배포 거부, 파일 크기·SHA-256 불일치를 확인합니다.

`mac/check-display.m`은 패드용 애니메이션 측정 화면, `mac/check-touch.m`은 터치·스크롤 확인 창, `mac/check-pen.m`은 필압 확인 창입니다. 실제 연결 기기에서 화면 전송과 입력 결과를 별도로 검증해야 합니다.

2026-10-02 실제 기기에서 Retina 픽셀 크기와 활성 120Hz 모드, 펜 필압 변화, 터치 이벤트 전달을 확인했습니다. 변경 전 24초 애니메이션 측정에서 영상 약 56.5fps를 기록했습니다. fps는 장면과 시스템 부하에 따라 달라지며 일반 모니터와 동일한 지연을 보장하지 않습니다.

## 현재 제약

확장 모니터 생성은 비공개 CoreGraphics API를 사용합니다. macOS 업데이트에 따라 달라질 수 있으며 생성이 안 되면 **화면 복제**를 선택할 수 있습니다. 글로벌 커서 이미지 API도 deprecated 상태여서 사용할 수 없으면 기본 화살표를 사용합니다. DRM 콘텐츠는 macOS 캡처 제한의 영향을 받습니다. DisplayLink나 Apple Sidecar의 공식 구현 또는 호환 드라이버가 아닙니다.

## 참고 자료

- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [ScreenCaptureKit queueDepth](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/queuedepth)
- [Android MediaCodec](https://developer.android.com/reference/android/media/MediaCodec)
- [Android SurfaceControl.Transaction](https://developer.android.com/reference/android/view/SurfaceControl.Transaction)
- [Chromium CGVirtualDisplay 사용 예](https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm)
- [DisplayLink EVDI 커서 분리 구조](https://displaylink.github.io/evdi/quickstart/)

공개 API 문서와 런타임 인터페이스를 참고해 구현했습니다. DisplayLink의 영상·커서 분리 원리를 참고했으며, 전용 압축 알고리즘이나 드라이버 코드를 사용하지 않았습니다. DisplayLink 제품과의 직접 지연 비교 실험은 수행하지 않았습니다.

앱 아이콘은 내장 image_gen으로 제작했습니다. [원본 및 라운딩 프롬프트](assets/icon-prompts.txt)를 함께 제공합니다.
