# PAPNG Converter

Linux·Windows용 영상 → PAPNG 변환기입니다. Qt Quick 마법사에서 MP4·WebM·GIF의 구간과 크기를 선택하고, 결과를 비교·재생한 뒤 PAPNG 1.1로 저장합니다. Android는 대상에 포함하지 않습니다.

## 사용 흐름

1. **파일 선택:** 파일 선택기, 창으로 끌어놓기, 실행 인자로 파일 경로 전달을 지원합니다.
2. **사용 구간:** 시간 슬라이더와 이전·다음 원본 프레임으로 시작·끝을 정합니다. 처음에는 GIF 전체 구간(최대 60초), MP4·WebM 앞부분 최대 3초를 선택합니다.
3. **크기와 자르기:** 미리보기에서 영역을 드래그하거나 좌표를 입력합니다. 출력 크기는 긴 변 최대 128픽셀로 시작합니다. 최근접 또는 Lanczos 축소를 선택합니다.
4. **프레임과 시간:** 기본값은 원본 프레임 시간 유지입니다. 선택한 경우에만 일정한 FPS로 다시 샘플링합니다. 동일한 연속 프레임은 표시 시간을 더해 합칩니다. 유사 프레임 병합은 오차를 직접 지정했을 때만 적용합니다.
5. **색상과 투명도:** 원본 색상 유지가 기본입니다. 선택적으로 구간 전체의 공통 팔레트, 고정 패턴 디더링, 단색 배경 제거를 사용합니다.
6. **확인과 저장:** 자르기·크기 조정 전 원본과 변환 결과를 나란히 재생합니다. 파일 크기와 프레임 수를 확인하고 저장합니다. 결과는 기존 PAPNG 편집기의 열기 기능으로 불러올 수 있습니다.

이전 단계로 돌아가도 값은 유지됩니다. 설정을 바꾸면 이전 변환 결과를 무효화하므로 다시 미리보기를 만들어야 저장할 수 있습니다. 변환·저장은 별도 작업에서 수행하며 취소할 수 있습니다. 완료되지 않은 출력으로 기존 파일을 덮어쓰지 않습니다.

단축키: `Ctrl+O` 파일 열기, 결과 화면에서 `Space` 재생·정지, 작업 중 `Esc` 취소.

GIF의 0 지연은 디코딩 타임스탬프와 일치하도록 100ms로 정규화하며, 0이 아닌 지연은 유지합니다. 음성은 내보내지 않습니다. MP4/WebM에 이미 소실된 색상·투명도·프레임 간격을 자동으로 복구하지 않습니다. 파일에 존재하는 알파는 유지하며, VP8/VP9 알파는 FFmpeg의 libvpx 디코더를 사용합니다. 미리보기의 타이머 정확도는 화면 갱신 주기에 영향을 받지만, 파일은 APNG의 16비트 유리수 지연으로 기록합니다.

## 처리 한도

이 값은 **변환기**의 작업 예산이며 PAPNG 명세의 제한을 바꾸지 않습니다.

- 원본 크기: 8,294,400픽셀 이하. 원본 전체 길이는 제한하지 않지만 유효한 길이를 읽을 수 있어야 합니다.
- 선택 구간: 0초 초과, 최대 60초.
- 출력 크기: 각 변 1~512픽셀.
- 결과: 최대 600프레임, 비압축 RGBA 합계 64 MiB.
- 중간 디코딩: 최대 10,000프레임, RGBA 256 MiB. 디코딩 프레임은 임시 파일로 순차 저장합니다.
- 정보·썸네일 조회 15초, 구간 디코딩 180초의 제한 시간이 있습니다.

PAPNG 저장은 RGBA8, 전체 프레임 SOURCE 합성, 기본 확장값을 사용합니다. PNG의 다섯 고정 필터와 행별 적응 필터를 무손실 압축해 가장 작은 후보를 저장합니다. 마스크·소켓·프레임 제어는 편집기에서 추가할 수 있습니다. 변환 옵션과 원본 **파일명**만 JSON5 호환 메타데이터에 남기며 전체 경로는 저장하지 않습니다.

## 개발과 빌드

필요 항목: C++17 컴파일러, Python 3.10+, CMake 3.22+, Qt 6.10+의 Core·Gui·Quick·QuickControls2·Concurrent. Linux·Windows 각각 해당 OS에서 빌드합니다. FFmpeg와 ffprobe는 개발 실행 시 `PAPNG_FFMPEG_DIR` 또는 PATH에서 찾습니다. 배포 폴더에서는 동봉된 `tools/`를 먼저 사용합니다.

Ubuntu 개발 환경:

```sh
sudo apt install build-essential cmake ninja-build patchelf qt6-base-dev qt6-declarative-dev ffmpeg \
  qml6-module-qtquick qml6-module-qtquick-window qml6-module-qtquick-controls \
  qml6-module-qtquick-dialogs qml6-module-qtquick-layouts qml6-module-qtquick-templates \
  qml6-module-qtqml-workerscript
python3 tools/converter/build.py
builds/linux/papng-converter/papng-converter
```

Windows는 Qt SDK의 MSVC 2022 64비트 구성과 CMake, Python을 준비하고 해당 개발자 터미널에서 실행합니다.

```powershell
python tools/converter/build.py --qt-prefix C:/Qt/6.10.2/msvc2022_64
```

멀티 구성 생성기를 사용하면 실행 파일이 `Release/` 아래에 생성될 수 있습니다. 모든 빌드와 배포 결과는 저장소의 `builds/<platform>/papng-converter/` 아래에 있습니다.

## 실행 폴더 만들기

```sh
python3 tools/converter/build.py --package --ffmpeg-dir /path/to/ffmpeg/bin
```

Qt 배포 도구로 QML·라이브러리·플러그인을 모으고 FFmpeg·ffprobe를 `package/tools/`에 넣습니다. Linux는 두 영상 도구의 공유 라이브러리도 수집합니다. Linux의 진입점은 `package/PAPNG-Converter.sh`, Windows는 `package/papng-converter.exe`입니다. **파일 하나가 아니라 package 폴더 전체**를 전달합니다. Linux 배포본은 빌드한 배포판의 glibc 이상이 필요하며 모든 배포판에서의 실행을 보장하지 않습니다.

Windows 패키징에는 선택한 FFmpeg 배포본의 라이선스 자료도 지정합니다:

```powershell
python tools/converter/build.py --package --qt-prefix C:/Qt/6.10.2/msvc2022_64 `
  --ffmpeg-dir C:/ffmpeg/bin --ffmpeg-notices C:/ffmpeg/doc
```

FFmpeg에는 MP4/H.264, WebM/VP8/VP9, GIF 디코더, libvpx 알파 디코더, PNG·rawvideo 출력, crop·scale·setsar·format·showinfo 필터가 필요합니다. [의존성과 배포 안내](THIRD_PARTY.md)를 참고하세요.

## 터미널에서 변환

인자 없이 실행하거나 파일 경로 하나만 전달하면 GUI가 열립니다. **변환 옵션을 전달하면 창을 만들지 않고 실행**합니다. 디스플레이가 없는 터미널에서도 사용할 수 있으며 `--cli`로 명시할 수도 있습니다. 별도 CLI 실행 파일은 필요하지 않습니다.

저장소에서 빌드한 Linux 실행 폴더를 사용하는 예:

```sh
# 도움말과 전체 옵션
./builds/linux/papng-converter/package/PAPNG-Converter.sh --help

# 원본 전체 변환: 원본 프레임 시간 유지, 긴 변 최대 128픽셀
./builds/linux/papng-converter/package/PAPNG-Converter.sh \
  -i animation.webm -o animation.papng

# 5초 위치부터 2초 동안 자르고 64×64픽셀로 변환
./builds/linux/papng-converter/package/PAPNG-Converter.sh \
  animation.mp4 -o clip.papng --start 5 --duration 2 --size 64x64

# 저장하지 않고 해상도·시간·코덱·알파 정보 확인
./builds/linux/papng-converter/package/PAPNG-Converter.sh --info -i animation.gif
```

이하 예제의 `papng-converter`는 위 실행 경로 또는 PATH에 등록한 실행 파일을 뜻합니다. Windows에서는 `papng-converter.exe`에 같은 옵션을 전달합니다.

```sh
# 자르기, FPS, 공통 팔레트와 디더링
papng-converter -i animation.mp4 -o pixel.papng \
  --start 0.2 --end 2.8 --crop 0,0,640,480 --size 128x96 \
  --fps 12 --colors 32 --dither

# 단색 배경 제거; # 문자가 셸 주석으로 해석되지 않도록 따옴표 사용
papng-converter -i green.webm -o transparent.papng \
  --key-color '#00ff00' --key-tolerance 20

