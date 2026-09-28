# PAPNG 설치 패키지

설치 묶음 버전은 `VERSION`에서 관리하며 PAPNG 파일 포맷 버전과 별개입니다. 패키징 명령은 저장소 최상위에서 실행합니다. 생성물은 모두 `builds/<platform>/papng-suite/`에 저장됩니다.

Ubuntu와 Windows에는 **Godot 뷰어·편집기, Unity 뷰어, Unreal 뷰어, Qt 영상 변환기** 다섯 앱을 설치합니다. Android에는 Android를 지원하는 **Godot 뷰어·편집기**를 설치합니다. 웹뷰어는 브라우저에서 실행하므로 설치 묶음에 넣지 않습니다.

PAPNG의 기본 연결 대상은 **Godot 뷰어**입니다. PNG/APNG는 뷰어와 편집기의 연결 프로그램 목록에 등록합니다. GIF는 편집기와 변환기, MP4/WebM은 변환기에 연결할 수 있습니다. PNG·동영상 등 이미 사용 중인 기본 앱은 유지합니다.

## Ubuntu

Ubuntu x86_64용 `.deb` 한 개로 설치합니다. 현재 빌드 기준은 **Ubuntu 26.04**입니다. 이전 Ubuntu 버전 지원을 주장하지 않으며, 다른 Ubuntu 버전을 지원하려면 해당 버전에서 앱과 패키지를 함께 다시 빌드해야 합니다. 패키지에는 빌드 환경의 외부 라이브러리 의존성과 최소 버전이 기록됩니다. 각 엔진을 실행할 수 있는 OpenGL/Vulkan 그래픽 드라이버가 필요합니다.

```sh
sudo apt install ./papng-suite_0.1.0_ubuntu-26.04_amd64.deb
```

- 앱 본체는 `/opt/papng-suite/`, 실행 명령은 `/usr/bin/papng-viewer`, `papng-editor`, `papng-unity-viewer`, `papng-unreal-viewer`, `papng-converter`입니다.
- 앱 메뉴에 다섯 앱과 **PAPNG 기본 뷰어 설정**이 추가됩니다. 변환기 명령은 GUI와 CLI 모두 지원합니다.
- 시스템의 PAPNG 기본 연결을 Godot 뷰어로 설정합니다. 사용자가 이미 지정한 개인 연결이 우선한다면 메뉴의 **PAPNG 기본 뷰어 설정**을 한 번 실행합니다. 개인 연결은 `papng-defaults remove`로 이전 값으로 돌릴 수 있습니다.
- 시스템 연결은 제거 시 설치 전 값으로 복원합니다. 설치 후 다른 앱으로 변경한 연결은 그대로 둡니다. 업그레이드도 이후의 선택을 덮어쓰지 않습니다.
- 파일과 앱별 사용자 설정은 앱 설치 폴더 밖에 보관됩니다. Unreal의 저장 경로도 사용자 영역을 사용합니다.

```sh
# 개인 연결 설정도 사용했다면 패키지 제거 전에 실행합니다.
papng-defaults remove
sudo apt remove papng-suite
```

### 제작

앱별 빌드 의존성은 각 앱 README를 참고합니다. 빌더에는 Python 3.11 이상과 `dpkg-dev`, `desktop-file-utils`, `binutils`, `patchelf`가 필요합니다.

```sh
python3 tools/native/build.py linux
python3 tools/editor/build.py linux
python3 demos/unity/viewer/build.py linux
python3 demos/unreal/viewer/build.py linux
python3 tools/converter/build.py --package
python3 packaging/build.py ubuntu --check
python3 packaging/build.py ubuntu
```

엔진 중간 파일·테스트·로그·이전 압축 파일은 포함하지 않습니다. 앱의 실행 라이브러리와 라이선스 고지는 함께 넣으며, Qt·FFmpeg 런타임도 변환기 안에 유지합니다. 시스템 로더와 glibc는 Ubuntu가 제공하는 것을 사용합니다. 이 패키지는 앱별 런타임을 `/opt`에 묶는 직접 배포용 구성입니다. `manifest.json`과 `SHA256SUMS`를 함께 배포하면 포함 앱 버전과 설치 파일 해시를 확인할 수 있습니다.

## Windows

Windows x64용 NSIS 설치 파일 `PAPNG-Suite-0.1.0-windows-x64-setup.exe`를 제작합니다. 현재 저장소에는 **제작 설정**이 제공됩니다. 다섯 앱의 Windows 실행 파일을 먼저 빌드해야 하며, 현재 Linux 환경에서 Windows 전체 설치 파일을 완성하거나 실제 Windows 설치를 검증한 것은 아닙니다.

- 사용자별 `%LOCALAPPDATA%\Programs\PAPNG Suite`에 설치하므로 관리자 권한을 요구하지 않습니다.
- 시작 메뉴의 **PAPNG** 폴더에 각 앱, 기본 앱 설정, 제거 메뉴가 생깁니다. Windows의 설치된 앱 목록에서도 제거할 수 있습니다.
- 각 앱을 연결 프로그램 후보와 기본 앱 설정 화면에 등록합니다. 설치 마지막 단계에서 **Godot PAPNG Viewer**를 `.papng` 기본 앱으로 선택할 수 있습니다.
- 기존 Windows 기본 앱 선택은 운영체제에서 직접 변경해야 합니다. 보호된 `UserChoice` 레지스트리를 조작하지 않습니다.
- 제거할 때 자체 메뉴·앱 등록·설치 파일만 삭제합니다. 사용자가 저장한 이미지나 앱의 사용자 설정은 제거하지 않습니다. 설치 프로그램은 현재 코드 서명이 없는 상태로 제작되며, 공개 배포용 서명은 별도로 적용할 수 있습니다.

