# PAPNG Unity Viewer

Unity **6000.5.7f1** 기반 독립 실행형 이미지 뷰어, 앱 버전 **0.1.0**입니다. Godot 뷰어의 재생·마스크·위치 표시·배경·소켓 결합 기능을 Unity 화면으로 제공합니다. 포맷은 PAPNG 1.1을 그대로 사용합니다.

Linux 실행 파일은 `builds/linux/papng-unity-viewer/papng-unity-viewer.x86_64`, Windows는 `builds/windows/papng-unity-viewer/papng-unity-viewer.exe`입니다. 실행 파일과 함께 생성되는 `_Data` 및 런타임 디렉터리를 함께 배포해야 합니다.

```sh
./papng-unity-viewer.x86_64 /path/to/image.papng
```

IMGUI 기반 파일 브라우저와 도구 대화상자를 사용합니다. 색상 대화상자의 색상각 막대와 ΔS·ΔV 슬라이더에서 HSV 변화량을 선택합니다. 마스크가 많으면 이름·인덱스 검색으로 범위를 좁힙니다. 배경은 PNG·JPEG를 지원하며 APNG·PAPNG를 배경으로 열면 기본 PNG 이미지를 사용합니다.

## 빌드

필요한 도구는 Unity 6000.5.7f1과 유효한 로컬 라이선스, 대상 플랫폼의 Standalone 빌드 지원, Python 3.10 이상, C++17 컴파일러입니다. Linux는 GCC/Clang, Windows는 Visual Studio의 C++ 도구를 사용합니다.

저장소 최상단에서 실행합니다.

```sh
python3 demos/unity/viewer/build.py linux --unity /path/to/Unity
```

Windows의 **x64 Native Tools Command Prompt for VS**에서:

```powershell
py demos/unity/viewer/build.py windows --unity "C:\Program Files\Unity\Hub\Editor\6000.5.7f1\Editor\Unity.exe"
```

`UNITY_BIN`, `CXX`, `CXX_WINDOWS` 환경변수도 사용할 수 있습니다. Windows에서 네이티브 플러그인은 MSVC로 빌드합니다. Linux에서 Windows를 교차 빌드하려면 별도로 MinGW-w64와 Unity Windows Standalone 지원이 필요합니다.

빌드는 프로젝트를 `builds/<platform>/papng-unity-viewer/project/`에 복사하고 네이티브 플러그인·시작 씬을 생성합니다. `Library`, 임시 씬과 플러그인 바이너리는 공개 소스에 넣지 않습니다. 독립 실행 파일, 플랫폼별 압축 파일과 SHA-256을 같은 앱 출력 디렉터리에 생성합니다. 재현 가능한 시작 씬 생성과 빌드 설정은 `Assets/Editor/BuildViewer.cs`에 있습니다.

## 지원 기능

- PAPNG·APNG·PNG 파일 선택, 명령행 파일 열기, 파일을 열면 자동 재생.
- 재생·일시정지, 처음으로, 다음 방문, 프레임 탐색, 메타데이터 클립 선택.
- 원본 픽셀의 정수 배율 확대, 화면 맞춤, 드래그 이동.
- 이름·인덱스로 마스크 선택, 원본 평균색과 수정색 비교, HSV 변경과 영역 강조.
- 캔버스·바운딩 박스·피벗 표시, 출력 크기·픽셀 배수 힌트, 소켓 이름·위치·회전 표시.
- 부속 PAPNG 하나를 소켓에 연결. 부속 피벗에 소켓 위치·회전을 적용하고 각 파일의 시간을 독립 재생합니다. 부모가 멈추거나 끝나면 부속도 멈춥니다.
- 체크무늬·단색·외부 이미지 배경. 원본 픽셀 좌표의 위치·배율·불투명도·표시·제거를 설정하며 확대·이동을 함께 적용합니다.
- 파일 정보에서 경고와 원본 JSON5 메타데이터 확인. 원본 파일에는 변경을 저장하지 않습니다.

마스크의 기준색은 전체 프레임의 원본 RGB를 알파로 가중 평균한 값입니다. 선택한 색과 기준색의 HSV 차이를 각 마스크에 적용합니다. ΔS·ΔV는 −1~+1의 가산 차이이며 결과는 0~1로 제한하고 픽셀별 알파는 유지합니다. 검정·회색의 기준 H는 0이며, S/V를 올려 색을 입힐 수 있습니다. 색상 변경 시 재생을 멈추고 0번부터 복원하며 클립 시작점까지 진행합니다.