# 스크립트용: 진행 메시지를 숨기고 JSON 결과를 파일로 기록
papng-converter --cli -i animation.gif -o result.papng --quiet > result.json
```

입력은 `-i`, `--input`, `--convert` 또는 위치 인자 중 하나로 지정합니다. 출력은 `-o` 또는 `--output`으로 지정하며 필수입니다. 여러 입력을 동시에 지정하면 오류를 반환합니다. 경로에 공백이 있으면 따옴표로 감쌉니다.

- **구간:** `--start`는 시작 시각, `--end`는 절대 끝 시각, `--duration`은 시작부터의 길이입니다. 단위는 초이며 소수를 허용합니다. `--end`와 `--duration`은 동시에 사용할 수 없습니다. CLI는 끝 시각 생략 시 **원본 끝까지** 변환합니다. 선택 구간이 60초를 넘으면 오류를 반환하므로 직접 구간을 지정해야 합니다. GUI는 GIF 전체(최대 60초), MP4·WebM은 첫 3초를 기본 선택합니다.
- **크기:** `--crop x,y,w,h`로 원본을 자르고 `--size WxH`로 출력 크기를 정합니다. 크기 생략 시 자른 영역의 비율을 유지하며 긴 변 최대 128픽셀로 줄입니다.
- **시간:** `--fps 1..60`으로 재샘플링합니다. 생략하거나 0이면 원본 시간을 유지합니다. `--plays 0..4294967295`로 반복 횟수를 지정하며 기본값 0은 계속 반복합니다.
- **병합:** 동일한 연속 프레임은 기본으로 합칩니다. `--no-merge`로 해제하고, `--merge-tolerance 0..16`으로 유사 프레임의 채널별 허용 오차를 지정합니다. 두 옵션은 함께 사용할 수 없습니다.
- **색상:** `--colors 2..256`은 구간 전체의 공통 팔레트입니다. 0 또는 생략 시 원본 색상을 유지합니다. `--dither`에는 색상 수 설정이 필요합니다. `--smooth`는 최근접 대신 Lanczos를 사용합니다.
- **배경:** `--key-color`와 선택적인 `--key-tolerance 0..255`로 단색 배경을 투명하게 바꿉니다. 허용 오차 기본값은 24입니다.
- **파일 교체:** 기존 출력 파일 교체에는 `--overwrite`가 필요합니다. 변환 실패·취소 시 기존 파일은 유지합니다.
- **조회·출력:** `--info`는 입력 정보만 JSON으로 출력합니다. 변환 옵션과 함께 사용할 수 없습니다. `-q`/`--quiet`는 진행 메시지를 숨기며 오류와 최종 JSON은 유지합니다. `-h`/`--help`, `-v`/`--version`도 지원합니다.

성공한 변환은 표준 출력에 JSON 객체 하나를 남깁니다. `output`, `width`, `height`, `frames`, `duration`, `bytes`, `memory` 등으로 결과를 확인할 수 있습니다. `bytes`와 `memory`는 바이트, `duration`은 초입니다. 진행률·단계·오류는 표준 오류로 출력되므로 결과 JSON에 섞이지 않습니다.

종료 코드는 성공 **0**, 입력·도구·변환·저장 실패 **1**, 옵션 오류 **2**, `Ctrl+C` 취소 **130**, `SIGTERM` 종료 **143**입니다. GUI와 같은 변환 한도와 원자적 저장 처리를 사용합니다.

## 구조

- `qml/`: 여섯 단계 UI, 픽셀 미리보기, 숫자 입력.
- `src/cli.*`: GUI 초기화 없는 옵션 파싱, 정보 조회, 변환·종료 코드.
- `src/controller.*`: UI 상태, 취소 가능한 백그라운드 작업, 미리보기 수명 관리.
- `src/pipeline.*`: FFmpeg 실행, 프레임 시간, 픽셀화·팔레트·병합.
- `src/writer.cpp`: PAPNG 1.1 및 무손실 PNG 저장.
- `tools/converter/build.py`: 저장소 루트에서 사용하는 공개 빌드·배포 진입점.

## 크기와 원본 비교

비율 유지 상태에서 1x~16x 슬라이더로 자르기 영역의 너비·높이를 나눕니다. 소수 픽셀은 반올림하며 최소 1픽셀입니다. 1x는 선택 영역과 같은 크기입니다. 512픽셀 한도를 넘으면 경고하고 변환 시 한도를 검사합니다. 너비·높이를 직접 입력하면 배수 적용을 해제합니다.

배경색 선택에서는 원본 프레임의 픽셀을 클릭하거나 기존 색상 대화상자를 열 수 있습니다. 이전·다음 프레임으로 이동하며 색을 고를 수도 있습니다.

확인과 저장의 왼쪽은 자르기·크기 조정·색상 처리 전 원본 프레임입니다. 패널에 맞추어 표시하지만 원본 해상도를 유지합니다. 오른쪽 결과와 같은 시점의 대표 프레임을 비교하며, 원본은 비동기로 읽고 최대 128 MiB 캐시를 사용합니다. 캐시에 없는 큰 프레임을 읽는 동안 재생이 잠시 기다릴 수 있습니다.