### Windows 빌드 환경

Windows PC에 Python 3.11 이상, CMake, Visual Studio C++ 빌드 도구와 Windows SDK, Godot 4.7.2 및 같은 버전의 export templates, Unity 6000.5.7f1의 Windows Build Support, Unreal Engine 5.8.2, Qt 6.10 이상 MSVC SDK, NSIS 3를 준비합니다. FFmpeg·ffprobe의 Windows 실행 파일과 해당 배포본의 라이선스 고지도 준비합니다. Qt, Unreal, Unity의 SDK 경로는 실제 설치 위치에 맞춥니다.

Visual Studio의 **재배포용 x64 CRT 디렉터리**와 라이선스 고지도 지정합니다. 보통 `%VCToolsRedistDir%\x64\Microsoft.VC143.CRT`에 있습니다. DLL을 각 실행 파일 옆에 함께 설치하여 개발 도구가 없는 PC에서도 실행하도록 구성하며, 시스템의 `System32` DLL을 복사하지 않습니다. 런타임 업데이트 시 설치 패키지도 다시 제작합니다. 자세한 경로는 [Microsoft 런타임 배포 문서](https://learn.microsoft.com/en-us/cpp/windows/determining-which-dlls-to-redistribute)를 참고합니다.

```powershell
$env:GODOT_BIN = 'C:\Tools\Godot\godot.exe'
$env:UNITY_BIN = 'C:\Program Files\Unity\Hub\Editor\6000.5.7f1\Editor\Unity.exe'
$env:UNREAL_ENGINE = 'C:\UnrealEngine'
# MSVC 개발자 터미널에서 실행하고 NSIS 디렉터리를 PATH에 추가합니다.
python tools/native/build.py windows --templates C:\Tools\Godot\Godot_v4.7.2-stable_export_templates.tpz
python tools/editor/build.py windows
python demos/unity/viewer/build.py windows
python demos/unreal/viewer/build.py windows
python tools/converter/build.py --package --qt-prefix C:\Qt\6.10.2\msvc2022_64 --ffmpeg-dir C:\Tools\ffmpeg\bin --ffmpeg-notices C:\Tools\ffmpeg\licenses
python packaging/build.py windows --check
python packaging/build.py windows --vc-runtime-dir "$env:VCToolsRedistDir\x64\Microsoft.VC143.CRT" --vc-runtime-notices C:\Tools\MSVC-Runtime-License.txt
```

`--check`는 다섯 앱의 필수 실행 파일과 런타임 파일을 검사합니다. 누락되면 전체 패키지 제작을 중단하고 목록을 출력합니다. 일부 앱만 들어 있는 설치 파일을 전체 패키지로 만들지 않습니다. 다른 컴퓨터의 `builds/windows/`를 가져왔다면 `--inputs <builds 경로>`로 지정할 수 있습니다. 최종 NSIS 조립은 Linux에서도 가능합니다.

## Android

`PAPNG-Suite-0.1.0-android-debug.zip`에는 `papng-viewer.apk`, `papng-editor.apk`, 검증 정보와 선택적인 USB 설치 도구가 들어갑니다. APK를 기기에 옮겨 각각 열고 Android 설치 화면에서 설치합니다. 두 앱 모두 런처 아이콘과 이미지 열기·공유 연결을 포함합니다.

Android는 일반 앱이 다른 앱을 조용히 설치하거나 기본 앱을 강제로 선택하는 것을 허용하지 않습니다. `.papng` 파일을 열 때 **PAPNG Viewer → 항상**을 선택하면 Godot 뷰어로 연결됩니다. 파일 관리자가 매번 선택하도록 강제하거나 파일을 일반 바이너리로 보고하는 경우, 선택 방식은 해당 파일 관리자를 따릅니다.

USB 디버깅과 SDK의 `adb`가 준비된 PC에서는 ZIP을 풀고 다음 명령으로 두 APK를 설치할 수도 있습니다.

```sh
python3 install.py
# 기기가 여러 개이거나 adb가 PATH에 없을 때
python3 install.py --serial DEVICE_SERIAL --adb /path/to/adb
```

기본 출력은 현재 개발 키로 서명한 **디버그 APK**입니다. 버전, 디버그 여부와 서명 인증서 해시를 `manifest.json`에 기록합니다. 서명이 다른 기존 설치가 있으면 덮어쓰기가 거부될 수 있습니다. 편집한 파일을 보관한 뒤 업데이트 방법을 결정해야 하므로 설치 도구가 임의로 기존 앱을 제거하지 않습니다. 배포용 키는 계속 보관하고 같은 키로 업데이트를 서명해야 합니다.

```sh
python3 tools/native/build.py android
python3 tools/editor/build.py android
python3 packaging/build.py android
# 별도로 release 서명한 두 파일을 묶을 때
python3 packaging/build.py android --apk-dir /path/to/signed-apks
```

`--apk-dir`에는 `papng-viewer.apk`와 `papng-editor.apk`가 있어야 합니다. 빌더는 서명·16 KiB 정렬·패키지 ID·런처·파일 연결을 검사합니다. 서명/매니페스트 검사는 실제 기기에서의 설치·파일 열기 검증을 대신하지 않습니다.

## 플랫폼 연결 규칙 참고

- [freedesktop MIME 기본 앱 규칙](https://specifications.freedesktop.org/mime-apps/latest-single/)
- [Windows 앱 기본값 플랫폼](https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/default-apps-platform)
- [NSIS 설치기 문법](https://nsis.sourceforge.io/Docs/Chapter4.html)
- [Android 앱 간 Intent 연결](https://developer.android.com/training/basics/intents/sending)
