# PAPNG

[한국어](#한국어) · [English](#english)

## 한국어

PAPNG는 게임용 픽셀아트 리소스의 편집·저장·공유를 위한 **APNG 기반 이미지 포맷**입니다. 파일 확장자는 `.papng`이며, 기존 APNG 컨테이너에 픽셀아트 편집과 애니메이션 재생을 위한 정보를 추가합니다.

### 주요 기능

- **16비트 마스크:** 원본 RGBA를 보존하고, 별도 압축 배열의 마스크 인덱스별로 색상각 변화량을 적용합니다. 픽셀별 알파를 유지하며 최대 32,768개 마스크를 지원합니다.
- **프레임 제어:** 고정·랜덤 지연, 상대·절대 이동, 랜덤 이동을 지원합니다.
- **공유 랜덤 분포:** 균등분포, 범위 기반 분포, 숫자와 가중치 배열을 여러 프레임에서 재사용합니다.
- **선택적 메타데이터:** 출력 크기, 바운딩 박스, 픽셀 배수, 피벗, 애니메이션 구간과 마스크 그룹을 저장합니다.

일반 APNG 디코더에서도 컨테이너를 읽을 수 있습니다. 원본 색상과 알파는 그대로 보이며, 색상각 편집과 확장 재생 동작에는 PAPNG를 지원하는 구현이 필요합니다.

### 포맷 명세

- [PAPNG 1.0 한국어 명세 — 기준 문서](spec/PAPNG-1.0.ko.md)
- [PAPNG 1.0 영어 명세 — 번역본](spec/PAPNG-1.0.en.md)

**한국어 명세가 기본이자 기준 문서입니다.** 두 언어판 사이에 해석 차이가 있으면 한국어판을 따릅니다. 명세는 Markdown으로 관리합니다.

### 샘플과 웹 뷰어

- [기능별 PAPNG 샘플 7개](samples/README.md): 마스크 색상, 모든 분포·프레임 제어, 숨김 프레임 합성, 부분 프레임 복원과 메타데이터를 확인할 수 있습니다.
- [TypeScript 웹 뷰어](demos/web/viewer/README.md): 로컬 파일 재생, 마스크 색상각 변화량 편집, 클립 선택과 점프 대상 우선 캐시를 시험할 수 있습니다.

Node.js 22.12 이상에서 `npm ci` 후 `npm run dev`로 실행합니다. 디코더와 플레이어는 포맷 동작을 확인하기 위한 실험용 구현입니다.

### 문서 검증

Python 3.10 이상이 필요합니다. 표준 라이브러리만 사용하므로 별도 패키지 설치는 필요하지 않습니다.

```sh
python3 tools/check_spec.py
```

한국어·영어 명세의 바이너리 예제, 정수 범위, 필드 오프셋과 메타데이터 예제를 검증합니다. 두 언어판의 절 구성·구조 선언·예제 일치 여부와 Markdown 문서의 로컬 링크·앵커도 확인합니다.

### 라이선스

[MIT License](LICENSE)

## English

PAPNG is an **APNG-based image format** for editing, storing, and sharing pixel-art resources for games. Its file extension is `.papng`.

It preserves original RGBA and adds independently compressed, shareable 16-bit mask planes, reusable random distributions, frame controls, and optional metadata. Up to 32,768 logical masks accept runtime hue offsets while keeping per-pixel alpha. Ordinary APNG decoders show original colors; hue edits and extended playback require a PAPNG-aware implementation.

### Specification

- [PAPNG 1.0 — Korean normative specification](spec/PAPNG-1.0.ko.md)
- [PAPNG 1.0 — English translation](spec/PAPNG-1.0.en.md)

**The Korean specification is the default and normative edition.** If the editions differ in interpretation, the Korean edition takes precedence. Specifications are maintained in Markdown.

### Samples and viewer

- [Seven PAPNG samples](samples/README.md) demonstrate mask colors, every distribution and control type, hidden-frame composition, partial-frame restoration, and metadata.
- The [TypeScript web viewer](demos/web/viewer/README.md) provides local playback, hue-offset editing, clip selection, and a cache that favors jump targets.

With Node.js 22.12 or later, run `npm ci` and `npm run dev`. The decoder and player are experimental implementations for exploring the format.

### Documentation checks

Python 3.10 or later is required. Only the standard library is used; no additional packages are needed.

```sh
python3 tools/check_spec.py
```

The checker validates binary vectors, integer boundaries, field offsets, and example metadata in both editions. It also verifies matching section structure, layout declarations, and examples across editions, plus local Markdown links and anchors.

### License

[MIT License](LICENSE)