일반 PNG는 한 프레임·한 번 재생으로, APNG는 확장이 없는 PAPNG 모델로 정규화합니다. 일반 APNG의 0 지연은 10 ms, 0 분모는 100으로 처리합니다. PAPNG의 0 지연은 합성에만 사용하고 출력하지 않습니다. 무한 0 지연 순환은 작업량을 나누므로 일시정지할 수 있습니다.

### 조작

- `Ctrl+O`: 파일 열기, `Ctrl+M`: 마스크 색상, `Ctrl+B`: 배경, `Ctrl+L`: 부속 열기.
- `Space`: 재생·일시정지, `Home`: 처음으로, `→`: 다음 방문.
- `M`: 마스크 강조, `H`: 헤더 힌트, `S`: 소켓 표시.
- `F`: 화면 맞춤, `1`: 1:1, 마우스 휠: 확대·축소, 드래그: 이동.

`socket-buddy.papng`를 부모로, `socket-wand.papng`를 부속으로 열면 결합을 확인할 수 있습니다. 파일 브라우저에서 디렉터리 경로를 직접 입력할 수도 있습니다. 메타데이터의 문자열을 외부 파일 경로로 자동 실행하거나 불러오지 않습니다.

## 파일 연결

배포 압축을 모두 풀고 원하는 위치에 둔 뒤 아래 명령을 실행합니다. Python 3.10 이상이 필요하며 관리자 권한은 필요하지 않습니다.

```sh
python3 associate.py
# Windows에서는: py associate.py
```

Linux 앱 메뉴와 Linux·Windows의 **연결 프로그램**에 등록합니다. `.papng`, `.png`, `.apng`의 기존 기본 앱은 바꾸지 않습니다. 기본 앱으로 쓰려면 운영체제의 연결 프로그램 설정에서 선택합니다. 등록 후에는 압축을 푼 디렉터리를 유지하세요. 위치를 바꾼 경우 새 위치에서 다시 등록합니다. 제거는 `python3 associate.py --remove`입니다.

Linux의 등록 도구에는 `desktop-file-utils`와 `shared-mime-info`가 필요합니다. Windows에서는 사용자 레지스트리의 OpenWithProgids에 등록하며 UserChoice를 변경하지 않습니다.

## 공유 코어와 처리 예산

[공유 C++ 코어](../../shared/papng/README.md)가 두 엔진에서 같은 파일 해석·프레임 복원·랜덤 분포·마스크 동작을 제공합니다. 엔진별 UI와 텍스처 처리는 별도입니다. 읽기와 합성은 작업 스레드에서 수행하고 화면에는 완성된 스냅샷을 전달합니다.

뷰어의 파일·RGBA 캔버스 예산은 각각 128 MiB, JSON5는 8 MiB, 원본 프레임 캐시와 합성 캐시는 각각 32 MiB, 마스크 캐시는 16 MiB입니다. 작업 버퍼·PNG 필터 데이터·엔진·화면 텍스처 등은 추가 메모리를 사용합니다. 이 수치는 포맷 한도나 프로세스 전체 메모리 상한이 아닙니다. 배경은 64 MiB·32메가픽셀까지입니다.

현재 대상은 Linux·Windows x86_64이며 Android 빌드는 포함하지 않습니다. 전문 ICC 색상 관리, 여러 단계의 부속 결합, 이미지 내보내기·편집·저장은 이 뷰어의 범위에 포함하지 않습니다.

## 검증 환경

Linux x86_64에서 독립 실행 빌드와 샘플 재생을 검증했습니다. Windows용 설정과 빌드 진입점은 포함되어 있지만 Windows 빌드·실행 및 파일 연결은 아직 검증하지 않았습니다.

## 라이선스

앱과 공유 코어는 저장소의 [MIT License](../../../LICENSE)를 따릅니다. 배포 파일에는 stb_image와 miniz의 라이선스도 포함됩니다. 각 엔진 런타임의 사용·배포 조건은 해당 엔진의 라이선스를 따릅니다.
