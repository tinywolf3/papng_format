# PAPNG

[한국어](#한국어) · [English](#english)

## 한국어

PAPNG는 게임용 픽셀아트 리소스의 편집·저장·공유를 위한 **APNG 기반 이미지 포맷**입니다. 파일 확장자는 `.papng`이며, APNG 컨테이너에 픽셀아트 편집과 애니메이션 재생을 위한 정보를 추가합니다.

### 주요 기능

- **16비트 마스크:** 원본 RGBA를 보존하고, 별도 압축 배열의 마스크 인덱스별로 색상각 변화량을 적용합니다. 픽셀별 알파를 유지하며 최대 32,768개 마스크를 지원합니다.
- **프레임 제어:** 고정·랜덤 지연, 상대·절대 이동, 랜덤 이동을 지원합니다.
- **공유 랜덤 분포:** 균등분포, 범위 기반 분포, 숫자와 가중치 배열을 여러 프레임에서 재사용합니다.
- **출력 힌트:** 출력 크기, 바운딩 박스, 픽셀 배수와 피벗을 바이너리 확장에 저장합니다.
- **JSON5 메타데이터:** 애니메이션 구간, 마스크 그룹과 프레임별 소켓 위치·회전을 저장합니다. 주석과 추가 멤버로 개발자 참고 정보를 함께 기록할 수 있습니다.

일반 APNG 디코더에서도 컨테이너를 읽을 수 있습니다. 원본 색상과 알파는 그대로 보이며, 색상각 편집과 확장 재생 동작에는 PAPNG를 지원하는 구현이 필요합니다.

### 포맷 명세

- [PAPNG 1.0 한국어 명세 — 기준 문서](spec/PAPNG-1.0.ko.md)
- [PAPNG 1.0 영어 명세 — 번역본](spec/PAPNG-1.0.en.md)

**한국어 명세가 기본이자 기준 문서입니다.** 두 언어판 사이에 해석 차이가 있으면 한국어판을 따릅니다. 명세는 Markdown으로 관리합니다.

### 샘플과 편집기·뷰어

[웹뷰어 데모 바로 열기](https://tinywolf3.github.io/papng_format/) — 설치 없이 샘플을 재생하고 마스크 색상을 바꿔 볼 수 있습니다.

- [기능별 PAPNG 샘플 9개](samples/README.md): 마스크 색상, 모든 분포·프레임 제어, 숨김 프레임 합성, 부분 프레임 복원과 메타데이터를 확인할 수 있습니다.
- [Godot 픽셀 편집기](demos/godot/editor/README.md): Linux·Windows·Android용 픽셀·마스크 편집, 프레임·소켓·클립 구성, 이미지 가져오기와 PAPNG 저장을 지원합니다.
- [Godot 이미지 뷰어](demos/godot/viewer/README.md): Linux·Windows·Android용 파일 선택·연결 프로그램, 마스크 색상 변경, 위치 표시와 소켓 부속 미리보기를 지원합니다.
- [Unity 이미지 뷰어](demos/unity/viewer/README.md): Linux·Windows용 독립 실행 뷰어와 마스크·소켓·배경 조작을 제공합니다.
- [Unreal 이미지 뷰어](demos/unreal/viewer/README.md): Linux·Windows용 Slate 뷰어와 엔진 색상 선택 대화상자를 제공합니다.
- [TypeScript 웹 뷰어](demos/web/viewer/README.md): 로컬 파일 재생, 마스크 색상각 변화량 편집, 클립 선택, 소켓에 부속 연결과 점프 대상 우선 캐시를 시험할 수 있습니다.

Node.js 22.12 이상에서 `npm ci` 후 `npm run dev`로 실행합니다. 디코더와 플레이어는 포맷 동작을 확인하기 위한 실험용 구현입니다.

### 라이선스

[MIT License](LICENSE)

## English

PAPNG is an **APNG-based image format** for editing, storing, and sharing pixel-art resources for games. Its file extension is `.papng`.

It preserves original RGBA and adds independently compressed, shareable 16-bit mask planes, reusable random distributions, frame controls, and optional JSON5 metadata including named sockets with per-frame position and rotation. Comments and additional members can carry developer notes. Up to 32,768 logical masks accept runtime hue offsets while keeping per-pixel alpha. Ordinary APNG decoders show original colors; hue edits and extended playback require a PAPNG-aware implementation.

### Specification

- [PAPNG 1.0 — Korean normative specification](spec/PAPNG-1.0.ko.md)
- [PAPNG 1.0 — English translation](spec/PAPNG-1.0.en.md)

**The Korean specification is the default and normative edition.** If the editions differ in interpretation, the Korean edition takes precedence. Specifications are maintained in Markdown.

### Samples, editor and viewers

[Open the web viewer demo](https://tinywolf3.github.io/papng_format/) to play samples and adjust mask colors without installation.

- [Nine PAPNG samples](samples/README.md) demonstrate mask colors, every distribution and control type, hidden-frame composition, partial-frame restoration, and socket attachments.
- The [Godot pixel editor](demos/godot/editor/README.md) provides Linux/Windows/Android pixel and mask editing, animation authoring, image import, and PAPNG saving.
- The [standalone Godot viewer](demos/godot/viewer/README.md) opens PAPNG, PNG and APNG on Linux, Windows and Android, with mask colors, overlays and a socket attachment preview.
- The [Unity viewer](demos/unity/viewer/README.md) and [Unreal viewer](demos/unreal/viewer/README.md) provide standalone Linux/Windows applications with a shared C++ PAPNG playback core, mask colors, backgrounds, and socket attachments.
- The [TypeScript web viewer](demos/web/viewer/README.md) provides local playback, hue-offset editing, clip selection, and a cache that favors jump targets.

With Node.js 22.12 or later, run `npm ci` and `npm run dev`. The decoder and player are experimental implementations for exploring the format.

### License

[MIT License](LICENSE)
